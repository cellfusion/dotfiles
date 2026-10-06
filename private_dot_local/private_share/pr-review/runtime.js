'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

const REPOSITORY = /^[A-Za-z0-9][A-Za-z0-9_.-]*\/[A-Za-z0-9][A-Za-z0-9_.-]*$/;
const SHA = /^[0-9a-f]{40}$/;
const URL = /^https:\/\/github\.com\/([A-Za-z0-9][A-Za-z0-9_.-]*\/[A-Za-z0-9][A-Za-z0-9_.-]*)\/pull\/([1-9][0-9]*)\/?$/;

function parseArgs(args) {
  const result = { number: null, repository: null, quick: false, noFocus: false, skillFile: null };
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--quick' || arg === '--no-focus') {
      const key = arg === '--quick' ? 'quick' : 'noFocus';
      if (result[key]) throw new Error('duplicate option');
      result[key] = true;
    } else if (arg === '--skill-file') {
      if (result.skillFile || !args[i + 1] || args[i + 1].startsWith('--')) throw new Error('invalid skill-file option');
      result.skillFile = path.resolve(args[++i]);
    } else {
      if (result.number !== null || arg.startsWith('-')) throw new Error('invalid input or unknown option');
      const match = arg.match(URL);
      const number = match ? match[2] : arg;
      if (!/^[1-9][0-9]*$/.test(number) || !Number.isSafeInteger(Number(number))) throw new Error('expected positive PR number or GitHub PR URL');
      result.number = Number(number);
      if (match) result.repository = match[1];
    }
  }
  if (result.number === null) throw new Error('missing PR input');
  return result;
}

function command(binary, args, cwd) {
  const result = spawnSync(binary, args, { cwd, encoding: 'utf8', timeout: 300000, maxBuffer: 16 * 1024 * 1024 });
  if (result.error || result.status !== 0) throw new Error(`${binary} command failed`);
  return result.stdout.trim();
}
function git(cwd, ...args) { return command('git', ['-C', cwd, ...args]); }
function jsonCommand(binary, args, cwd) { return JSON.parse(command(binary, args, cwd)); }
function privateWrite(file, value) {
  fs.writeFileSync(file, typeof value === 'string' ? value : JSON.stringify(value, null, 2) + '\n', { mode: 0o600, flag: 'wx' });
}
function sameRepository(a, b) { return a.toLowerCase() === b.toLowerCase(); }

function validateMetadata(data, repository, number) {
  if (!data || !REPOSITORY.test(repository) || data.number !== number || !SHA.test(data.baseRefOid) || !SHA.test(data.headRefOid) || typeof data.isCrossRepository !== 'boolean') throw new Error('invalid PR metadata');
  const match = typeof data.url === 'string' && data.url.match(URL);
  if (!match || !sameRepository(match[1], repository) || Number(match[2]) !== number) throw new Error('PR URL repository mismatch');
  let headRepository = repository;
  if (data.isCrossRepository) {
    headRepository = data.headRepository?.nameWithOwner || (data.headRepositoryOwner?.login && data.headRepository?.name ? `${data.headRepositoryOwner.login}/${data.headRepository.name}` : null);
    if (!headRepository || !REPOSITORY.test(headRepository)) throw new Error('fork repository unavailable');
  }
  return { baseSha: data.baseRefOid, headSha: data.headRefOid, headRepository };
}
function assertSameRevision(fixed, latest) {
  if (latest.baseSha !== fixed.baseSha || latest.headSha !== fixed.headSha || !sameRepository(latest.headRepository, fixed.headRepository)) throw new Error('PR revision changed during preparation');
}

function checkPrivate(file, directory) {
  const stat = fs.lstatSync(file);
  if (stat.isSymbolicLink() || (directory ? !stat.isDirectory() : !stat.isFile()) || (stat.mode & 0o777) !== (directory ? 0o700 : 0o600) || (process.getuid && stat.uid !== process.getuid())) throw new Error('context and artifacts must be private and caller-owned');
}
function validateContext(file, cwd = process.cwd(), env = process.env) {
  if (!path.isAbsolute(file)) throw new Error('context path must be absolute');
  checkPrivate(file, false);
  const context = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (context.version !== 1 || context.owner !== 'herdr') throw new Error('invalid context version or owner');
  if (!/^[a-zA-Z0-9_-]+$/.test(context.runId) || !REPOSITORY.test(context.repository) || !REPOSITORY.test(context.headRepository) || !Number.isSafeInteger(context.prNumber) || context.prNumber < 1 || !SHA.test(context.baseSha) || !SHA.test(context.headSha) || typeof context.quick !== 'boolean') throw new Error('invalid context identity');
  if (!path.isAbsolute(context.worktreePath) || !path.isAbsolute(context.artifactPath) || path.dirname(fs.realpathSync(file)) !== fs.realpathSync(context.artifactPath)) throw new Error('invalid context artifact paths');
  checkPrivate(context.artifactPath, true);
  if (env.HERDR_ENV !== '1' || !context.workspaceId || !context.rootPaneId || env.HERDR_WORKSPACE_ID !== context.workspaceId || env.HERDR_PANE_ID !== context.rootPaneId) throw new Error('prepared workspace/root pane mismatch');
  if (fs.realpathSync(cwd) !== fs.realpathSync(context.worktreePath)) throw new Error('prepared cwd mismatch');
  const root = fs.realpathSync(git(cwd, 'rev-parse', '--show-toplevel'));
  if (root !== fs.realpathSync(context.worktreePath)) throw new Error('prepared cwd mismatch');
  if (git(root, 'rev-parse', 'HEAD') !== context.baseSha || git(root, 'status', '--porcelain')) throw new Error('prepared base checkout is changed');
  if (git(root, 'rev-parse', `${context.headSha}^{commit}`) !== context.headSha) throw new Error('prepared head object mismatch');
  if (!context.repositoryGitDir || !path.isAbsolute(context.repositoryGitDir) || fs.realpathSync(git(root, 'rev-parse', '--path-format=absolute', '--git-common-dir')) !== fs.realpathSync(context.repositoryGitDir)) throw new Error('prepared repository mismatch');
  if (fs.realpathSync(git(root, 'rev-parse', '--absolute-git-dir')) === fs.realpathSync(context.repositoryGitDir)) throw new Error('prepared owner requires a linked worktree');
  return context;
}

function recordFailure(run, stage, error, resources) {
  const reason = stage === 'omp-integration'
    ? 'Install the official lifecycle integration with herdr integration install omp before starting a review.'
    : stage === 'agent-readiness'
      ? 'OMP lifecycle integration did not report the isolated root session; resources retained before prompt submission.'
      : 'Stage failed; resources retained. Inspect the existing workspace before resuming.';
  const result = { version: 1, status: 'blocked', stage, at: new Date().toISOString(), ...resources, artifactPath: run, reason };
  // Never copy external command output, environment, or exception text into metadata.
  if (run) fs.writeFileSync(path.join(run, 'startup.json'), JSON.stringify(result, null, 2) + '\n', { mode: 0o600 });
  return result;
}

async function launch(args) {
  const options = parseArgs(args);
  let stage = 'dependencies'; let run = null; const resources = { owner: 'herdr', workspaceId: null, rootPaneId: null, worktreePath: null };
  try {
    if (process.env.HERDR_ENV !== '1') throw new Error('Herdr environment required');
    for (const binary of ['git', 'gh', 'herdr', 'omp']) command('/usr/bin/env', ['which', binary]);
    stage = 'omp-integration';
    const configuredAgentDir = process.env.PI_CODING_AGENT_DIR;
    const agentDir = configuredAgentDir
      ? path.resolve(configuredAgentDir.replace(/^~(?=\/|$)/, os.homedir()))
      : path.join(os.homedir(), '.omp', 'agent');
    const lifecycleExtension = path.join(agentDir, 'extensions', 'herdr-omp-agent-state.ts');
    if (!fs.statSync(lifecycleExtension).isFile()) throw new Error('official OMP integration required');
    stage = 'skill-source';
    const skill = options.skillFile || path.join(os.homedir(), '.agents/skills/pr-review/SKILL.md');
    const skillText = fs.readFileSync(skill, 'utf8');
    if (!fs.statSync(skill).isFile() || !/^name: pr-review$/m.test(skillText) || !skillText.includes('**Prepared-review contract:**') || /\{\{/.test(skillText)) throw new Error('rendered prepared pr-review skill required');
    stage = 'repository';
    const callerRoot = fs.realpathSync(git(process.cwd(), 'rev-parse', '--show-toplevel'));
    resources.callerRoot = callerRoot;
    const repository = command('gh', ['repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner'], callerRoot);
    if (!REPOSITORY.test(repository) || (options.repository && !sameRepository(options.repository, repository))) throw new Error('local repository and PR URL mismatch');
    const fields = 'number,url,baseRefOid,headRefOid,headRepository,headRepositoryOwner,isCrossRepository';
    const metadata = () => jsonCommand('gh', ['pr', 'view', String(options.number), '--repo', repository, '--json', fields], callerRoot);
    stage = 'metadata';
    const fixed = validateMetadata(metadata(), repository, options.number);
    stage = 'objects';
    for (const [sha, repo] of [[fixed.baseSha, repository], [fixed.headSha, fixed.headRepository]]) {
      const available = spawnSync('git', ['-C', callerRoot, 'cat-file', '-e', `${sha}^{commit}`], { stdio: 'ignore' });
      if (available.status !== 0) git(callerRoot, 'fetch', '--no-tags', '--no-write-fetch-head', `https://github.com/${repo}.git`, sha);
      if (git(callerRoot, 'rev-parse', `${sha}^{commit}`) !== sha) throw new Error('fetched SHA mismatch');
    }
    git(callerRoot, 'merge-base', fixed.baseSha, fixed.headSha);
    stage = 'revision-race';
    const latest = validateMetadata(metadata(), repository, options.number);
    assertSameRevision(fixed, latest);
    stage = 'artifacts';
    process.umask(0o077);
    const runId = `pr-${options.number}-${crypto.randomUUID()}`;
    const parent = path.join(os.homedir(), '.local/state/pr-review', repository.replace('/', '-'), `pr-${options.number}`, fixed.headSha);
    fs.mkdirSync(parent, { recursive: true, mode: 0o700 });
    const runPath = path.join(parent, runId); fs.mkdirSync(runPath, { mode: 0o700 }); run = runPath;
    fs.mkdirSync(path.join(run, 'sessions'), { mode: 0o700 });
    privateWrite(path.join(run, 'omp-config.yml'), 'autoResume: false\n');
    stage = 'worktree-create';
    resources.branch = `review/pr-${options.number}-${runId.slice(-12)}`;
    privateWrite(path.join(run, 'attempt.json'), { runId, repository, prNumber: options.number, ...fixed, ...resources });
    const creationCommand = spawnSync('herdr', ['worktree', 'create', '--cwd', callerRoot, '--branch', resources.branch, '--base', fixed.baseSha, '--label', `pr-review-${options.number}`, options.noFocus ? '--no-focus' : '--focus'], { encoding: 'utf8', timeout: 300000, maxBuffer: 1024 * 1024 });
    let creation;
    try { creation = JSON.parse(creationCommand.stdout); } catch { creation = null; }
    resources.workspaceId = creation?.result?.workspace?.workspace_id || null;
    resources.rootPaneId = creation?.result?.root_pane?.pane_id || null;
    resources.worktreePath = creation?.result?.worktree?.path || null;
    privateWrite(path.join(run, 'resources.json'), resources);
    if (creationCommand.error || creationCommand.status !== 0) throw new Error('Herdr worktree creation failed; inspect recorded branch before resuming');
    if (!resources.workspaceId || !resources.rootPaneId || !resources.worktreePath || !path.isAbsolute(resources.worktreePath)) throw new Error('incomplete Herdr creation response');
    stage = 'checkout-verify';
    if (git(resources.worktreePath, 'rev-parse', 'HEAD') !== fixed.baseSha || git(resources.worktreePath, 'status', '--porcelain')) throw new Error('Herdr base checkout mismatch');
    const context = { version: 1, runId, repository, prNumber: options.number, ...fixed, ...resources, artifactPath: run, quick: options.quick, callerRoot, repositoryGitDir: fs.realpathSync(git(callerRoot, 'rev-parse', '--path-format=absolute', '--git-common-dir')) };
    const contextFile = path.join(run, 'prepared-context.json'); privateWrite(contextFile, context);
    privateWrite(path.join(run, 'runtime.js'), fs.readFileSync(__filename, 'utf8'));
    // Copy the selected trusted skill so a source-render smoke never needs chezmoi apply.
    const skillFile = path.join(run, 'SKILL.md'); privateWrite(skillFile, skillText);
    stage = 'agent-start';
    const agentName = `pr-${options.number}-${runId.slice(-8)}`.slice(0, 32);
    command('herdr', ['agent', 'start', agentName, '--kind', 'omp', '--pane', resources.rootPaneId, '--timeout', '60000', '--', '--extension', lifecycleExtension, '--cwd', resources.worktreePath, '--session-dir', path.join(run, 'sessions'), '--config', path.join(run, 'omp-config.yml')]);
    stage = 'agent-readiness';
    const ready = jsonCommand('herdr', ['agent', 'get', agentName]).result?.agent;
    const session = ready?.agent_session;
    const isolatedSessionRoot = fs.realpathSync(path.join(run, 'sessions')) + path.sep;
    if (ready?.agent !== 'omp' || ready.pane_id !== resources.rootPaneId || !['idle', 'done'].includes(ready.agent_status) || fs.realpathSync(ready.foreground_cwd || ready.cwd) !== fs.realpathSync(resources.worktreePath)
      || session?.source !== 'herdr:omp' || session.kind !== 'path' || !path.isAbsolute(session.value)
      // OMP reserves a session path before its first message creates the file.
      || !path.join(fs.realpathSync(path.dirname(session.value)), path.basename(session.value)).startsWith(isolatedSessionRoot)) throw new Error('OMP root pane readiness or lifecycle session mismatch');
    stage = 'agent-prompt';
    const prompt = `Read the trusted pr-review skill at ${JSON.stringify(skillFile)} and execute its prepared-review contract now, using context ${JSON.stringify(contextFile)}. Validate with node ${JSON.stringify(path.join(run, 'runtime.js'))} validate-context ${JSON.stringify(contextFile)} first. Review only fixed PR ${repository}#${options.number}. Remain in this root pane/base checkout; do not create another visible workspace, worktree, pane, or agent environment. Preserve substantive review and security checks. Never post without explicit user confirmation.`;
    command('herdr', ['agent', 'prompt', agentName, prompt, '--wait', '--until', 'working', '--until', 'blocked', '--until', 'unknown', '--timeout', '15000']);
    const state = jsonCommand('herdr', ['agent', 'get', agentName]).result?.agent;
    if (state?.agent !== 'omp' || state.pane_id !== resources.rootPaneId || !['working', 'idle', 'done'].includes(state.agent_status)) throw new Error('OMP startup blocked or unknown');
    const result = { status: 'submitted', stage: 'agent-prompt', runId, repository, prNumber: options.number, ...resources, artifactPath: run, contextFile, agentName };
    privateWrite(path.join(run, 'startup.json'), result);
    process.stdout.write(JSON.stringify(result, null, 2) + '\n');
  } catch (error) {
    const failure = recordFailure(run, stage, error, resources);
    process.stderr.write(JSON.stringify(failure, null, 2) + '\n');
    process.exitCode = 1;
  }
}

module.exports = { parseArgs, validateMetadata, assertSameRevision, validateContext, recordFailure };
if (require.main === module) {
  if (process.argv[2] === 'validate-context') {
    try {
      if (process.argv.length !== 4) throw new Error('one context path required');
      process.stdout.write(JSON.stringify(validateContext(process.argv[3]), null, 2) + '\n');
    } catch (error) { process.stderr.write(`pr-review: ${error.message}\n`); process.exitCode = 1; }
  } else if (process.argv.includes('--help')) {
    process.stdout.write('Usage: pr-review [--quick] [--no-focus] [--skill-file /absolute/rendered/SKILL.md] <positive-number|GitHub-PR-URL>\nRequires a local matching repository and Herdr. Failures retain all created resources.\n');
  } else {
    launch(process.argv.slice(2)).catch(error => { process.stderr.write(`pr-review: ${error.message}\n`); process.exitCode = 2; });
  }
}
