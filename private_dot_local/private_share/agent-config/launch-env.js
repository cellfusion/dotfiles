'use strict'

// agent ラッパーが起動前に設定する値を決める。provider id から environment と
// provider family を引き、family の設定ディレクトリの変数を materialize する。
// ラッパー本体は exec で自分を置き換える必要があるため bash で書いてある。この
// module は値を stdout へ書くだけで、CLI を起動しない。

const fs = require('node:fs')
const path = require('node:path')
const { expandDirectoryPattern } = require('./directory-setup.js')

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

// 正本の全体は検査しない。起動に要るのは defaults.environment、providers、
// environments の 3 つだけであり、selection の形が変わっても起動は動き続ける。
function readConfig() {
  const file = inputPath()
  let text
  try {
    text = fs.readFileSync(file, 'utf8')
  } catch {
    fail(`${file}: 読めない`)
  }
  let config
  try {
    config = JSON.parse(text)
  } catch {
    fail(`${file}: JSON として読めない`)
  }
  if (!isObject(config) || !isObject(config.providers) || !isObject(config.environments) ||
      !isObject(config.defaults) || typeof config.defaults.environment !== 'string' ||
      config.defaults.environment.length === 0) {
    fail(`${file}: shape が不正である`)
  }
  return config
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

function main(argv) {
  if (argv.length !== 1) fail('引数は provider id か --list を 1 つだけ取る')
  const config = readConfig()
  const byId = providerIndex(config)
  const ids = [...byId.keys()].sort()
  if (argv[0] === '--list') {
    process.stdout.write(`${ids.join('\n')}\n`)
    return
  }
  const entry = byId.get(argv[0])
  if (entry === undefined) {
    process.stderr.write(`agent: provider id ${argv[0]}: agent-config.json にない\n`)
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
