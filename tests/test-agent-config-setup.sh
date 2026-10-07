#!/usr/bin/env bash
# Validate the environment-only CLI and safe shared-file setup without touching live data.
set -u
source "$(dirname "$0")/lib/assert.sh"

if node - "$CHEZMOI_SOURCE" <<'NODE'
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')
const source = process.argv[2]
const command = path.join(source, 'private_dot_local/bin/executable_agent-config')
const share = path.join(source, 'private_dot_local/private_share/agent-config')
const sample = JSON.parse(fs.readFileSync(path.join(share, 'agent-config.sample.json'), 'utf8'))
const temporary = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'agent-config-setup-')))
const home = path.join(temporary, 'home')
const configHome = path.join(home, '.config')
const input = path.join(configHome, 'chezmoi/agent-config.json')
function run(args) {
  return spawnSync(process.execPath, [command, ...args], {
    env: { ...process.env, HOME: home, XDG_CONFIG_HOME: configHome }, encoding: 'utf8',
  })
}
function succeeds(args) {
  const result = run(args)
  if (result.status !== 0 || result.stdout !== '') throw new Error(`${args.join(' ')}: ${result.status} ${result.stderr}`)
}
function rejects(value, label) {
  fs.writeFileSync(input, JSON.stringify(value))
  if (run(['validate']).status !== 2) throw new Error(`${label} accepted`)
}
try {
  fs.mkdirSync(path.dirname(input), { recursive: true })
  const value = structuredClone(sample)
  value.projectRouting.rules = []
  fs.writeFileSync(input, JSON.stringify(value))
  succeeds(['validate'])
  if (fs.existsSync(path.join(configHome, 'claude_lab'))) throw new Error('validate created directories')
  for (const [family, provider] of Object.entries(value.providers)) {
    const root = path.join(configHome, family)
    fs.mkdirSync(root)
    for (const entry of provider.setup.symlinks) {
      const target = path.join(root, entry)
      if (entry.includes('.')) fs.writeFileSync(target, 'shared configuration\n')
      else fs.mkdirSync(target)
    }
    fs.mkdirSync(path.join(configHome, `${family}_lab`))
    for (const entry of provider.setup.preservedMutable) {
      fs.writeFileSync(path.join(configHome, `${family}_lab`, entry), 'private mutable state\n', { mode: 0o600 })
    }
  }
  succeeds(['--input', input, 'setup'])
  succeeds(['setup'])
  for (const [family, provider] of Object.entries(value.providers)) {
    for (const entry of provider.setup.symlinks) {
      const link = path.join(configHome, `${family}_lab`, entry)
      if (!fs.lstatSync(link).isSymbolicLink() || fs.readlinkSync(link) !== path.join('..', family, entry)) {
        throw new Error(`incorrect shared link: ${link}`)
      }
    }
    for (const entry of provider.setup.preservedMutable) {
      if (fs.readFileSync(path.join(configHome, `${family}_lab`, entry), 'utf8') !== 'private mutable state\n') {
        throw new Error('mutable state overwritten')
      }
    }
  }
  const badLink = path.join(configHome, 'codex_lab/rules')
  fs.unlinkSync(badLink)
  fs.symlinkSync('../elsewhere/rules', badLink)
  if (run(['setup']).status !== 2 || fs.readlinkSync(badLink) !== '../elsewhere/rules') throw new Error('wrong link replaced')
  fs.unlinkSync(badLink)
  fs.mkdirSync(badLink)
  if (run(['setup']).status !== 2 || !fs.lstatSync(badLink).isDirectory()) throw new Error('real entry replaced')
  fs.rmdirSync(badLink)
  fs.symlinkSync('../codex/rules', badLink)
  const third = structuredClone(value)
  third.environments.third = { providers: ['claude', 'codex'] }
  fs.writeFileSync(input, JSON.stringify(third))
  succeeds(['setup'])
  if ((fs.statSync(path.join(configHome, 'claude_third')).mode & 0o777) !== 0o700) throw new Error('new directory is not private')
  for (const args of [['resolve'], ['write-paseo'], ['prune-paseo-profiles'], ['--paseo-config', input, 'validate'], ['--input', 'relative', 'validate']]) {
    if (run(args).status !== 2) throw new Error(`obsolete/invalid CLI accepted: ${args.join(' ')}`)
  }
  const legacy = structuredClone(value); legacy.version = 2; rejects(legacy, 'legacy schema')
  const selection = structuredClone(value); selection.selection = {}; rejects(selection, 'Paseo selection')
  const backend = structuredClone(value); backend.providers.codex.backends = ['paseo']; rejects(backend, 'Paseo backend')
  const omp = structuredClone(value); omp.providers.omp = { displayName: 'OMP', setup: null }; rejects(omp, 'environment-scoped OMP')
  const invalid = structuredClone(value); invalid.environments.lab.providers = ['pi']; rejects(invalid, 'retired family')
} finally { fs.rmSync(temporary, { recursive: true, force: true }) }
NODE
then
  pass 'environment config validates and setup preserves safe shared links and mutable state'
else
  fail_check 'environment config validates and setup preserves safe shared links and mutable state'
fi
assert_summary
