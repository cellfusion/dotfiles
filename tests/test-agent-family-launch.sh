#!/usr/bin/env bash
# Cwd/parent/explicit environment から family CLI の隔離設定を解決することを検証する。
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
const { validateConfig } = require(path.join(share, 'config-validator.js'))
const { resolveExport } = require(path.join(share, 'resolver.js'))
const { materializePaseoProviders } = require(path.join(share, 'paseo-providers.js'))
const sample = JSON.parse(fs.readFileSync(path.join(share, 'agent-config.sample.json'), 'utf8'))
const temporary = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'agent-family-launch-')))

function git(directory, ...args) {
  const result = spawnSync('git', ['-C', directory, ...args], { encoding: 'utf8' })
  if (result.status !== 0) throw new Error(`git ${args.join(' ')} failed: ${result.stderr}`)
}

function run(cwd, configPath, mockBin, args, extraEnv = {}) {
  return spawnSync('bash', [wrapper, ...args], {
    cwd,
    env: {
      ...process.env,
      HOME: path.join(temporary, 'home'),
      XDG_CONFIG_HOME: path.join(temporary, 'home', '.config'),
      AGENT_CONFIG: configPath,
      PATH: `${mockBin}:${process.env.PATH}`,
      AGENT_ENV: '',
      ...extraEnv,
    },
    encoding: 'utf8',
  })
}

function assertSuccess(result, label) {
  if (result.status !== 0) throw new Error(`${label} failed (${result.status}): ${result.stderr}`)
  return JSON.parse(result.stdout)
}

try {
  const main = path.join(temporary, 'main')
  const linked = path.join(temporary, 'linked')
  const unrelated = path.join(temporary, 'unrelated')
  for (const directory of [main, unrelated]) {
    fs.mkdirSync(directory, { recursive: true })
    git(directory, 'init', '-q')
    git(directory, 'config', 'user.name', 'Launch Test')
    git(directory, 'config', 'user.email', 'launch@example.test')
    fs.writeFileSync(path.join(directory, 'README.md'), 'fixture\n')
    git(directory, 'add', 'README.md')
    git(directory, 'commit', '-qm', 'fixture')
  }
  git(main, 'worktree', 'add', '-qb', 'linked-launch-test', linked)
  fs.mkdirSync(path.join(linked, 'nested'))

  const home = path.join(temporary, 'home')
  const mockBin = path.join(temporary, 'bin')
  fs.mkdirSync(path.join(home, '.config'), { recursive: true })
  fs.mkdirSync(mockBin)
  const mock = `#!/usr/bin/env node
process.stdout.write(JSON.stringify({
  binary: require('node:path').basename(process.argv[1]),
  args: process.argv.slice(2),
  environment: process.env.AGENT_ENV || null,
  claude: process.env.CLAUDE_CONFIG_DIR || null,
  codex: process.env.CODEX_HOME || null,
  pi: process.env.PI_CODING_AGENT_DIR || null,
  omp: process.env.OMP_PROFILE || null,
}))
`
  for (const family of ['claude', 'codex', 'pi', 'omp']) {
    fs.writeFileSync(path.join(mockBin, family), mock, { mode: 0o755 })
  }

  const missingConfig = path.join(temporary, 'missing.json')
  for (const selector of ['--family', '--provider']) {
    const direct = assertSuccess(
      run(unrelated, missingConfig, mockBin, [selector, 'codex', '--', 'prompt with spaces'], {
        AGENT_ENV: 'inherited',
        CODEX_HOME: path.join(home, 'existing-codex'),
      }),
      `configless ${selector}`,
    )
    if (direct.binary !== 'codex' || direct.environment !== 'inherited' ||
        direct.codex !== path.join(home, 'existing-codex') ||
        JSON.stringify(direct.args) !== JSON.stringify(['prompt with spaces'])) {
      throw new Error(`configless launch changed arguments or environment: ${JSON.stringify(direct)}`)
    }
  }
  const configlessExplicit = run(unrelated, missingConfig, mockBin, ['--family', 'codex', '--environment', 'lab'])
  if (configlessExplicit.status !== 2 || configlessExplicit.stdout !== '') {
    throw new Error('configless explicit environment must not silently launch')
  }
  const malformedConfig = path.join(temporary, 'malformed.json')
  fs.writeFileSync(malformedConfig, '{')
  const malformed = run(unrelated, malformedConfig, mockBin, ['--family', 'codex'])
  if (malformed.status !== 2 || malformed.stdout !== '') {
    throw new Error('malformed config must not fall back to a direct launch')
  }

  const value = structuredClone(sample)
  value.providers.omp = {
    displayName: 'OMP',
    backends: ['paseo'],
    setup: null,
    environmentVariable: 'OMP_PROFILE',
    featureAllowlist: {},
  }
  value.environments.primary.providers = ['claude', 'codex', 'pi', 'omp']
  value.environments.lab.providers = ['claude', 'codex', 'pi', 'omp']
  value.projectRouting.rules = [{
    name: 'linked-environment',
    environment: 'lab',
    match: { gitRepository: main },
  }]
  const config = validateConfig(JSON.stringify(value)).config
  const configPath = path.join(temporary, 'agent-config.json')
  fs.writeFileSync(configPath, JSON.stringify(value))

  const routed = assertSuccess(
    run(path.join(linked, 'nested'), configPath, mockBin, ['--family=omp', '--', 'prompt', '--flag']),
    'cwd-routed OMP',
  )
  if (routed.binary !== 'omp' || routed.environment !== 'lab' || routed.omp !== 'lab' ||
      JSON.stringify(routed.args) !== JSON.stringify(['prompt', '--flag'])) {
    throw new Error(`cwd-routed OMP assignments are wrong: ${JSON.stringify(routed)}`)
  }

  const parent = assertSuccess(
    run(linked, configPath, mockBin, ['--family', 'pi'], { AGENT_ENV: 'primary' }),
    'parent-routed Pi',
  )
  if (parent.environment !== 'primary' || parent.pi !== path.join(home, '.pi/agent')) {
    throw new Error(`parent environment did not override cwd: ${JSON.stringify(parent)}`)
  }

  const explicit = assertSuccess(
    run(linked, configPath, mockBin, ['--family=codex', '--environment=lab'], { AGENT_ENV: 'primary' }),
    'explicit Codex',
  )
  if (explicit.environment !== 'lab' || explicit.codex !== path.join(home, '.config', 'codex_lab')) {
    throw new Error(`explicit environment did not override parent: ${JSON.stringify(explicit)}`)
  }

  const fallback = assertSuccess(
    run(unrelated, configPath, mockBin, ['--family', 'claude']),
    'default Claude',
  )
  if (fallback.environment !== 'primary' || fallback.claude !== path.join(home, '.config', 'claude')) {
    throw new Error(`default environment assignments are wrong: ${JSON.stringify(fallback)}`)
  }

  const provider = assertSuccess(
    run(unrelated, configPath, mockBin, ['--provider=pi-lab']),
    'explicit provider compatibility',
  )
  if (provider.environment !== 'lab' || provider.pi !== path.join(home, '.pi/agent-lab')) {
    throw new Error(`explicit provider changed behavior: ${JSON.stringify(provider)}`)
  }

  const materialized = materializePaseoProviders(resolveExport(config))
  if (materialized.providers['omp-lab'].env.OMP_PROFILE !== 'lab' ||
      materialized.providers.omp.env.OMP_PROFILE !== 'primary') {
    throw new Error(`Paseo OMP profile assignments are wrong: ${JSON.stringify(materialized.providers)}`)
  }

  const ineligibleValue = structuredClone(value)
  ineligibleValue.environments.lab.providers = ['claude', 'codex', 'omp']
  const ineligiblePath = path.join(temporary, 'ineligible.json')
  fs.writeFileSync(ineligiblePath, JSON.stringify(ineligibleValue))
  const ineligible = run(linked, ineligiblePath, mockBin, ['--family=pi'])
  if (ineligible.status !== 2 || !ineligible.stderr.includes('configured')) {
    throw new Error(`ineligible family did not fail closed: ${ineligible.status} ${ineligible.stderr}`)
  }

  for (const args of [
    ['--family=omp', '--provider=omp'],
    ['--environment=lab'],
    ['--provider=omp', '--environment=lab'],
    ['--family=omp', '--family=pi'],
    ['--family=omp', '--environment=missing'],
  ]) {
    const invalid = run(main, configPath, mockBin, args)
    if (invalid.status !== 2) throw new Error(`invalid options were accepted: ${args.join(' ')}`)
  }

  const brokenConfigPath = path.join(temporary, 'broken.json')
  fs.writeFileSync(brokenConfigPath, '{')
  const brokenUsage = run(main, brokenConfigPath, mockBin, [])
  if (brokenUsage.status !== 2 ||
      !brokenUsage.stderr.includes('provider 一覧を取得できない') ||
      !brokenUsage.stderr.includes('JSON')) {
    throw new Error(`usage error hid the invalid config: ${brokenUsage.status} ${brokenUsage.stderr}`)
  }
} finally {
  spawnSync('git', ['-C', path.join(temporary, 'main'), 'worktree', 'remove', '--force', path.join(temporary, 'linked')])
  fs.rmSync(temporary, { recursive: true, force: true })
}
NODE
then
  pass 'family launch resolves cwd, parent, explicit environment, provider compatibility, and OMP profiles'
else
  fail_check 'family launch resolves cwd, parent, explicit environment, provider compatibility, and OMP profiles'
fi

assert_summary
