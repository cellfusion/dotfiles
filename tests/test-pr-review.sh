#!/usr/bin/env bash
set -eu
SOURCE="$(cd "$(dirname "$0")/.." && pwd)"
source "$SOURCE/tests/lib/assert.sh"
result=0
node - "$SOURCE" <<'NODE' || result=$?
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const runtime = require(path.join(process.argv[2], 'private_dot_local/private_share/pr-review/runtime.js'));
for (const input of [[], ['0'], ['01'], ['-1'], ['1', '2'], ['--worktree', '1'], ['--quick', '--quick', '1'], ['https://evil.test/a/b/pull/1'], ['https://github.com/a/b/pull/1?x=1']]) {
  assert.throws(() => runtime.parseArgs(input), /input|option|positive|URL/);
}
assert.deepEqual(runtime.parseArgs(['--no-focus', '--quick', 'https://github.com/a/b/pull/12']), {
  number: 12, repository: 'a/b', quick: true, noFocus: true, skillFile: null,
});
assert.equal(runtime.parseArgs(['123']).number, 123);
assert.throws(() => runtime.validateMetadata({number: 1, baseRefOid:'a'.repeat(40), headRefOid:'b'.repeat(40), url:'https://github.com/a/b/pull/1', isCrossRepository:true, headRepository:null}, 'a/b', 1), /fork/);
assert.equal(runtime.validateMetadata({number: 1, baseRefOid:'a'.repeat(40), headRefOid:'b'.repeat(40), url:'https://github.com/a/b/pull/1', isCrossRepository:true, headRepository:{name:'fork'}, headRepositoryOwner:{login:'other'}}, 'a/b', 1).headRepository, 'other/fork');
const fixed={baseSha:'a'.repeat(40),headSha:'b'.repeat(40),headRepository:'other/fork'};
for (const changed of [{...fixed,baseSha:'c'.repeat(40)},{...fixed,headSha:'d'.repeat(40)},{...fixed,headRepository:'wrong/repo'}]) {
  assert.throws(()=>runtime.assertSameRevision(fixed,changed),/revision changed/);
}
assert.throws(()=>runtime.validateMetadata({number:1,baseRefOid:fixed.baseSha,headRefOid:fixed.headSha,url:'https://github.com/wrong/repo/pull/1',isCrossRepository:false},'a/b',1),/repository mismatch/);
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pr-review-boundary-'));
try {
  const callerRepo = path.join(root, 'repo'); fs.mkdirSync(callerRepo); let repo = callerRepo;
  function git(...args) { const r=spawnSync('git', ['-C', repo, ...args], {encoding:'utf8'}); assert.equal(r.status,0,r.stderr); return r.stdout.trim(); }
  git('init', '-q'); git('config','user.name','Boundary'); git('config','user.email','boundary@example.invalid');
  git('config','commit.gpgsign','false'); git('config','core.hooksPath','/dev/null');
  fs.writeFileSync(path.join(repo,'a'),'base'); git('add','a'); git('commit','-qm','base'); const base=git('rev-parse','HEAD');
  fs.writeFileSync(path.join(repo,'a'),'head'); git('commit','-qam','head'); const head=git('rev-parse','HEAD');
  const repositoryGitDir=fs.realpathSync(git('rev-parse','--path-format=absolute','--git-common-dir'));
  const linked=path.join(root,'review'); git('worktree','add','--detach',linked,base); repo=linked;
  const run = path.join(root,'run'); fs.mkdirSync(run,{mode:0o700});
  const contextFile=path.join(run,'prepared-context.json');
  const context={version:1,runId:'test-run',repository:'a/b',headRepository:'a/b',repositoryGitDir,prNumber:1,baseSha:base,headSha:head,owner:'herdr',worktreePath:repo,artifactPath:run,workspaceId:'w42',rootPaneId:'w42:p1',quick:false};
  function save(value=context) { fs.writeFileSync(contextFile,JSON.stringify(value),{mode:0o600}); }
  save();
  const env={HERDR_ENV:'1',HERDR_WORKSPACE_ID:'w42',HERDR_PANE_ID:'w42:p1'};
  assert.equal(runtime.validateContext(contextFile, repo, env).baseSha,base);
  assert.equal(runtime.validateContext(contextFile,repo,env).runId, 'test-run');
  assert.equal(git('worktree','list','--porcelain').split('worktree ').length-1,2);
  fs.writeFileSync(path.join(repo,'untracked'),'dirty');
  assert.throws(()=>runtime.validateContext(contextFile,repo,env),/base checkout is changed/); fs.unlinkSync(path.join(repo,'untracked'));
  save({...context,version:2}); assert.throws(()=>runtime.validateContext(contextFile,repo,env),/version/); save();
  const checkoutMain=spawnSync('git',['-C',callerRepo,'checkout','--detach',base],{encoding:'utf8'}); assert.equal(checkoutMain.status,0,checkoutMain.stderr);
  save({...context,worktreePath:callerRepo}); assert.throws(()=>runtime.validateContext(contextFile,callerRepo,env),/linked worktree/); save();
  save({...context,headSha:'c'.repeat(40)}); assert.throws(()=>runtime.validateContext(contextFile,repo,env),/git command failed|head/); save();
  save({...context,repositoryGitDir:root}); assert.throws(()=>runtime.validateContext(contextFile,repo,env),/repository/); save();
  assert.throws(()=>runtime.validateContext(contextFile,root,env),/cwd/);
  assert.throws(()=>runtime.validateContext(contextFile,repo,{...env,HERDR_PANE_ID:'w42:p2'}),/pane/);
  save({...context,owner:'external'}); assert.throws(()=>runtime.validateContext(contextFile,repo,env),/owner/);
  save(); git('checkout','--detach',head); assert.throws(()=>runtime.validateContext(contextFile,repo,env),/base/);
  git('checkout','--detach',base); fs.chmodSync(contextFile,0o644); assert.throws(()=>runtime.validateContext(contextFile,repo,env),/private/);
  const resources={worktreePath:repo,workspaceId:'w42',rootPaneId:'w42:p1'};
  const failure=runtime.recordFailure(run,'agent-start',new Error('sensitive output'),resources);
  assert.equal(failure.stage,'agent-start'); assert.equal(failure.status,'blocked'); assert.equal(failure.workspaceId,'w42');
  assert.ok(fs.existsSync(repo)); assert.ok(fs.existsSync(contextFile));
  assert.ok(!fs.readFileSync(path.join(run,'startup.json'),'utf8').includes('sensitive output'));
} finally { fs.rmSync(root,{recursive:true,force:true}); }
NODE
assert_eq "$result" 0 'PR parsing, fork identity, prepared ownership/cwd/base and failure retention boundaries'
assert_summary
