#!/usr/bin/env bash
# Verify environment routing and configless launch behavior for every family.
set -u
source "$(dirname "$0")/lib/assert.sh"

if node - "$CHEZMOI_SOURCE" <<'NODE'
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')
const source = process.argv[2]
const share = path.join(source, 'private_dot_local/private_share/agent-config')
const wrapper = path.join(source, 'private_dot_local/bin/executable_agent')
const sample = JSON.parse(fs.readFileSync(path.join(share, 'agent-config.sample.json'), 'utf8'))
const temporary = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'agent-family-launch-')))
function run(configPath, mockBin, args, extraEnv = {}) {
  return spawnSync('bash', [wrapper, ...args], {
    cwd: temporary,
    env: { ...process.env, HOME: path.join(temporary, 'home'),
      XDG_CONFIG_HOME: path.join(temporary, 'home', '.config'),
      AGENT_CONFIG: configPath, PATH: `${mockBin}:${process.env.PATH}`, AGENT_ENV: '', ...extraEnv },
    encoding: 'utf8',
  })
}
function successful(result, label) {
  if (result.status !== 0) throw new Error(`${label}: ${result.status} ${result.stderr}`)
  return JSON.parse(result.stdout)
}
try {
  const home = path.join(temporary, 'home')
  const mockBin = path.join(temporary, 'bin')
  fs.mkdirSync(path.join(home, '.config'), { recursive: true })
  fs.mkdirSync(mockBin)
  const mock = `#!/usr/bin/env node
process.stdout.write(JSON.stringify({binary: require('node:path').basename(process.argv[1]),
args: process.argv.slice(2), environment: process.env.AGENT_ENV || null,
claude: process.env.CLAUDE_CONFIG_DIR || null, codex: process.env.CODEX_HOME || null,
profile: process.env.OMP_PROFILE || null, storage: process.env.PI_CODING_AGENT_DIR || null}))
`
  for (const family of ['claude', 'codex', 'omp', 'opencode', 'pi']) fs.writeFileSync(path.join(mockBin, family), mock, { mode: 0o755 })
  const value = structuredClone(sample)
  value.providers.pi = { displayName: 'Pi', setup: null }
  value.environments.lab.providers = [...new Set([...value.environments.lab.providers, 'pi'])]
  const baseOmpConfig = path.join(home, 'default settings.yml')
  const labOmpConfig = path.join(home, 'lab settings.yml')
  value.environments.lab.ompConfigOverlays = [baseOmpConfig, labOmpConfig]
  value.projectRouting.rules = [{ name: 'cwd', environment: 'lab', match: { path: temporary } }]
  const configPath = path.join(temporary, 'agent-config.json')
  fs.writeFileSync(configPath, JSON.stringify(value))
  const routed = successful(run(configPath, mockBin, ['--family=codex', '--', 'prompt with spaces', '--flag']), 'cwd Codex')
  if (routed.binary !== 'codex' || routed.environment !== 'lab' || routed.codex !== path.join(home, '.config/codex_lab') ||
      JSON.stringify(routed.args) !== JSON.stringify(['prompt with spaces', '--flag'])) throw new Error('cwd/argument isolation failed')
  const openCode = successful(run(configPath, mockBin, ['--family=opencode', '--', 'prompt with spaces']), 'cwd OpenCode')
  if (openCode.binary !== 'opencode' || openCode.environment !== 'lab' ||
      JSON.stringify(openCode.args) !== JSON.stringify(['prompt with spaces'])) throw new Error('OpenCode routing failed')
  fs.mkdirSync(path.join(home, '.pi/agent/extensions'), { recursive: true })
  fs.writeFileSync(path.join(home, '.pi/agent/settings.json'), '{}')
  fs.writeFileSync(path.join(home, '.pi/agent/auth.json'), 'private')
  const pi = successful(run(configPath, mockBin, ['--family=pi', '--', 'prompt with spaces'],
    { PI_CODING_AGENT_DIR: '/custom/pi' }), 'cwd Pi')
  if (pi.binary !== 'pi' || pi.environment !== 'lab' || pi.storage !== path.join(home, '.pi/agent_lab') ||
      JSON.stringify(pi.args) !== JSON.stringify(['prompt with spaces'])) throw new Error('Pi routing failed')
  for (const name of ['settings.json', 'extensions']) {
    if (fs.realpathSync(path.join(pi.storage, name)) !== fs.realpathSync(path.join(home, '.pi/agent', name))) throw new Error(`Pi did not share ${name}`)
  }
  if (fs.existsSync(path.join(pi.storage, 'auth.json'))) throw new Error('Pi shared credentials')
  fs.symlinkSync(path.join(home, '.pi/agent/auth.json'), path.join(pi.storage, 'auth.json'))
  if (run(configPath, mockBin, ['--family=pi']).status !== 2) throw new Error('Pi accepted shared auth symlink')
  fs.unlinkSync(path.join(pi.storage, 'auth.json'))
  fs.linkSync(path.join(home, '.pi/agent/auth.json'), path.join(pi.storage, 'auth.json'))
  if (run(configPath, mockBin, ['--family=pi']).status !== 2) throw new Error('Pi accepted shared auth hard link')
  fs.unlinkSync(path.join(pi.storage, 'auth.json'))
  const defaultPi = successful(run(configPath, mockBin, ['--family=pi', '--environment=primary'],
    { PI_CODING_AGENT_DIR: '/custom/pi' }), 'default Pi')
  if (defaultPi.storage !== path.join(home, '.pi/agent')) throw new Error('Pi default did not use existing credentials')
  const configlessPi = successful(run(path.join(temporary, 'missing.json'), mockBin, ['--family=pi'],
    { PI_CODING_AGENT_DIR: '/custom/pi' }), 'configless Pi')
  if (configlessPi.storage !== '/custom/pi') throw new Error('configless Pi changed inherited storage')
  const parent = successful(run(configPath, mockBin, ['--family', 'claude'], { AGENT_ENV: 'primary' }), 'parent Claude')
  if (parent.environment !== 'primary' || parent.claude !== path.join(home, '.config/claude')) throw new Error('parent did not override cwd')
  const explicit = successful(run(configPath, mockBin, ['--family=codex', '--environment=lab'], { AGENT_ENV: 'primary' }), 'explicit Codex')
  if (explicit.environment !== 'lab' || explicit.codex !== path.join(home, '.config/codex_lab')) throw new Error('explicit did not override parent')
  const fallbackValue = structuredClone(value)
  fallbackValue.projectRouting.rules = []
  const fallbackPath = path.join(temporary, 'fallback.json')
  fs.writeFileSync(fallbackPath, JSON.stringify(fallbackValue))
  const fallback = successful(run(fallbackPath, mockBin, ['--family=claude']), 'default Claude')
  if (fallback.environment !== 'primary' || fallback.claude !== path.join(home, '.config/claude')) throw new Error('default changed')
  const missing = path.join(temporary, 'missing.json')
  const direct = successful(run(missing, mockBin, ['--family=codex', '--', 'prompt'], { AGENT_ENV: 'inherited', CODEX_HOME: '/existing/codex' }), 'configless')
  if (direct.environment !== 'inherited' || direct.codex !== '/existing/codex') throw new Error('configless launch changed inherited environment')
  const malformed = path.join(temporary, 'malformed.json')
  fs.writeFileSync(malformed, '{')
  for (const [config, args] of [
    [missing, ['--family=codex', '--environment=lab']],
    [malformed, ['--family=codex']],
    [missing, ['--family=omp', '--environment=lab']],
    [malformed, ['--family=omp']],
    [configPath, ['--family=omp', '--environment=missing']],
    [configPath, ['--family=omp', '--environment=']],
    [configPath, ['--provider=codex']], [configPath, ['--environment=lab']],
    [configPath, ['--family=codex', '--family=claude']], [configPath, ['--family=codex', '--environment=missing']],
  ]) {
    const result = run(config, mockBin, args)
    if (result.status !== 2 || result.stdout !== '') throw new Error(`unsupported launch accepted: ${args.join(' ')}`)
  }
  const ineligibleValue = structuredClone(value)
  ineligibleValue.environments.lab.providers = ['claude']
  const ineligiblePath = path.join(temporary, 'ineligible.json')
  fs.writeFileSync(ineligiblePath, JSON.stringify(ineligibleValue))
  if (run(ineligiblePath, mockBin, ['--family=codex']).status !== 2) throw new Error('ineligible CLI launched')
  if (run(ineligiblePath, mockBin, ['--family=opencode']).status !== 2) throw new Error('ineligible OpenCode launched')
  if (run(ineligiblePath, mockBin, ['--family=pi']).status !== 2) throw new Error('ineligible Pi launched')

  const inherited = { OMP_PROFILE: 'old-profile', PI_CODING_AGENT_DIR: '/old/pi' }
  const cwdOmp = successful(run(configPath, mockBin, ['--family=omp'], inherited), 'cwd OMP')
  if (cwdOmp.environment !== 'lab' || cwdOmp.profile !== 'lab' || cwdOmp.storage !== null) {
    throw new Error('OMP did not select cwd profile or retained old storage')
  }
  if (JSON.stringify(cwdOmp.args) !== JSON.stringify(['--config', baseOmpConfig, '--config', labOmpConfig])) {
    throw new Error('OMP did not load default config before profile overrides')
  }
  const customOmpConfig = path.join(home, 'custom settings.yml')
  const customOmp = successful(run(configPath, mockBin, ['--family=omp', '--', '--config', customOmpConfig]), 'OMP custom overlay')
  if (JSON.stringify(customOmp.args) !== JSON.stringify([...cwdOmp.args, '--config', customOmpConfig])) {
    throw new Error('explicit OMP overlays must load last')
  }
  const parentOmp = successful(run(configPath, mockBin, ['--family=omp'], { ...inherited, AGENT_ENV: 'primary' }), 'parent OMP')
  if (parentOmp.environment !== 'primary' || parentOmp.profile !== null || parentOmp.storage !== null) {
    throw new Error('OMP parent did not override cwd with native default')
  }
  if (parentOmp.args.length !== 0) throw new Error('OMP default loaded a named profile overlay')
  for (const option of [['--environment=lab'], ['--environment', 'lab']]) {
    const explicitOmp = successful(run(configPath, mockBin, ['--family=omp', ...option], {
      ...inherited, AGENT_ENV: 'primary',
    }), 'explicit OMP')
    if (explicitOmp.environment !== 'lab' || explicitOmp.profile !== 'lab' || explicitOmp.storage !== null) {
      throw new Error('OMP explicit environment did not override parent')
    }
  }
  const defaultOmp = successful(run(fallbackPath, mockBin, ['--family=omp'], inherited), 'default OMP')
  if (defaultOmp.environment !== 'primary' || defaultOmp.profile !== null || defaultOmp.storage !== null) {
    throw new Error('OMP default retained an inherited profile or storage')
  }
  const configlessOmp = successful(run(missing, mockBin, ['--family=omp'], {
    ...inherited, AGENT_ENV: 'unregistered-parent',
  }), 'configless OMP')
  if (configlessOmp.environment !== 'unregistered-parent' ||
      configlessOmp.profile !== inherited.OMP_PROFILE || configlessOmp.storage !== inherited.PI_CODING_AGENT_DIR) {
    throw new Error('configless OMP changed native environment')
  }
  if (run(ineligiblePath, mockBin, ['--family=omp']).status !== 2) throw new Error('ineligible OMP launched')
  const unregistered = structuredClone(value)
  delete unregistered.providers.omp
  for (const environment of Object.values(unregistered.environments)) {
    environment.providers = environment.providers.filter((family) => family !== 'omp')
  }
  const unregisteredPath = path.join(temporary, 'unregistered.json')
  fs.writeFileSync(unregisteredPath, JSON.stringify(unregistered))
  if (run(unregisteredPath, mockBin, ['--family=omp']).status !== 2) throw new Error('unregistered OMP launched')
  if (run(configPath, mockBin, ['--family=omp'], { AGENT_ENV: 'missing' }).status !== 2) {
    throw new Error('OMP accepted unknown parent environment')
  }
} finally { fs.rmSync(temporary, { recursive: true, force: true }) }
NODE
then
  pass 'all families route configured environments and preserve configless native launch'
else
  fail_check 'all families route configured environments and preserve configless native launch'
fi
assert_summary
