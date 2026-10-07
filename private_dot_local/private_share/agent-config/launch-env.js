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
  if (argv.length !== 2 && argv.length !== 4) fail('expected --family claude|codex [--environment <name>]')
  if (argv[0] !== '--family' || !['claude', 'codex'].includes(argv[1]) ||
      (argv.length === 4 && (argv[2] !== '--environment' || !argv[3]))) {
    fail('expected --family claude|codex [--environment <name>]')
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
