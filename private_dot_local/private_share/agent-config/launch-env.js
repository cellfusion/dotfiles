'use strict'

// agent ラッパーが起動前に設定する値を決める。provider id から environment と
// provider family を引き、family の設定ディレクトリの変数を materialize する。
// ラッパー本体は exec で自分を置き換える必要があるため bash で書いてある。この
// module は値を stdout へ書くだけで、CLI を起動しない。

const fs = require('node:fs')
const path = require('node:path')
const { expandDirectoryPattern } = require('./directory-setup.js')
const { validateConfig } = require('./config-validator.js')
const { selectEnvironment } = require('./resolver.js')

class LaunchError extends Error {}

function fail(message) {
  throw new LaunchError(message)
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function configHome() {
  const explicit = process.env.XDG_CONFIG_HOME
  if (typeof explicit === 'string' && explicit.length > 0) {
    if (!path.isAbsolute(explicit)) fail('XDG_CONFIG_HOME: 絶対 path が必要である')
    return explicit
  }
  const home = process.env.HOME
  if (typeof home !== 'string' || !path.isAbsolute(home)) fail('HOME: 絶対 path が必要である')
  return path.join(home, '.config')
}

function inputPath() {
  const explicit = process.env.AGENT_CONFIG
  if (typeof explicit === 'string' && explicit.length > 0) {
    if (!path.isAbsolute(explicit)) fail('AGENT_CONFIG: 絶対 path が必要である')
    return explicit
  }
  return path.join(configHome(), 'chezmoi', 'agent-config.json')
}

// 起動前に schema と semantics の全体を検査する。Project routing、environment
// eligibility、provider assignment のどれか一つでも不正なら CLI を起動しない。
function readConfig() {
  const file = inputPath()
  let text
  try {
    text = fs.readFileSync(file, 'utf8')
  } catch {
    fail(`${file}: 読めない`)
  }
  try {
    return validateConfig(text).config
  } catch (error) {
    fail(`${file}: ${error instanceof Error ? error.message : '設定が不正である'}`)
  }
}

// id の作り方と集合は paseo-providers.js の materializeProviderId と
// generatedProviderEntries に合わせる。全 family が既定環境の id を持ち、既定環境
// でない environment は providers に挙げた family の id を持つ。
function providerIndex(config) {
  const defaultEnvironment = config.defaults.environment
  if (!Object.prototype.hasOwnProperty.call(config.environments, defaultEnvironment)) {
    fail(`defaults.environment ${defaultEnvironment}: environments にない`)
  }
  const byId = new Map()
  const add = (family, environment) => {
    const id = environment === defaultEnvironment ? family : `${family}-${environment}`
    const previous = byId.get(id)
    if (previous === undefined) {
      byId.set(id, { family, environment })
    } else if (previous.family !== family || previous.environment !== environment) {
      fail(`provider id ${id}: 2 つの組から materialize される`)
    }
  }
  for (const family of Object.keys(config.providers)) add(family, defaultEnvironment)
  for (const [environment, definition] of Object.entries(config.environments)) {
    if (environment === defaultEnvironment) continue
    if (!isObject(definition) || !Array.isArray(definition.providers)) {
      fail(`environments.${environment}: providers が配列でない`)
    }
    for (const family of definition.providers) {
      if (typeof family !== 'string' ||
          !Object.prototype.hasOwnProperty.call(config.providers, family)) {
        fail(`environments.${environment}: 未知の provider family がある`)
      }
      add(family, environment)
    }
  }
  return byId
}

function assignments(config, entry) {
  const definition = config.providers[entry.family]
  if (!isObject(definition)) fail(`provider family ${entry.family}: 定義が不正である`)
  const lines = [`binary ${entry.family}`, `env AGENT_ENV ${entry.environment}`]
  if (definition.environmentVariable !== undefined) {
    lines.push(`env ${definition.environmentVariable} ${entry.environment}`)
  }
  const setup = definition.setup
  if (setup === null || setup === undefined) return lines
  if (!isObject(setup) || !isObject(setup.configDirectoryEnv) || !isObject(setup.directoryPattern)) {
    fail(`provider family ${entry.family}: setup が不正である`)
  }
  const pattern = entry.environment === config.defaults.environment
    ? setup.directoryPattern.primary
    : setup.directoryPattern.nonPrimary
  const directory = expandDirectoryPattern(
    pattern,
    configHome(),
    entry.environment,
    `provider family ${entry.family}`,
  )
  for (const key of Object.keys(setup.configDirectoryEnv)) lines.push(`env ${key} ${directory}`)
  return lines
}

function familyEntry(config, family, explicitEnvironment) {
  if (!Object.prototype.hasOwnProperty.call(config.providers, family)) {
    fail(`provider family ${family}: agent-config.json にない`)
  }
  const parentEnvironment = typeof process.env.AGENT_ENV === 'string' && process.env.AGENT_ENV.length > 0
    ? process.env.AGENT_ENV
    : undefined
  const selected = selectEnvironment(config, process.cwd(), explicitEnvironment, parentEnvironment)
  for (const warning of selected.warnings) process.stderr.write(`agent: ${warning}\n`)
  const environment = config.environments[selected.environment]
  if (!environment.providers.includes(family)) {
    fail(`provider family ${family}: environment ${selected.environment} に configured されていない`)
  }
  return { family, environment: selected.environment }
}

function main(argv) {
  const config = readConfig()
  const byId = providerIndex(config)
  const ids = [...byId.keys()].sort()
  if (argv.length === 1 && argv[0] === '--list') {
    process.stdout.write(`${ids.join('\n')}\n`)
    return
  }
  let entry
  if (argv.length === 1 && !argv[0].startsWith('--')) {
    entry = byId.get(argv[0])
  } else if (argv.length === 2 && argv[0] === '--provider') {
    entry = byId.get(argv[1])
  } else if (argv.length === 2 && argv[0] === '--family') {
    entry = familyEntry(config, argv[1], undefined)
  } else if (argv.length === 4 && argv[0] === '--family' && argv[2] === '--environment') {
    entry = familyEntry(config, argv[1], argv[3])
  } else {
    fail('引数は --provider <id>、--family <family> [--environment <environment>]、--list のいずれかである')
  }
  if (entry === undefined) {
    const requested = argv[0] === '--provider' ? argv[1] : argv[0]
    process.stderr.write(`agent: provider id ${requested}: agent-config.json にない\n`)
    process.stderr.write(`agent: 使える provider id: ${ids.join(' ')}\n`)
    process.exit(2)
  }
  process.stdout.write(`${assignments(config, entry).join('\n')}\n`)
}

try {
  main(process.argv.slice(2))
} catch (error) {
  process.stderr.write(`agent: ${error instanceof Error ? error.message : '起動を解決できない'}\n`)
  process.exit(2)
}
