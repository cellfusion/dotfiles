#!/usr/bin/env bash
# Verify retained CLI isolation and native OMP launch behavior.
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
  for (const family of ['claude', 'codex', 'omp']) fs.writeFileSync(path.join(mockBin, family), mock, { mode: 0o755 })
  const value = structuredClone(sample)
  value.projectRouting.rules = [{ name: 'cwd', environment: 'lab', match: { path: temporary } }]
  const configPath = path.join(temporary, 'agent-config.json')
  fs.writeFileSync(configPath, JSON.stringify(value))
  const routed = successful(run(configPath, mockBin, ['--family=codex', '--', 'prompt with spaces', '--flag']), 'cwd Codex')
  if (routed.binary !== 'codex' || routed.environment !== 'lab' || routed.codex !== path.join(home, '.config/codex_lab') ||
      JSON.stringify(routed.args) !== JSON.stringify(['prompt with spaces', '--flag'])) throw new Error('cwd/argument isolation failed')
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
    [configPath, ['--family=omp']], [configPath, ['--family=pi']], [configPath, ['--family=opencode']],
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

  // Exercise the rendered shell function, not a resolver-based OMP launch.
  const rendered = spawnSync('chezmoi', ['execute-template', '--source', source], {
    input: fs.readFileSync(path.join(source, 'private_dot_config/zsh/agent-environments.zsh.tmpl'), 'utf8'), encoding: 'utf8',
  })
  if (rendered.status !== 0) throw new Error(`shell template: ${rendered.stderr}`)
  for (const args of [[], ['--profile', 'explicit', 'prompt with spaces']]) {
    const result = spawnSync('zsh', ['-f', '-c', `${rendered.stdout}\nomp "$@"`, 'test', ...args], {
      cwd: temporary, encoding: 'utf8', env: { ...process.env, PATH: `${mockBin}:${process.env.PATH}`,
        AGENT_CONFIG: malformed, AGENT_ENV: 'lab', OMP_PROFILE: 'lab', PI_CODING_AGENT_DIR: '/old/pi' },
    })
    const omp = successful(result, 'native OMP')
    if (omp.binary !== 'omp' || omp.profile !== null || omp.storage !== null || JSON.stringify(omp.args) !== JSON.stringify(args)) {
      throw new Error(`OMP selected an environment/profile: ${JSON.stringify(omp)}`)
    }
  }
} finally { fs.rmSync(temporary, { recursive: true, force: true }) }
NODE
then
  pass 'Claude/Codex retain environment routing; OMP uses native defaults'
else
  fail_check 'Claude/Codex retain environment routing; OMP uses native defaults'
fi
assert_summary
