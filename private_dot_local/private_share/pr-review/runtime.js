'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { isDeepStrictEqual } = require('node:util');

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
  const result = spawnSync(binary, args, { cwd, encoding: 'utf8', timeout: 300000, maxBuffer: 16 * 1024 * 1024, env: binary === 'git' ? gitEnvironment() : process.env });
  if (result.error || result.status !== 0) throw new Error(`${binary} command failed`);
  return result.stdout.trim();
}
function git(cwd, ...args) { return command('git', ['-C', cwd, ...args]); }
function gitEnvironment() {
  return { ...process.env, GIT_NO_REPLACE_OBJECTS: '1', GIT_NO_LAZY_FETCH: '1', GIT_TERMINAL_PROMPT: '0' };
}
function mergeBase(cwd, base, head) {
  if (git(cwd, 'rev-parse', '--is-shallow-repository') !== 'false') throw new Error('shallow history cannot establish review scope');
  const bases = git(cwd, 'merge-base', '--all', base, head).split('\n');
  if (bases.length !== 1 || !SHA.test(bases[0])) throw new Error('one unambiguous merge-base required');
  return bases[0];
}
function jsonCommand(binary, args, cwd) { return JSON.parse(command(binary, args, cwd)); }
function privateWrite(file, value) {
  fs.writeFileSync(file, typeof value === 'string' || Buffer.isBuffer(value) ? value : JSON.stringify(value, null, 2) + '\n', { mode: 0o600, flag: 'wx' });
}
function sameRepository(a, b) { return a.toLowerCase() === b.toLowerCase(); }
function orcaCommand(env = process.env, platform = process.platform) {
  return env.ORCA_CLI_COMMAND || (env.ORCA_DEV_REPO_ROOT ? 'orca-dev' : platform === 'linux' && !env.ORCA_TERMINAL_HANDLE ? 'orca-ide' : 'orca');
}
function shellQuote(value) { return "'" + value.replace(/'/g, "'\\''") + "'"; }
function orcaResult(binary, args, cwd) {
  const response = jsonCommand(binary, [...args, '--json'], cwd);
  if (response.ok !== true || !response.result) throw new Error('Orca request failed');
  return response.result;
}

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
  if (context.version !== 2 || context.owner !== 'orca') throw new Error('invalid context version or owner');
  if (!/^[a-zA-Z0-9_-]+$/.test(context.runId) || !REPOSITORY.test(context.repository) || !REPOSITORY.test(context.headRepository) || !Number.isSafeInteger(context.prNumber) || context.prNumber < 1 || !SHA.test(context.baseSha) || !SHA.test(context.headSha) || typeof context.quick !== 'boolean') throw new Error('invalid context identity');
  if (!path.isAbsolute(context.worktreePath) || !path.isAbsolute(context.artifactPath) || path.dirname(fs.realpathSync(file)) !== fs.realpathSync(context.artifactPath)) throw new Error('invalid context artifact paths');
  checkPrivate(context.artifactPath, true);
  if (typeof context.worktreeId !== 'string' || !context.worktreeId.endsWith(`::${context.worktreePath}`) || context.worktreeId.indexOf('::') < 1) throw new Error('invalid prepared worktree identity');
  if (!context.terminalHandle || env.ORCA_WORKTREE_ID !== context.worktreeId || env.ORCA_TERMINAL_HANDLE !== context.terminalHandle) throw new Error('prepared worktree/terminal mismatch');
  if (fs.realpathSync(cwd) !== fs.realpathSync(context.worktreePath)) throw new Error('prepared cwd mismatch');
  const root = fs.realpathSync(git(cwd, 'rev-parse', '--show-toplevel'));
  if (root !== fs.realpathSync(context.worktreePath)) throw new Error('prepared cwd mismatch');
  if (git(root, 'rev-parse', 'HEAD') !== context.baseSha || git(root, 'status', '--porcelain')) throw new Error('prepared base checkout is changed');
  if (git(root, 'rev-parse', `${context.headSha}^{commit}`) !== context.headSha) throw new Error('prepared head object mismatch');
  if (!context.repositoryGitDir || !path.isAbsolute(context.repositoryGitDir) || fs.realpathSync(git(root, 'rev-parse', '--path-format=absolute', '--git-common-dir')) !== fs.realpathSync(context.repositoryGitDir)) throw new Error('prepared repository mismatch');
  if (fs.realpathSync(git(root, 'rev-parse', '--absolute-git-dir')) === fs.realpathSync(context.repositoryGitDir)) throw new Error('prepared owner requires a linked worktree');
  const ancestor = mergeBase(root, context.baseSha, context.headSha);
  if (context.mergeBaseSha !== undefined && context.mergeBaseSha !== ancestor) throw new Error('prepared merge-base mismatch');
  return context;
}

function inspectContext(file, cwd = process.cwd(), env = process.env) {
  const c = validateContext(file, cwd, env);
  return {
    actualCheckout: { branch: git(cwd, 'branch', '--show-current') || null, sha: c.baseSha, path: c.worktreePath },
    reviewTarget: { baseSha: c.baseSha, headSha: c.headSha, mergeBaseSha: mergeBase(cwd, c.baseSha, c.headSha) },
    sourceAccess: 'fixed-git-objects',
    executionPolicy: 'not-run; PR-side execution requires explicit permission and isolated sandbox',
  };
}
function rawGit(cwd, args) {
  const r = spawnSync('git', ['-C', cwd, ...args], { env: gitEnvironment(), timeout: 300000, maxBuffer: 128 * 1024 * 1024 });
  if (r.error || r.status !== 0) throw new Error('git object read failed (missing object or output limit); scope is incomplete');
  return r.stdout;
}
function sourcePath(value) {
  if (typeof value !== 'string' || !value || value.includes('\0') || value.startsWith('/') || value.split('/').some(p => !p || p === '.' || p === '..')) throw new Error('invalid relative source path');
  return value;
}
function patchHeadPath(header) {
  let value = header.replace(/\t$/, '');
  if (value.startsWith('"')) {
    if (!value.endsWith('"')) throw new Error('invalid quoted patch path');
    const chunks = []; const body = value.slice(1, -1);
    const escapes = { a: 7, b: 8, t: 9, n: 10, v: 11, f: 12, r: 13, '"': 34, '\\': 92 };
    const pattern = /\\([0-7]{1,3}|[abtnvfr"\\])/g;
    let offset = 0;
    for (const match of body.matchAll(pattern)) {
      const plain = body.slice(offset, match.index);
      if (plain.includes('\\')) throw new Error('unsupported patch path escape');
      chunks.push(Buffer.from(plain), Buffer.from([/^[0-7]/.test(match[1]) ? parseInt(match[1], 8) : escapes[match[1]]]));
      offset = match.index + match[0].length;
    }
    if (body.slice(offset).includes('\\')) throw new Error('unsupported patch path escape');
    chunks.push(Buffer.from(body.slice(offset)));
    value = Buffer.concat(chunks).toString('utf8');
  }
  return value.startsWith('b/') ? value.slice(2) : null;
}
function treeEntry(cwd, sha, name) {
  sourcePath(name);
  const entries = rawGit(cwd, ['--literal-pathspecs', 'ls-tree', '-z', sha, '--', name]).toString('utf8').split('\0').filter(Boolean);
  for (const entry of entries) {
    const tab = entry.indexOf('\t');
    if (entry.slice(tab + 1) === name) {
      const [mode, type, oid] = entry.slice(0, tab).split(' ');
      return { mode, type, oid };
    }
  }
  return null;
}
function treeManifest(c, cwd, revision) {
  const fixed = identity(c, cwd);
  const sha = revision === 'head' ? c.headSha : fixed.mergeBaseOid;
  const bytes = rawGit(cwd, ['ls-tree', '-rz', '--full-tree', sha]);
  if (!Buffer.from(bytes.toString('utf8')).equals(bytes)) throw new Error('non-UTF-8 source names cannot be inventoried safely');
  const entries = bytes.toString('utf8').split('\0').filter(Boolean).map(row => {
    const tab = row.indexOf('\t'); const [mode, type, oid] = row.slice(0, tab).split(' ');
    return { path: row.slice(tab + 1), mode, type, oid };
  });
  return { schemaVersion: 1, ...fixed, revision, sha, entries };
}
function preserveManifest(c, cwd, revision) {
  const dir = privateDirectory(c.artifactPath, 'context');
  const name = `context/${revision}-tree.json`;
  const manifest = treeManifest(c, cwd, revision);
  if (fs.existsSync(path.join(dir, `${revision}-tree.json`))) {
    if (!equal(artifact(c, name), manifest)) throw new Error('fixed source tree manifest mismatch');
  } else privateWrite(path.join(c.artifactPath, name), manifest);
}
function identity(c, cwd) {
  return { reviewId: c.runId, repository: c.repository, prNumber: c.prNumber, baseRefOid: c.baseSha, headRefOid: c.headSha, mergeBaseOid: mergeBase(cwd, c.baseSha, c.headSha) };
}
function inventory(c, cwd) {
  const ancestor = mergeBase(cwd, c.baseSha, c.headSha);
  const parts = rawGit(cwd, ['diff', '--no-ext-diff', '--no-textconv', '--name-status', '-z', '--find-renames', ancestor, c.headSha, '--']).toString('utf8').split('\0');
  const files = [];
  for (let i = 0; i < parts.length && parts[i];) {
    const status = parts[i++]; const from = parts[i++];
    const renamed = /^[RC]/.test(status); const name = renamed ? parts[i++] : from;
    sourcePath(name);
    const base = status === 'A' ? null : treeEntry(cwd, ancestor, renamed ? from : name);
    const head = status === 'D' ? null : treeEntry(cwd, c.headSha, name);
    files.push({ path: name, oldPath: renamed ? from : null, status, baseBlob: base?.type === 'tree' ? null : base?.oid || null, headBlob: head?.type === 'tree' ? null : head?.oid || null });
  }
  return files;
}
function privateDirectory(root, name) {
  const dir = path.join(root, name);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { mode: 0o700 });
  checkPrivate(dir, true);
  return dir;
}
function artifact(c, name) {
  const file = path.join(c.artifactPath, name);
  checkPrivate(file, false);
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}
function equal(a, b) { return isDeepStrictEqual(a, b); }
function assertIdentity(value, expected) {
  for (const [key, val] of Object.entries(expected)) if (value[key] !== val) throw new Error(`artifact identity mismatch: ${key}`);
}
function prepareCoverage(file, cwd = process.cwd(), env = process.env) {
  const c = validateContext(file, cwd, env); const expected = identity(c, cwd);
  const target = path.join(c.artifactPath, 'coverage.json');
  const files = inventory(c, cwd);
  preserveManifest(c, cwd, 'base');
  preserveManifest(c, cwd, 'head');
  if (fs.existsSync(target)) {
    const existing = artifact(c, 'coverage.json'); assertIdentity(existing, expected);
    assertInventory(existing.files, files);
    return existing;
  }
  const coverage = { schemaVersion: 1, ...expected, status: 'partial', files: files.map(f => ({ ...f, classification: 'unclassified', method: 'unreviewed', evidence: [], reason: '' })), behaviorPaths: [], limitations: [] };
  privateWrite(target, coverage);
  return coverage;
}
function blobRange(bytes, start, end) {
  const binary = bytes.includes(0) || !Buffer.from(bytes.toString('utf8'), 'utf8').equals(bytes);
  if (binary) {
    if (start !== undefined || end !== undefined) throw new Error('binary source has no line ranges');
    return { bytes, start: 1, end: 0, totalLines: 0, complete: true, binary: true };
  }
  const offsets = [0];
  for (let i = 0; i < bytes.length; i++) if (bytes[i] === 10 && i + 1 < bytes.length) offsets.push(i + 1);
  const totalLines = bytes.length ? offsets.length : 0;
  const first = start === undefined ? 1 : Number(start);
  const last = end === undefined ? totalLines : Number(end);
  if (!Number.isSafeInteger(first) || !Number.isSafeInteger(last) || first < 1 || (totalLines ? last < first || last > totalLines : first !== 1 || last !== 0)) throw new Error('invalid source line range');
  return { bytes: bytes.subarray(offsets[first - 1] || 0, last < totalLines ? offsets[last] : bytes.length), start: first, end: last, totalLines, complete: first === 1 && last === totalLines, binary: false };
}
function readSource(file, revision, name, start, end, cwd = process.cwd(), env = process.env) {
  const c = validateContext(file, cwd, env);
  if (!['base', 'head'].includes(revision)) throw new Error('revision must be base or head');
  const sha = revision === 'base' ? mergeBase(cwd, c.baseSha, c.headSha) : c.headSha;
  const entry = treeEntry(cwd, sha, name);
  if (!entry || entry.type !== 'blob') throw new Error('source must be a fixed tree blob (submodules are not source snapshots)');
  const selected = blobRange(rawGit(cwd, ['cat-file', 'blob', entry.oid]), start, end);
  const contextDir = privateDirectory(c.artifactPath, 'context');
  const evidenceDir = privateDirectory(contextDir, 'source-evidence');
  const id = `read-${crypto.randomUUID()}`; const evidencePath = path.join(evidenceDir, `${id}.blob`);
  privateWrite(evidencePath, selected.bytes);
  const { bytes, ...range } = selected;
  const record = { id, ...identity(c, cwd), revision, path: name, blob: entry.oid, ...range, evidencePath, sha256: crypto.createHash('sha256').update(bytes).digest('hex') };
  const ledger = path.join(contextDir, 'source-reads.jsonl');
  if (fs.existsSync(ledger)) checkPrivate(ledger, false);
  fs.appendFileSync(ledger, JSON.stringify(record) + '\n', { mode: 0o600 });
  return record;
}
function assertInventory(actual, expected) {
  if (!Array.isArray(actual) || actual.length !== expected.length) throw new Error('changed-file inventory mismatch');
  for (let i = 0; i < expected.length; i++) for (const [key, val] of Object.entries(expected[i])) if (actual[i][key] !== val) throw new Error('changed-file inventory mismatch');
}
function nonempty(value) { return typeof value === 'string' && value.trim().length > 0; }
function validateReview(file, cwd = process.cwd(), env = process.env) {
  const c = validateContext(file, cwd, env); const fixed = identity(c, cwd);
  const coverage = artifact(c, 'coverage.json'); assertIdentity(coverage, fixed);
  assertInventory(coverage.files, inventory(c, cwd));
  if (!['partial', 'complete'].includes(coverage.status) || !Array.isArray(coverage.behaviorPaths) || !Array.isArray(coverage.limitations)) throw new Error('invalid coverage schema');
  const contextDir = path.join(c.artifactPath, 'context'); checkPrivate(contextDir, true);
  for (const revision of ['base', 'head']) if (!equal(artifact(c, `context/${revision}-tree.json`), treeManifest(c, cwd, revision))) throw new Error('fixed source tree manifest mismatch');
  const ledger = path.join(contextDir, 'source-reads.jsonl');
  const reads = new Map();
  if (fs.existsSync(ledger)) {
    checkPrivate(ledger, false);
    checkPrivate(path.join(contextDir, 'source-evidence'), true);
    for (const row of fs.readFileSync(ledger, 'utf8').split('\n').filter(Boolean)) {
      const r = JSON.parse(row); assertIdentity(r, fixed);
      if (!/^read-[0-9a-f-]{36}$/.test(r.id) || reads.has(r.id) || !['base', 'head'].includes(r.revision)) throw new Error('invalid source read identity');
      const entry = treeEntry(cwd, r.revision === 'head' ? c.headSha : fixed.mergeBaseOid, r.path);
      if (!entry || entry.type !== 'blob' || entry.oid !== r.blob) throw new Error('source read blob mismatch');
      const selected = blobRange(rawGit(cwd, ['cat-file', 'blob', entry.oid]), r.binary ? undefined : r.start, r.binary ? undefined : r.end);
      for (const key of ['start', 'end', 'totalLines', 'complete', 'binary']) if (selected[key] !== r[key]) throw new Error('source read range mismatch');
      const evidencePath = path.join(contextDir, 'source-evidence', `${r.id}.blob`);
      if (r.evidencePath !== evidencePath) throw new Error('source evidence path mismatch');
      checkPrivate(evidencePath, false);
      if (!fs.readFileSync(evidencePath).equals(selected.bytes) || crypto.createHash('sha256').update(selected.bytes).digest('hex') !== r.sha256) throw new Error('source evidence bytes mismatch');
      reads.set(r.id, r);
    }
  }
  function references(ids) {
    if (!Array.isArray(ids) || ids.some(id => !reads.has(id))) throw new Error('unknown source evidence');
    return ids.map(id => reads.get(id));
  }
  function covers(ids, revision, name, oid, allowBinary) {
    if (oid === null) return true;
    const selected = references(ids).filter(r => r.revision === revision && r.path === name && r.blob === oid);
    if (!selected.length || (!allowBinary && selected.some(r => r.binary))) return false;
    if (selected.some(r => r.complete)) return true;
    let next = 1;
    for (const r of selected.sort((a, b) => a.start - b.start)) {
      if (r.start > next) return false;
      next = Math.max(next, r.end + 1);
    }
    return next > selected[0].totalLines;
  }
  let reviewedCount = 0; let excludedCount = 0; let unreviewedCount = 0;
  for (const f of coverage.files) {
    references(f.evidence);
    if (!['unreviewed', 'read', 'mechanical', 'excluded'].includes(f.method)) throw new Error('invalid coverage method');
    let supported = false;
    if (f.method === 'read') supported = f.headBlob
      ? covers(f.evidence, 'head', f.path, f.headBlob, false)
      : covers(f.evidence, 'base', f.oldPath || f.path, f.baseBlob, false);
    if (f.method === 'mechanical') supported = nonempty(f.reason) && covers(f.evidence, 'base', f.oldPath || f.path, f.baseBlob, true) && covers(f.evidence, 'head', f.path, f.headBlob, true);
    if (f.method === 'excluded') {
      if (!nonempty(f.reason)) throw new Error('excluded file requires reason');
      excludedCount++;
    } else if (supported) reviewedCount++;
    else unreviewedCount++;
    if (coverage.status === 'complete' && (!nonempty(f.classification) || f.classification === 'unclassified' || (f.method !== 'excluded' && !supported))) throw new Error('complete coverage has unreviewed file or source range gap');
  }
  const summary = { status: coverage.status, fileCount: coverage.files.length, reviewedCount, excludedCount, unreviewedCount };
  const metadata = artifact(c, 'metadata.json'); const findings = artifact(c, 'findings.json');
  const checks = artifact(c, 'checks.json'); const plan = artifact(c, 'review-plan.json');
  for (const a of [metadata, findings, checks, plan]) assertIdentity(a, fixed);
  if (plan.changedFileCount !== coverage.files.length || !['low', 'medium', 'high'].includes(plan.risk) || !['minimal', 'focused', 'full'].includes(plan.profile)) throw new Error('plan inventory count or risk/profile mismatch');
  if (plan.mode !== 'prepared' || plan.speed !== (c.quick ? 'quick' : 'standard') || !Array.isArray(plan.focus) || !plan.focus.length || !plan.focus.every(nonempty) || !['none', 'summary', 'full'].includes(plan.ci)) throw new Error('plan prepared mode, speed or policy mismatch');
  for (const key of ['mode', 'speed', 'risk', 'profile', 'focus', 'ci']) if (!equal(metadata.review?.[key], plan[key])) throw new Error(`metadata review policy mismatch: ${key}`);
  for (const key of ['baseRefOid', 'headRefOid', 'mergeBaseOid']) if (metadata.revision?.[key] !== fixed[key]) throw new Error(`metadata revision mismatch: ${key}`);
  const workspace = { kind: 'orca', path: c.worktreePath, worktreeId: c.worktreeId, terminalHandle: c.terminalHandle, owner: c.owner, owned: true, cleanupStatus: 'retained' };
  for (const [key, value] of Object.entries(workspace)) if (metadata.workspace?.[key] !== value) throw new Error(`metadata workspace mismatch: ${key}`);
  const prUrl = typeof metadata.pr?.url === 'string' && metadata.pr.url.match(URL);
  if (metadata.pr?.number !== c.prNumber || metadata.pr?.repository !== c.repository || !prUrl || !sameRepository(prUrl[1], c.repository) || Number(prUrl[2]) !== c.prNumber) throw new Error('metadata PR identity mismatch');
  if (!['PASS', 'NEEDS_ATTENTION', 'BLOCKED'].includes(findings.verdict) || !Array.isArray(findings.findings)) throw new Error('invalid findings verdict');
  const ids = findings.findings.map(f => f.id);
  if (ids.some(id => !/^F-[0-9]+$/.test(id)) || new Set(ids).size !== ids.length) throw new Error('invalid finding IDs');
  for (const a of [metadata, findings, checks]) {
    if (a.verdict !== findings.verdict || a.findingCount !== ids.length || !equal(a.findingIds, ids)) throw new Error('artifact finding summary mismatch');
  }
  if ((findings.verdict === 'PASS' && ids.length) || (findings.verdict === 'NEEDS_ATTENTION' && !ids.length)) throw new Error('verdict contradicts findings');
  if (coverage.status === 'partial' && findings.verdict === 'PASS') throw new Error('partial review cannot claim PASS');
  const disclosure = inspectContext(file, cwd, env);
  for (const [key, val] of Object.entries(disclosure)) if (!equal(metadata[key], val)) throw new Error('checkout disclosure mismatch');
  if (!equal(metadata.coverage, summary)) throw new Error('metadata coverage mismatch');
  if (!Array.isArray(checks.checks) || !Array.isArray(plan.specialists)) throw new Error('missing checks or specialists');
  const roles = plan.specialists.map(lens => lens.role);
  const recordedRoles = metadata.specialistReviews?.map(lens => lens.role);
  if (roles.some(role => !nonempty(role)) || new Set(roles).size !== roles.length || !Array.isArray(recordedRoles) || new Set(recordedRoles).size !== recordedRoles.length || !equal([...roles].sort(), [...recordedRoles].sort())) throw new Error('specialist roles must be unique and match metadata');
  const completedRoutes = plan.specialists.filter(lens => lens.status === 'completed').map(lens => lens.route);
  const route = completedRoutes.includes('independent') ? 'independent' : completedRoutes.includes('sequential') ? 'sequential' : 'primary';
  if (metadata.delegation?.route !== route || metadata.delegation?.agents !== (route === 'independent' ? 'omp-internal' : 'none') || !nonempty(metadata.delegation?.reason)) throw new Error('metadata delegation route mismatch');
  const checkNames = new Set();
  for (const check of checks.checks) {
    if (!nonempty(check.name) || checkNames.has(check.name) || !['static', 'ci', 'local'].includes(check.kind) || !['pass', 'fail', 'not_run'].includes(check.status) || !nonempty(check.command) || !Number.isFinite(Date.parse(check.at)) || (check.status === 'not_run' ? !nonempty(check.reason) : !nonempty(check.evidence))) throw new Error('invalid check evidence');
    if (['ci', 'local'].includes(check.kind) && check.status !== 'not_run' && check.targetSha !== c.headSha) throw new Error('execution check target revision mismatch');
    checkNames.add(check.name);
  }
  function execution(names, kind) {
    if (!Array.isArray(names) || !names.length || names.some(name => !checks.checks.some(check => check.name === name && ['pass', 'fail'].includes(check.status) && (kind ? check.kind === kind : ['ci', 'local'].includes(check.kind))))) throw new Error('execution claim lacks matching executed check');
  }
  const pathIds = new Set();
  for (const p of coverage.behaviorPaths) {
    if (!nonempty(p.id) || pathIds.has(p.id) || !['low', 'medium', 'high'].includes(p.risk) || !['unverified', 'static', 'executed'].includes(p.status) || !nonempty(p.reason)) throw new Error('invalid behavior path');
    pathIds.add(p.id); references(p.evidence);
    if (p.status !== 'unverified' && (!p.evidence.length || !nonempty(p.beforeAfter) || !nonempty(p.reachability))) throw new Error('behavior path lacks before/after or reachability evidence');
    if (p.status === 'executed') execution(p.checks);
    if (coverage.status === 'complete' && p.risk === 'high' && p.status === 'unverified') throw new Error('complete coverage has unverified important behavior path');
  }
  if (plan.risk === 'high' && !coverage.behaviorPaths.length) throw new Error('high risk review requires behavior paths');
  if (coverage.status === 'partial' && (plan.profile === 'full' || !coverage.limitations.some(nonempty))) throw new Error('partial coverage requires limitations and cannot claim full profile');
  for (const lens of plan.specialists) {
    if (!['completed', 'blocked', 'not_run'].includes(lens.status) || !nonempty(lens.reason)) throw new Error('invalid specialist status');
    if (lens.status === 'completed') {
      if (unreviewedCount > 0) throw new Error('completed specialist cannot hide unread source range gaps');
      if (!['primary', 'sequential', 'independent'].includes(lens.route) || !nonempty(lens.limitations) || !references(lens.evidence).length) throw new Error('completed specialist lacks route or evidence');
      if (coverage.status === 'partial' && coverage.behaviorPaths.some(p => p.risk === 'high' && p.status === 'unverified')) throw new Error('completed lens cannot hide unverified important paths');
    }
    const actual = metadata.specialistReviews?.find(item => item.role === lens.role);
    if (!actual || ['status', 'reason', ...(lens.status === 'completed' ? ['route', 'evidence', 'limitations'] : [])].some(key => !equal(actual[key], lens[key]))) throw new Error('metadata specialist summary mismatch');
  }
  for (const f of findings.findings) {
    if (!coverage.files.some(changed => changed.path === f.path && changed.headBlob) || !nonempty(f.beforeAfter) || !nonempty(f.reachability) || !nonempty(f.regressionBasis) || !['static', 'ci', 'local'].includes(f.validation?.kind) || !nonempty(f.validation.evidence) || !nonempty(f.validation.limitations)) throw new Error('finding lacks changed-head path or regression/validation evidence');
    if (f.validation.kind !== 'static') execution(f.validation.checks, f.validation.kind);
    const changed = coverage.files.find(item => item.path === f.path);
    const findingReads = [...reads.values()].filter(r => f.validation.evidence.includes(r.id));
    if (!findingReads.some(r => r.revision === 'head' && r.path === f.path) || (changed.baseBlob && !findingReads.some(r => r.revision === 'base' && r.path === (changed.oldPath || f.path)))) throw new Error('finding lacks fixed before/after source read evidence');
    if (!['P0', 'P1', 'P2', 'P3'].includes(f.priority) || !['high', 'medium', 'low'].includes(f.confidence) || !['title', 'evidence', 'impact', 'recommendation'].every(key => nonempty(f[key])) || typeof f.inline !== 'boolean') throw new Error('invalid actionable finding');
    if (f.inline) {
      if (!Number.isSafeInteger(f.line) || f.line < 1) throw new Error('invalid inline finding line');
      const paths = changed.oldPath ? [changed.oldPath, f.path] : [f.path];
      const patch = rawGit(cwd, ['-c', 'core.quotePath=true', '--literal-pathspecs', 'diff', '--no-color', '--no-ext-diff', '--no-textconv', '--find-renames', '--src-prefix=a/', '--dst-prefix=b/', '--unified=0', '--inter-hunk-context=0', '--output-indicator-new=+', '--output-indicator-old=-', '--output-indicator-context= ', fixed.mergeBaseOid, c.headSha, '--', ...paths]).toString('utf8');
      let headLine = null; let headPath = null; let changedLine = false;
      for (const line of patch.split('\n')) {
        if (line.startsWith('diff --git ')) { headLine = null; headPath = null; continue; }
        if (headLine === null && line.startsWith('+++ ')) { headPath = patchHeadPath(line.slice(4)); continue; }
        const hunk = line.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/);
        if (hunk) { headLine = Number(hunk[1]); continue; }
        if (headLine === null || headPath !== f.path) continue;
        if (line.startsWith('+')) { if (headLine === f.line) changedLine = true; headLine++; }
        else if (line.startsWith(' ')) headLine++;
      }
      if (!changedLine) throw new Error('inline finding is not on a changed head line; use body-only');
    }
  }
  const reportPath = path.join(c.artifactPath, 'review.md'); checkPrivate(reportPath, false);
  const report = fs.readFileSync(reportPath, 'utf8');
  const statuses = [...report.matchAll(/^(Coverage|Verdict): (.+)$/gm)];
  const headings = [...report.matchAll(/^### (F-[0-9]+) \[([^\]]+)\] (.*)$/gm)].map(m => ({ id: m[1], priority: m[2], title: m[3] }));
  if (statuses.length !== 2 || !statuses.some(m => m[1] === 'Coverage' && m[2] === coverage.status) || !statuses.some(m => m[1] === 'Verdict' && m[2] === findings.verdict) || !equal(headings, findings.findings.map(f => ({ id: f.id, priority: f.priority, title: f.title })))) throw new Error('Markdown review summary mismatch');
  const expectedSummary = canonicalSummary(metadata, coverage, plan, checks);
  const blocks = [...report.matchAll(/<!-- pr-review-summary:start -->[\s\S]*?<!-- pr-review-summary:end -->/g)];
  if (blocks.length !== 1 || blocks[0][0] !== expectedSummary || report.split('<!-- pr-review-summary:start -->').length !== 2 || report.split('<!-- pr-review-summary:end -->').length !== 2) throw new Error('canonical report summary missing, duplicated or stale');
  return { valid: true, coverage: summary };
}

function canonicalSummary(metadata, coverage, plan, checks) {
  // JSON escaping keeps source paths and authored explanations on one non-executable line.
  const ordered = (_, item) => item && typeof item === 'object' && !Array.isArray(item) ? Object.fromEntries(Object.keys(item).sort().map(key => [key, item[key]])) : item;
  const value = data => '`' + JSON.stringify(data, ordered).replace(/[<>&`\u2028\u2029]/g, char => '\\u' + char.charCodeAt(0).toString(16).padStart(4, '0')) + '`';
  const lines = ['<!-- pr-review-summary:start -->', '## Review scope and evidence'];
  const add = (name, data) => lines.push(`- ${name}: ${value(data)}`);
  add('Review', Object.fromEntries(['mode', 'speed', 'risk', 'profile', 'focus', 'ci'].map(key => [key, plan[key]])));
  add('Coverage', metadata.coverage);
  add('Declared methods', Object.fromEntries(['read', 'mechanical', 'excluded', 'unreviewed'].map(method => [method, coverage.files.filter(file => file.method === method).length])));
  add('Checkout', metadata.actualCheckout);
  add('Target', metadata.reviewTarget);
  add('Source access', metadata.sourceAccess);
  add('Execution policy', metadata.executionPolicy);
  add('Delegation', metadata.delegation);
  for (const file of coverage.files) add('File', { path: file.path, classification: file.classification, declaredMethod: file.method, reason: file.reason });
  for (const behavior of coverage.behaviorPaths) add('Behavior', { id: behavior.id, risk: behavior.risk, status: behavior.status, checks: behavior.checks || [], reason: behavior.reason });
  for (const lens of plan.specialists) add('Lens', { role: lens.role, status: lens.status, route: lens.route || null, reason: lens.reason, limitations: lens.limitations || '' });
  for (const check of checks.checks) add('Check', { name: check.name, kind: check.kind, status: check.status, targetSha: check.targetSha || null, reason: check.reason });
  for (const limitation of coverage.limitations) add('Limitation', limitation);
  lines.push('Artifact consistency is not proof of comprehension, independent execution, or behavioral correctness.', '<!-- pr-review-summary:end -->');
  return lines.join('\n');
}
function renderSummary(file, cwd = process.cwd(), env = process.env) {
  const c = validateContext(file, cwd, env); const fixed = identity(c, cwd);
  const metadata = artifact(c, 'metadata.json'), coverage = artifact(c, 'coverage.json'), plan = artifact(c, 'review-plan.json'), checks = artifact(c, 'checks.json');
  for (const data of [metadata, coverage, plan, checks]) assertIdentity(data, fixed);
  // Rendering is deliberately not approval: validate-review must still check all evidence.
  return { markdown: canonicalSummary(metadata, coverage, plan, checks) };
}

function recordFailure(run, stage, error, resources) {
  const reason = stage === 'agent-readiness'
    ? 'OMP terminal readiness was not proven; resources retained before prompt submission.'
    : stage === 'agent-prompt'
      ? 'Prompt submission was not proven; inspect the recorded terminal and receipt before resuming. Do not resend automatically.'
      : 'Stage failed; resources retained. Inspect the existing Orca worktree before resuming.';
  const result = { version: 1, status: 'blocked', stage, at: new Date().toISOString(), ...resources, artifactPath: run, reason };
  // Never copy external command output, environment, or exception text into metadata.
  if (run) fs.writeFileSync(path.join(run, 'startup.json'), JSON.stringify(result, null, 2) + '\n', { mode: 0o600 });
  return result;
}

async function launch(args) {
  const options = parseArgs(args);
  const orca = orcaCommand();
  let stage = 'dependencies'; let run = null; const resources = { owner: 'orca', worktreeId: null, terminalHandle: null, worktreePath: null, orcaCommand: orca };
  try {
    for (const binary of ['git', 'gh', orca, 'omp']) command('/usr/bin/env', ['which', binary]);
    stage = 'skill-source';
    const skill = options.skillFile || path.join(os.homedir(), '.agents/skills/pr-review/SKILL.md');
    const skillText = fs.readFileSync(skill, 'utf8');
    if (!fs.statSync(skill).isFile() || !/^name: pr-review$/m.test(skillText) || !skillText.includes('**Prepared-review contract:**') || /\{\{/.test(skillText)) throw new Error('rendered prepared pr-review skill required');
    stage = 'repository';
    const callerRoot = fs.realpathSync(git(process.cwd(), 'rev-parse', '--show-toplevel'));
    resources.callerRoot = callerRoot;
    const repository = command('gh', ['repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner'], callerRoot);
    if (!REPOSITORY.test(repository) || (options.repository && !sameRepository(options.repository, repository))) throw new Error('local repository and PR URL mismatch');
    stage = 'orca-repository';
    const repositoryGitDir = fs.realpathSync(git(callerRoot, 'rev-parse', '--path-format=absolute', '--git-common-dir'));
    const repos = orcaResult(orca, ['repo', 'list'], callerRoot).repos;
    const matches = repos.filter(repo => {
      if (repo.kind !== 'git' || !path.isAbsolute(repo.path)) return false;
      try {
        return fs.realpathSync(git(repo.path, 'rev-parse', '--path-format=absolute', '--git-common-dir')) === repositoryGitDir;
      } catch { return false; } // Unavailable unrelated registrations do not select this repository.
    });
    if (matches.length !== 1) throw new Error('matching local Orca repository required');
    resources.repoId = matches[0].id;
    const fields = 'number,url,baseRefOid,headRefOid,headRepository,headRepositoryOwner,isCrossRepository';
    const metadata = () => jsonCommand('gh', ['pr', 'view', String(options.number), '--repo', repository, '--json', fields], callerRoot);
    stage = 'metadata';
    const fixed = validateMetadata(metadata(), repository, options.number);
    stage = 'objects';
    for (const [sha, repo] of [[fixed.baseSha, repository], [fixed.headSha, fixed.headRepository]]) {
      const available = spawnSync('git', ['-C', callerRoot, 'cat-file', '-e', `${sha}^{commit}`], { stdio: 'ignore', env: gitEnvironment() });
      if (available.status !== 0) git(callerRoot, 'fetch', '--no-tags', '--no-write-fetch-head', `https://github.com/${repo}.git`, sha);
      if (git(callerRoot, 'rev-parse', `${sha}^{commit}`) !== sha) throw new Error('fetched SHA mismatch');
    }
    const mergeBaseSha = mergeBase(callerRoot, fixed.baseSha, fixed.headSha);
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
    resources.name = `pr-review-${options.number}-${runId.slice(-12)}`;
    privateWrite(path.join(run, 'attempt.json'), { runId, repository, prNumber: options.number, ...fixed, ...resources });
    const creationCommand = spawnSync(orca, ['worktree', 'create', '--repo', `id:${resources.repoId}`, '--name', resources.name, '--base-branch', fixed.baseSha, '--no-parent', '--setup', 'skip', '--pr', String(options.number), ...(options.noFocus ? [] : ['--activate']), '--json'], { cwd: callerRoot, encoding: 'utf8', timeout: 300000, maxBuffer: 1024 * 1024 });
    let creation;
    try { creation = JSON.parse(creationCommand.stdout); } catch { creation = null; }
    resources.worktreeId = creation?.result?.worktree?.id || null;
    resources.worktreePath = creation?.result?.worktree?.path || null;
    resources.branch = creation?.result?.worktree?.branch || null;
    privateWrite(path.join(run, 'resources.json'), resources);
    if (creationCommand.error || creationCommand.status !== 0 || creation?.ok !== true) throw new Error('Orca worktree creation failed; inspect recorded resources before resuming');
    if (!resources.worktreeId || !resources.worktreePath || !path.isAbsolute(resources.worktreePath) || resources.worktreeId !== `${resources.repoId}::${resources.worktreePath}`) throw new Error('incomplete Orca creation response');
    stage = 'checkout-verify';
    const root = resources.worktreePath;
    if (git(root, 'rev-parse', 'HEAD') !== fixed.baseSha || git(root, 'status', '--porcelain') || fs.realpathSync(git(root, 'rev-parse', '--path-format=absolute', '--git-common-dir')) !== repositoryGitDir || fs.realpathSync(git(root, 'rev-parse', '--absolute-git-dir')) === repositoryGitDir) throw new Error('Orca base checkout mismatch');
    stage = 'agent-start';
    // Custom argv is required for a fresh, run-private OMP session; --agent cannot forward it.
    const argv = ['env', '-u', 'OMP_PROFILE', '-u', 'PI_CODING_AGENT_DIR', 'omp', '--cwd', root, '--session-dir', path.join(run, 'sessions'), '--config', path.join(run, 'omp-config.yml')];
    const terminalCommand = spawnSync(orca, ['terminal', 'create', '--worktree', `id:${resources.worktreeId}`, '--title', resources.name, '--command', `umask 077; exec ${argv.map(shellQuote).join(' ')}`, '--json'], { cwd: callerRoot, encoding: 'utf8', timeout: 300000, maxBuffer: 1024 * 1024 });
    let terminalResponse;
    try { terminalResponse = JSON.parse(terminalCommand.stdout); } catch { terminalResponse = null; }
    resources.terminalHandle = terminalResponse?.result?.terminal?.handle || null;
    fs.writeFileSync(path.join(run, 'resources.json'), JSON.stringify(resources, null, 2) + '\n', { mode: 0o600 });
    if (terminalCommand.error || terminalCommand.status !== 0 || terminalResponse?.ok !== true || !resources.terminalHandle) throw new Error('Orca terminal creation failed; inspect retained resources');
    const context = { version: 2, runId, repository, prNumber: options.number, ...fixed, mergeBaseSha, ...resources, artifactPath: run, quick: options.quick, callerRoot, repositoryGitDir };
    const contextFile = path.join(run, 'prepared-context.json'); privateWrite(contextFile, context);
    privateWrite(path.join(run, 'runtime.js'), fs.readFileSync(__filename, 'utf8'));
    // Copy the selected trusted skill so a source-render smoke never needs chezmoi apply.
    const skillFile = path.join(run, 'SKILL.md'); privateWrite(skillFile, skillText);
    stage = 'agent-readiness';
    let ready = orcaResult(orca, ['terminal', 'wait', '--terminal', resources.terminalHandle, '--for', 'tui-idle', '--timeout-ms', '60000'], callerRoot);
    if (ready.wait?.satisfied !== true) ready = orcaResult(orca, ['terminal', 'wait', '--terminal', resources.terminalHandle, '--for', 'tui-idle', '--timeout-ms', '120000'], callerRoot);
    if (ready.wait?.satisfied !== true) throw new Error('OMP terminal not ready');
    const state = orcaResult(orca, ['terminal', 'show', '--terminal', resources.terminalHandle], callerRoot).terminal;
    if (state?.handle !== resources.terminalHandle || state.worktreeId !== resources.worktreeId || !state.connected || !state.writable || fs.realpathSync(state.worktreePath) !== fs.realpathSync(root)) throw new Error('OMP terminal identity mismatch');
    assertSameRevision(fixed, validateMetadata(metadata(), repository, options.number));
    if (git(root, 'rev-parse', 'HEAD') !== fixed.baseSha || git(root, 'status', '--porcelain')) throw new Error('prepared base checkout is changed');
    stage = 'agent-prompt';
    const prompt = `Read the trusted pr-review skill at ${JSON.stringify(skillFile)} and execute its prepared-review contract now, using context ${JSON.stringify(contextFile)}. Validate with node ${JSON.stringify(path.join(run, 'runtime.js'))} validate-context ${JSON.stringify(contextFile)} first. Review only fixed PR ${repository}#${options.number}. Remain in this Orca terminal/base checkout; do not create another visible workspace, worktree, terminal, or agent environment. Preserve substantive review and security checks. Never post without explicit user confirmation.`;
    const receipt = orcaResult(orca, ['terminal', 'send', '--terminal', resources.terminalHandle, '--text', prompt, '--enter', '--wait-submit', '15'], callerRoot);
    privateWrite(path.join(run, 'submission.json'), receipt);
    if (receipt.send?.handle !== resources.terminalHandle || receipt.send.accepted !== true) throw new Error('OMP prompt not accepted');
    const status = receipt.send.prompt?.stages?.includes('turn_started') ? 'submitted' : 'accepted';
    const result = { status, stage: 'agent-prompt', runId, repository, prNumber: options.number, ...resources, artifactPath: run, contextFile, ...inspectContext(contextFile, root, { ORCA_WORKTREE_ID: resources.worktreeId, ORCA_TERMINAL_HANDLE: resources.terminalHandle }), submission: receipt };
    privateWrite(path.join(run, 'startup.json'), result);
    process.stdout.write(JSON.stringify(result, null, 2) + '\n');
  } catch (error) {
    const failure = recordFailure(run, stage, error, resources);
    process.stderr.write(JSON.stringify(failure, null, 2) + '\n');
    process.exitCode = 1;
  }
}

module.exports = { parseArgs, validateMetadata, assertSameRevision, validateContext, recordFailure, orcaCommand, inspectContext, prepareCoverage, readSource, validateReview, renderSummary };
if (require.main === module) {
  const operations = { 'validate-context': validateContext, 'inspect-context': inspectContext, 'prepare-coverage': prepareCoverage, 'validate-review': validateReview, 'render-summary': renderSummary };
  if (Object.hasOwn(operations, process.argv[2]) || process.argv[2] === 'read-source') {
    try {
      const read = process.argv[2] === 'read-source';
      if (read ? ![6, 8].includes(process.argv.length) : process.argv.length !== 4) throw new Error('invalid prepared operation arguments');
      const result = read ? readSource(...process.argv.slice(3)) : operations[process.argv[2]](process.argv[3]);
      process.stdout.write(JSON.stringify(result, null, 2) + '\n');
    } catch (error) { process.stderr.write(`pr-review: ${error.message}\n`); process.exitCode = 1; }
  } else if (process.argv.includes('--help')) {
    process.stdout.write('Usage: pr-review [--quick] [--no-focus] [--skill-file /absolute/rendered/SKILL.md] <positive-number|GitHub-PR-URL>\nRequires a local matching repository registered in Orca, its CLI/runtime, gh and OMP. No Herdr environment or integration is required. Failures retain all created resources.\n');
  } else {
    launch(process.argv.slice(2)).catch(error => { process.stderr.write(`pr-review: ${error.message}\n`); process.exitCode = 2; });
  }
}
