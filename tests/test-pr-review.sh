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
assert.equal(runtime.orcaCommand({}, 'linux'), 'orca-ide');
assert.equal(runtime.orcaCommand({ORCA_TERMINAL_HANDLE:'term'}, 'linux'), 'orca');
assert.equal(runtime.orcaCommand({ORCA_DEV_REPO_ROOT:'/dev'}, 'darwin'), 'orca-dev');
assert.equal(runtime.orcaCommand({ORCA_CLI_COMMAND:'/custom/orca',ORCA_DEV_REPO_ROOT:'/dev'}, 'darwin'), '/custom/orca');
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
  const context={version:2,runId:'test-run',repository:'a/b',headRepository:'a/b',repositoryGitDir,prNumber:1,baseSha:base,headSha:head,owner:'orca',worktreePath:repo,artifactPath:run,worktreeId:`r42::${repo}`,terminalHandle:'term_review',quick:false};
  function save(value=context) { fs.writeFileSync(contextFile,JSON.stringify(value),{mode:0o600}); }
  save();
  const env={ORCA_WORKTREE_ID:`r42::${repo}`,ORCA_TERMINAL_HANDLE:'term_review'};
  assert.equal(runtime.validateContext(contextFile, repo, env).baseSha,base);
  assert.equal(runtime.validateContext(contextFile,repo,env).runId, 'test-run');
  fs.writeFileSync(path.join(repo,'untracked'),'dirty');
  assert.throws(()=>runtime.validateContext(contextFile,repo,env),/base checkout is changed/); fs.unlinkSync(path.join(repo,'untracked'));
  save({...context,version:1}); assert.throws(()=>runtime.validateContext(contextFile,repo,env),/version/); save();
  const checkoutMain=spawnSync('git',['-C',callerRepo,'checkout','--detach',base],{encoding:'utf8'}); assert.equal(checkoutMain.status,0,checkoutMain.stderr);
  save({...context,worktreePath:callerRepo,worktreeId:`r42::${callerRepo}`}); assert.throws(()=>runtime.validateContext(contextFile,callerRepo,{...env,ORCA_WORKTREE_ID:`r42::${callerRepo}`}),/linked worktree/); save();
  save({...context,headSha:'c'.repeat(40)}); assert.throws(()=>runtime.validateContext(contextFile,repo,env),/git command failed|head/); save();
  save({...context,repositoryGitDir:root}); assert.throws(()=>runtime.validateContext(contextFile,repo,env),/repository/); save();
  assert.throws(()=>runtime.validateContext(contextFile,root,env),/cwd/);
  assert.throws(()=>runtime.validateContext(contextFile,repo,{...env,ORCA_TERMINAL_HANDLE:'term_other'}),/terminal/);
  assert.throws(()=>runtime.validateContext(contextFile,repo,{}),/terminal/);
  save({...context,worktreeId:'r42'}); assert.throws(()=>runtime.validateContext(contextFile,repo,env),/worktree/); save();
  save({...context,owner:'external'}); assert.throws(()=>runtime.validateContext(contextFile,repo,env),/owner/);
  save(); git('checkout','--detach',head); assert.throws(()=>runtime.validateContext(contextFile,repo,env),/base/);
  git('checkout','--detach',base); fs.chmodSync(contextFile,0o644); assert.throws(()=>runtime.validateContext(contextFile,repo,env),/private/);
  const resources={worktreePath:repo,worktreeId:`r42::${repo}`,terminalHandle:'term_review'};
  const failure=runtime.recordFailure(run,'agent-start',new Error('sensitive output'),resources);
  assert.equal(failure.stage,'agent-start'); assert.equal(failure.status,'blocked'); assert.equal(failure.terminalHandle,'term_review');
  assert.ok(fs.existsSync(repo)); assert.ok(fs.existsSync(contextFile));
  assert.ok(!fs.readFileSync(path.join(run,'startup.json'),'utf8').includes('sensitive output'));
  const bin=path.join(root,'bin'); fs.mkdirSync(bin);
  const driver=path.join(bin,'driver');
  fs.writeFileSync(driver, `#!${process.execPath}
const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const c=JSON.parse(fs.readFileSync(process.env.FIXTURE,'utf8')),a=process.argv.slice(2);
const flag=k=>a[a.indexOf(k)+1], emit=result=>console.log(JSON.stringify({ok:true,result}));
const name=path.basename(process.argv[1]);
fs.appendFileSync(c.log,JSON.stringify({name,args:a})+'\\n');
if(name==='gh'){
  if(a[0]==='repo') console.log('a/b');
  else {
    let n=fs.existsSync(c.count)?Number(fs.readFileSync(c.count,'utf8')):0;
    fs.writeFileSync(c.count,String(n+1));
    console.log(JSON.stringify({number:1,url:'https://github.com/a/b/pull/1',baseRefOid:c.base,headRefOid:c.mode==='race'&&n>0?c.base:c.head,isCrossRepository:false}));
  }
} else if(a[0]==='repo') emit({repos:[{id:'missing',kind:'git',path:c.repo+'/unavailable'},{id:'r42',kind:'git',path:c.repo}]});
else if(a[0]==='worktree'){
  const r=spawnSync('git',['-C',c.repo,'worktree','add','--detach',c.checkout,c.mode==='wrong-base'?c.head:flag('--base-branch')],{encoding:'utf8'});
  if(r.status!==0) process.exit(2);
  emit({worktree:{id:'r42::'+c.checkout,path:c.checkout,branch:null}});
  if(c.mode==='partial') process.exit(1);
} else if(a[1]==='create') {
  process.umask(0o022); // Orca's host does not inherit the entry command's private umask.
  const started=spawnSync('/bin/sh',['-c',flag('--command')],{env:process.env,encoding:'utf8'});
  if(started.status!==0)process.exit(2);
  emit({terminal:{handle:'term_review'}}); if(c.mode==='partial-terminal')process.exit(1);
}
else if(a[1]==='wait') emit({wait:{satisfied:c.mode!=='timeout'}});
else if(a[1]==='show') emit({terminal:{handle:'term_review',worktreeId:(c.mode==='wrong-terminal'?'other':'r42')+'::'+c.checkout,worktreePath:c.checkout,connected:true,writable:true}});
else if(a[1]==='send') emit({send:{handle:'term_review',accepted:c.mode!=='rejected',prompt:{requestId:'request-1',stages:c.mode==='unproven'?['input_accepted']:['input_accepted','turn_started']}}});
else process.exit(2);
`,{mode:0o700});
  fs.symlinkSync(driver,path.join(bin,'gh')); fs.symlinkSync(driver,path.join(bin,'orca-fixture'));
  fs.writeFileSync(path.join(bin,'omp'),`#!${process.execPath}\nconst fs=require('node:fs'),path=require('node:path'),a=process.argv.slice(2);fs.writeFileSync(path.join(a[a.indexOf('--session-dir')+1],'session.jsonl'),'private session');\n`,{mode:0o700});
  const skill=path.join(root,'SKILL.md');
  fs.writeFileSync(skill,'---\nname: pr-review\n---\n**Prepared-review contract:**\n');
  for(const mode of ['success','unproven','url-mismatch','race','timeout','wrong-base','wrong-terminal','partial','partial-terminal','rejected']){
    const dir=path.join(root,mode); fs.mkdirSync(dir);
    const fixture={mode,repo:callerRepo,base,head,checkout:path.join(dir,'review'),log:path.join(dir,'calls'),count:path.join(dir,'count')};
    const config=path.join(dir,'fixture.json'); fs.writeFileSync(config,JSON.stringify(fixture));
    const env={...process.env,HOME:dir,PATH:bin+path.delimiter+process.env.PATH,ORCA_CLI_COMMAND:path.join(bin,'orca-fixture'),FIXTURE:config};
    for(const key of ['HERDR_ENV','HERDR_WORKSPACE_ID','HERDR_PANE_ID','ORCA_WORKTREE_ID','ORCA_TERMINAL_HANDLE','ORCA_DEV_REPO_ROOT']) delete env[key];
    const launched=spawnSync('bash',[path.join(process.argv[2],'private_dot_local/bin/executable_pr-review'),'--no-focus','--skill-file',skill,mode==='url-mismatch'?'https://github.com/other/repo/pull/1':'https://github.com/a/b/pull/1'],{cwd:callerRepo,env,encoding:'utf8'});
    const accepted=['success','unproven'].includes(mode);
    const output=JSON.parse(accepted?launched.stdout:launched.stderr);
    assert.equal(launched.status,accepted?0:1,launched.stderr);
    const calls=fs.existsSync(fixture.log)?fs.readFileSync(fixture.log,'utf8').trim().split('\n').map(JSON.parse):[];
    const creates=calls.filter(c=>c.args[0]==='worktree'&&c.args[1]==='create');
    const sends=calls.filter(c=>c.args[0]==='terminal'&&c.args[1]==='send');
    assert.equal(creates.length,['race','url-mismatch'].includes(mode)?0:1,mode);
    assert.equal(sends.length,['success','unproven','rejected'].includes(mode)?1:0,mode);
    if(accepted){
      assert.equal(output.status,mode==='success'?'submitted':'accepted'); assert.equal(output.worktreeId,'r42::'+fixture.checkout);
      assert.equal(git('rev-parse','HEAD'),base);
      assert.equal(spawnSync('git',['-C',fixture.checkout,'rev-parse','HEAD'],{encoding:'utf8'}).stdout.trim(),base);
      assert.equal(fs.statSync(output.artifactPath).mode&0o777,0o700);
      assert.equal(fs.statSync(output.contextFile).mode&0o777,0o600);
      assert.equal(fs.statSync(path.join(output.artifactPath,'sessions','session.jsonl')).mode&0o777,0o600);
      const prepared=JSON.parse(fs.readFileSync(output.contextFile,'utf8'));
      assert.equal(runtime.validateContext(output.contextFile,fixture.checkout,{ORCA_WORKTREE_ID:output.worktreeId,ORCA_TERMINAL_HANDLE:output.terminalHandle}).headSha,head);
      assert.equal(prepared.owner,'orca');
    } else {
      assert.equal(output.status,'blocked');
      if(creates.length){assert.ok(fs.existsSync(fixture.checkout));assert.ok(fs.existsSync(path.join(output.artifactPath,'startup.json')));}
      if(mode==='partial') assert.equal(output.worktreePath,fixture.checkout);
      if(mode==='partial-terminal') assert.equal(output.terminalHandle,'term_review');
      if(mode==='timeout') assert.equal(output.stage,'agent-readiness');
      if(mode==='rejected') assert.ok(fs.existsSync(path.join(output.artifactPath,'submission.json')));
    }
  }
} finally { fs.rmSync(root,{recursive:true,force:true}); }
NODE
assert_eq "$result" 0 'PR parsing, fork identity, prepared ownership/cwd/base and failure retention boundaries'
assert_summary
