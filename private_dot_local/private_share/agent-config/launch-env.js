'use strict'

const fs = require('node:fs')
const path = require('node:path')
const { expandDirectoryPattern } = require('./directory-setup.js')
const { validateConfig, ConfigError } = require('./config-validator.js')
const { selectEnvironment } = require('./resolver.js')
function fail(message) { throw new ConfigError(message) }
function configHome() {
  if (process.env.XDG_CONFIG_HOME) {
    if (!path.isAbsolute(process.env.XDG_CONFIG_HOME)) fail('XDG_CONFIG_HOME: absolute path is required')
    return process.env.XDG_CONFIG_HOME
  }
  if (!process.env.HOME || !path.isAbsolute(process.env.HOME)) fail('HOME: absolute path is required')
  return path.join(process.env.HOME, '.config')
}
function readConfig() {
  const input = process.env.AGENT_CONFIG || path.join(configHome(), 'chezmoi', 'agent-config.json')
  if (!path.isAbsolute(input)) fail('AGENT_CONFIG: absolute path is required')
  let raw
  try { raw = fs.readFileSync(input, 'utf8') } catch (error) {
    if (error.code === 'ENOENT') return null
    throw error
  }
  return validateConfig(raw).config
}
function main(argv) {
  if (argv.length !== 2 && argv.length !== 4) fail('expected --family claude|codex|omp|opencode|pi [--environment <name>]')
  if (argv[0] !== '--family' || !['claude', 'codex', 'omp', 'opencode', 'pi'].includes(argv[1]) ||
      (argv.length === 4 && (argv[2] !== '--environment' || !argv[3]))) {
    fail('expected --family claude|codex|omp|opencode|pi [--environment <name>]')
  }
  const family = argv[1]
  const config = readConfig()
  if (config === null) {
    if (argv.length === 4) fail('--environment: cannot resolve without agent-config.json')
    process.stdout.write(`binary ${family}\n`)
    return
  }
  if (!Object.prototype.hasOwnProperty.call(config.providers, family)) fail(`CLI ${family}: not configured`)
  const selected = selectEnvironment(config, process.cwd(), argv[3], process.env.AGENT_ENV || undefined)
  for (const warning of selected.warnings) process.stderr.write(`agent: ${warning}\n`)
  if (!config.environments[selected.environment].providers.includes(family)) {
    fail(`CLI ${family}: not configured in environment ${selected.environment}`)
  }
  if (family === 'opencode') {
    process.stdout.write(`binary ${family}\nenv AGENT_ENV ${selected.environment}\n`)
    return
  }
  if (family === 'pi') {
    if (!process.env.HOME || !path.isAbsolute(process.env.HOME)) fail('HOME: absolute path is required')
    const primary = path.join(process.env.HOME, '.pi', 'agent')
    const directory = selected.environment === config.defaults.environment
      ? primary : path.join(process.env.HOME, '.pi', `agent_${selected.environment}`)
    if (directory !== primary) {
      fs.mkdirSync(directory, { recursive: true, mode: 0o700 })
      if (!fs.lstatSync(directory).isDirectory()) fail('pi: environment directory must not be a symlink')
      const auth = path.join(directory, 'auth.json')
      try {
        const entry = fs.lstatSync(auth)
        if (entry.isSymbolicLink()) fail('pi: environment auth.json must not be a symlink')
        try {
          const original = fs.statSync(path.join(primary, 'auth.json'))
          if (entry.dev === original.dev && entry.ino === original.ino) fail('pi: environment auth.json must be independent')
        } catch (error) { if (error.code !== 'ENOENT') throw error }
      } catch (error) { if (error.code !== 'ENOENT') throw error }
      for (const name of ['settings.json', 'keybindings.json', 'mcp.json', 'models.json', 'AGENTS.md',
        'AGENTS.override.md', 'SYSTEM.md', 'APPEND_SYSTEM.md', 'extensions', 'skills', 'prompts', 'themes', 'npm']) {
        const source = path.join(primary, name)
        const destination = path.join(directory, name)
        try { fs.lstatSync(source) } catch (error) { if (error.code === 'ENOENT') continue; throw error }
        try { fs.symlinkSync(path.relative(directory, source), destination) }
        catch (error) { if (error.code !== 'EEXIST') throw error }
      }
    }
    process.stdout.write(`binary pi\nenv AGENT_ENV ${selected.environment}\nenv PI_CODING_AGENT_DIR ${directory}\n`)
    return
  }
  if (family === 'omp') {
    const lines = [
      'binary omp',
      `env AGENT_ENV ${selected.environment}`,
      'unset OMP_PROFILE',
      'unset PI_CODING_AGENT_DIR',
    ]
    if (selected.environment !== config.defaults.environment) lines.push(`env OMP_PROFILE ${selected.environment}`)
    for (const overlay of config.environments[selected.environment].ompConfigOverlays ?? []) {
      lines.push(`arg --config ${overlay}`)
    }
    process.stdout.write(`${lines.join('\n')}\n`)
    return
  }
  const setup = config.providers[family].setup
  const pattern = selected.environment === config.defaults.environment
    ? setup.directoryPattern.primary : setup.directoryPattern.nonPrimary
  const directory = expandDirectoryPattern(pattern, configHome(), selected.environment, family)
  const lines = [`binary ${family}`, `env AGENT_ENV ${selected.environment}`]
  for (const key of Object.keys(setup.configDirectoryEnv)) lines.push(`env ${key} ${directory}`)
  process.stdout.write(`${lines.join('\n')}\n`)
}
try { main(process.argv.slice(2)) } catch (error) {
  process.stderr.write(`agent: ${error instanceof Error ? error.message : 'failed'}\n`)
  process.exitCode = 2
}
