#!/usr/bin/env bash
# Pi の環境別設定ディレクトリを agent-config、Paseo、直接起動で共有することを検証する。
set -u

source "$(dirname "$0")/lib/assert.sh"

if node - "$CHEZMOI_SOURCE" <<'NODE'
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')
const source = process.argv[2]
const share = path.join(source, 'private_dot_local/private_share/agent-config')
const { validateConfig } = require(path.join(share, 'config-validator.js'))
const { resolveExport } = require(path.join(share, 'resolver.js'))
const { materializePaseoProviders } = require(path.join(share, 'paseo-providers.js'))
const { expandDirectoryPattern } = require(path.join(share, 'directory-setup.js'))

const configValue = JSON.parse(fs.readFileSync(path.join(share, 'agent-config.sample.json'), 'utf8'))
configValue.providers.pi.setup = {
  configDirectoryEnv: { PI_CODING_AGENT_DIR: 'pi' },
  directoryPattern: {
    primary: '$HOME/.pi/agent',
    nonPrimary: '$HOME/.pi/agent-<environment>',
  },
  symlinks: ['agents', 'extensions'],
  preservedMutable: [],
  existingPathPolicy: 'reject-real-or-wrong-symlink',
}
configValue.environments.lab.providers.push('pi')
const config = validateConfig(JSON.stringify(configValue)).config

const home = fs.mkdtempSync(path.join(os.tmpdir(), 'agent-pi-home-'))
const xdg = path.join(home, '.config')
process.env.HOME = home
process.env.XDG_CONFIG_HOME = xdg

if (expandDirectoryPattern('$HOME/.pi/agent', xdg, 'primary', 'pi') !== path.join(home, '.pi/agent')) {
  throw new Error('Pi primary directory did not expand under HOME')
}
if (expandDirectoryPattern('$HOME/.pi/agent-<environment>', xdg, 'lab', 'pi') !== path.join(home, '.pi/agent-lab')) {
  throw new Error('Pi non-primary directory did not expand under HOME')
}

const materialized = materializePaseoProviders(resolveExport(config))
if (materialized.providers.pi.env.PI_CODING_AGENT_DIR !== path.join(home, '.pi/agent')) {
  throw new Error(`default Pi env is wrong: ${JSON.stringify(materialized.providers.pi)}`)
}
if (materialized.providers['pi-lab'].env.PI_CODING_AGENT_DIR !== path.join(home, '.pi/agent-lab')) {
  throw new Error(`lab Pi env is wrong: ${JSON.stringify(materialized.providers['pi-lab'])}`)
}

const configPath = path.join(home, 'agent-config.json')
fs.writeFileSync(configPath, JSON.stringify(configValue))
const launch = spawnSync(process.execPath, [path.join(share, 'launch-env.js'), 'pi-lab'], {
  env: { ...process.env, AGENT_CONFIG: configPath },
  encoding: 'utf8',
})
if (launch.status !== 0) throw new Error(`launch-env failed: ${launch.stderr}`)
const assignments = new Map(launch.stdout.trim().split('\n').map((line) => {
  const [kind, key, ...rest] = line.split(' ')
  return [kind === 'binary' ? 'binary' : key, kind === 'binary' ? key : rest.join(' ')]
}))
if (assignments.get('binary') !== 'pi' || assignments.get('AGENT_ENV') !== 'lab' ||
    assignments.get('PI_CODING_AGENT_DIR') !== path.join(home, '.pi/agent-lab')) {
  throw new Error(`launch-env Pi assignments are wrong: ${launch.stdout}`)
}
NODE
then
  pass 'Pi uses an isolated directory for non-primary environments'
else
  fail_check 'Pi uses an isolated directory for non-primary environments'
fi
assert_summary
