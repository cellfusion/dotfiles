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
assert.equal(runtime.parseArgs(['--no-focus', '--quick', 'https://github.com/a/b/pull/12']).repository, 'a/b');
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
} else if(a[0]==='repo') emit({repos:[
  {id:'missing',kind:'git',path:c.repo+'/unavailable'},
  {id:'r42',displayName:'review-project',kind:'git',path:c.repo},
  ...(c.mode==='ambiguous-project'||c.mode==='ambiguous-url'?[{id:'r43',displayName:'review-project',kind:'git',path:c.repo}]:[])
]});
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
  git('remote','add','origin','git@github.com:a/b.git');
  for(const mode of ['success','outside-url','outside-project','outside-id','project-url-mismatch','missing-project','ambiguous-project','ambiguous-url','number-cwd','unproven','url-mismatch','race','timeout','wrong-base','wrong-terminal','partial','partial-terminal','rejected']){
    const dir=path.join(root,mode); fs.mkdirSync(dir);
    const fixture={mode,repo:callerRepo,base,head,checkout:path.join(dir,'review'),log:path.join(dir,'calls'),count:path.join(dir,'count')};
    const config=path.join(dir,'fixture.json'); fs.writeFileSync(config,JSON.stringify(fixture));
    const env={...process.env,HOME:dir,PATH:bin+path.delimiter+process.env.PATH,ORCA_CLI_COMMAND:path.join(bin,'orca-fixture'),FIXTURE:config};
    for(const key of ['HERDR_ENV','HERDR_WORKSPACE_ID','HERDR_PANE_ID','ORCA_WORKTREE_ID','ORCA_TERMINAL_HANDLE','ORCA_DEV_REPO_ROOT']) delete env[key];
    const projectArgs=mode==='outside-id'?['--project','id:r42']:['outside-project','project-url-mismatch','ambiguous-project'].includes(mode)?['--project','review-project']:mode==='missing-project'?['--project','unknown']:[];
    const input=['outside-project','outside-id','missing-project','ambiguous-project','number-cwd'].includes(mode)?'1':['url-mismatch','project-url-mismatch'].includes(mode)?'https://github.com/other/repo/pull/1':'https://github.com/a/b/pull/1';
    const launched=spawnSync('bash',[path.join(process.argv[2],'private_dot_local/bin/executable_pr-review'),'--no-focus','--skill-file',skill,...projectArgs,input],{cwd:mode.startsWith('outside-')||mode==='ambiguous-url'?root:callerRepo,env,encoding:'utf8'});
    const accepted=['success','outside-url','outside-project','outside-id','number-cwd','unproven'].includes(mode);
    assert.equal(launched.status,accepted?0:1,mode+': '+launched.stderr);
    const output=JSON.parse(accepted?launched.stdout:launched.stderr);
    const calls=fs.existsSync(fixture.log)?fs.readFileSync(fixture.log,'utf8').trim().split('\n').map(JSON.parse):[];
    const creates=calls.filter(c=>c.args[0]==='worktree'&&c.args[1]==='create');
    const sends=calls.filter(c=>c.args[0]==='terminal'&&c.args[1]==='send');
    assert.equal(creates.length,['race','url-mismatch','project-url-mismatch','missing-project','ambiguous-project','ambiguous-url'].includes(mode)?0:1,mode);
    assert.equal(sends.length,accepted||mode==='rejected'?1:0,mode);
    if(accepted){
      assert.equal(output.status,mode==='unproven'?'accepted':'submitted'); assert.equal(output.worktreeId,'r42::'+fixture.checkout);
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
  // Exercise only public runtime boundaries against a divergent, local Git fixture.
  const coverageRepo=path.join(root,'coverage-repo'); fs.mkdirSync(coverageRepo); repo=coverageRepo;
  fs.writeFileSync(path.join(repo,'a'),'ancestor\nstable\n');
  fs.writeFileSync(path.join(repo,'caller'),'unchanged caller\n');
  fs.writeFileSync(path.join(repo,'literal[*].txt'),'literal path\n');
  fs.writeFileSync(path.join(repo,'old-name'),'rename content\n');
  fs.writeFileSync(path.join(repo,'deleted'),'deleted content\n');
  fs.writeFileSync(path.join(repo,'binary'),Buffer.from([0,1,2]));
  fs.symlinkSync('caller',path.join(repo,'link'));
  fs.writeFileSync(path.join(repo,'edited-old'),Array.from({length:12},(_,i)=>`rename stable ${i+1}\n`).join(''));
  fs.writeFileSync(path.join(repo,'hunks'),Array.from({length:12},(_,i)=>`stable ${i+1}\n`).join(''));
  const quotedPath='quoted \t"é\\name\nfile.txt';
  fs.writeFileSync(path.join(repo,quotedPath),'quoted stable 1\nquoted stable 2\nquoted stable 3\n');
  fs.writeFileSync(path.join(repo,'file-to-directory'),'old file\n');
  fs.mkdirSync(path.join(repo,'directory-to-file'));
  fs.writeFileSync(path.join(repo,'directory-to-file','child'),'old child\n');
  git('init','-q'); git('config','user.name','Coverage'); git('config','user.email','coverage@example.invalid');
  git('config','commit.gpgsign','false'); git('config','core.hooksPath','/dev/null');
  git('add','.'); git('commit','-qm','ancestor'); const ancestor=git('rev-parse','HEAD');
  fs.writeFileSync(path.join(repo,'a'),'head one\nhead two\nhead three\n');
  fs.renameSync(path.join(repo,'old-name'),path.join(repo,'renamed'));
  fs.mkdirSync(path.join(repo,'old-name'));
  fs.writeFileSync(path.join(repo,'old-name','child'),'new directory child\n');
  fs.unlinkSync(path.join(repo,'deleted'));
  fs.writeFileSync(path.join(repo,'binary'),Buffer.from([0,3,4]));
  fs.writeFileSync(path.join(repo,'added'),'new source\n');
  fs.unlinkSync(path.join(repo,'link')); fs.symlinkSync('a',path.join(repo,'link'));
  fs.renameSync(path.join(repo,'edited-old'),path.join(repo,'edited-renamed'));
  fs.writeFileSync(path.join(repo,'edited-renamed'),fs.readFileSync(path.join(repo,'edited-renamed'),'utf8').replace('rename stable 6\n','rename changed 6\n'));
  fs.writeFileSync(path.join(repo,'hunks'),fs.readFileSync(path.join(repo,'hunks'),'utf8').replace('stable 3\n','changed 3\n').replace('stable 8\n','changed 8\n'));
  fs.writeFileSync(path.join(repo,quotedPath),'quoted stable 1\nquoted stable 2\nquoted changed 3\n');
  fs.unlinkSync(path.join(repo,'file-to-directory')); fs.mkdirSync(path.join(repo,'file-to-directory'));
  fs.writeFileSync(path.join(repo,'file-to-directory','child'),'new child\n');
  fs.unlinkSync(path.join(repo,'directory-to-file','child')); fs.rmdirSync(path.join(repo,'directory-to-file'));
  fs.writeFileSync(path.join(repo,'directory-to-file'),'new file\n');
  git('add','-A'); git('commit','-qm','PR head'); const fixedHead=git('rev-parse','HEAD');
  git('checkout','--detach',ancestor);
  fs.writeFileSync(path.join(repo,'a'),'advanced base\n');
  fs.writeFileSync(path.join(repo,'base-only'),'not a PR change\n');
  git('add','.'); git('commit','-qm','advance base'); const advancedBase=git('rev-parse','HEAD');
  const coverageWorktree=path.join(root,'coverage-worktree');
  const coverageGitDir=fs.realpathSync(git('rev-parse','--path-format=absolute','--git-common-dir'));
  git('worktree','add','--detach',coverageWorktree,advancedBase); repo=coverageWorktree;
  const coverageRun=path.join(root,'coverage-run'); fs.mkdirSync(coverageRun,{mode:0o700});
  const coverageContextFile=path.join(coverageRun,'prepared-context.json');
  const coverageContext={...context,runId:'coverage-run',baseSha:advancedBase,headSha:fixedHead,
    repositoryGitDir:coverageGitDir,worktreePath:repo,worktreeId:`r42::${repo}`,artifactPath:coverageRun};
  const coverageEnv={ORCA_WORKTREE_ID:coverageContext.worktreeId,ORCA_TERMINAL_HANDLE:coverageContext.terminalHandle};
  const writeArtifact=(name,value)=>fs.writeFileSync(path.join(coverageRun,name),
    typeof value==='string'?value:JSON.stringify(value),{mode:0o600});
  writeArtifact('prepared-context.json',coverageContext);
  const checkoutBefore=git('status','--porcelain'), cwdBefore=process.cwd();
  const inspection=runtime.inspectContext(coverageContextFile,repo,coverageEnv);
  assert.equal(inspection.actualCheckout.sha,advancedBase);
  assert.equal(inspection.actualCheckout.path,repo);
  assert.equal(inspection.reviewTarget.baseSha,advancedBase);
  assert.equal(inspection.reviewTarget.headSha,fixedHead);
  assert.equal(inspection.reviewTarget.mergeBaseSha,ancestor);
  assert.equal(inspection.sourceAccess,'fixed-git-objects');
  assert.match(inspection.executionPolicy,/not.run|permission/i);
  runtime.prepareCoverage(coverageContextFile,repo,coverageEnv);
  const headManifest=JSON.parse(fs.readFileSync(path.join(coverageRun,'context/head-tree.json'),'utf8'));
  assert.equal(headManifest.sha,fixedHead);
  assert.ok(headManifest.entries.some(entry=>entry.path==='caller'&&entry.type==='blob'));
  assert.ok(!headManifest.entries.some(entry=>entry.path==='base-only'));
  const coverage=JSON.parse(fs.readFileSync(path.join(coverageRun,'coverage.json'),'utf8'));
  assert.equal(coverage.reviewId,coverageContext.runId);
  assert.equal(coverage.baseRefOid,advancedBase); assert.equal(coverage.headRefOid,fixedHead);
  assert.equal(coverage.mergeBaseOid,ancestor); assert.equal(coverage.status,'partial');
  const files=new Map(coverage.files.map(file=>[file.path,file]));
  assert.deepEqual([...files.keys()].sort(),['a','added','binary','deleted','link','renamed','edited-renamed','hunks',
    quotedPath,'old-name/child','file-to-directory','file-to-directory/child','directory-to-file','directory-to-file/child'].sort());
  assert.equal(files.get('renamed').oldPath,'old-name'); assert.match(files.get('renamed').status,/^R/);
  assert.equal(files.get('deleted').status,'D'); assert.equal(files.get('deleted').headBlob,null);
  assert.equal(files.get('added').status,'A'); assert.equal(files.get('added').baseBlob,null);
  assert.equal(files.get('edited-renamed').oldPath,'edited-old'); assert.match(files.get('edited-renamed').status,/^R/);
  for(const file of ['file-to-directory','directory-to-file/child']){
    assert.equal(files.get(file).status,'D'); assert.equal(files.get(file).headBlob,null,'deleted blob is not the replacement tree');
  }
  for(const file of ['directory-to-file','file-to-directory/child']){
    assert.equal(files.get(file).status,'A'); assert.equal(files.get(file).baseBlob,null,'added blob is not the former tree');
  }
  assert.equal(files.get('a').baseBlob,git('rev-parse',`${ancestor}:a`));
  assert.equal(files.get('a').headBlob,git('rev-parse',`${fixedHead}:a`));
  assert.ok(coverage.files.every(file=>file.classification==='unclassified'&&file.method==='unreviewed'));
  const read=(revision,file,start,end)=>runtime.readSource(coverageContextFile,revision,file,start,end,repo,coverageEnv);
  const ledgerFile=path.join(coverageRun,'context','source-reads.jsonl');
  const evidence=record=>fs.readFileSync(record.evidencePath);
  const headFirst=read('head','a',1,1);
  assert.equal(headFirst.start,1); assert.equal(headFirst.end,1); assert.equal(headFirst.totalLines,3);
  assert.equal(headFirst.complete,false); assert.equal(headFirst.blob,files.get('a').headBlob);
  assert.match(evidence(headFirst).toString(),/head one/);
  const digest=require('node:crypto').createHash('sha256').update(evidence(headFirst)).digest('hex');
  assert.equal(headFirst.sha256,digest,'read evidence digest matches the saved bytes');
  const ledgerPrefix=fs.readFileSync(ledgerFile);
  const callerRead=read('head','caller');
  assert.equal(callerRead.complete,true); assert.equal(callerRead.binary,false);
  assert.equal(evidence(callerRead).toString(),'unchanged caller\n');
  assert.ok(fs.readFileSync(ledgerFile).subarray(0,ledgerPrefix.length).equals(ledgerPrefix),'source ledger is append-only');
  const baseRead=read('base','a');
  assert.equal(baseRead.blob,files.get('a').baseBlob);
  assert.equal(evidence(baseRead).toString(),'ancestor\nstable\n','base means merge base, not advanced checkout');
  const binaryRead=read('head','binary'); assert.equal(binaryRead.binary,true);
  assert.deepEqual(evidence(binaryRead),Buffer.from([0,3,4]));
  const symlinkRead=read('head','link');
  assert.equal(evidence(symlinkRead).toString(),'a','read the Git symlink blob, never follow its target');
  assert.equal(evidence(read('head','literal[*].txt')).toString(),'literal path\n','source paths do not expand pathspec wildcards');
  assert.equal(evidence(read('base','file-to-directory')).toString(),'old file\n');
  assert.equal(evidence(read('head','file-to-directory/child')).toString(),'new child\n');
  assert.equal(evidence(read('base','directory-to-file/child')).toString(),'old child\n');
  assert.equal(evidence(read('head','directory-to-file')).toString(),'new file\n');
  assert.throws(()=>read('head','file-to-directory'),/blob|tree|source/i,'head directory is never read as a blob');
  assert.throws(()=>read('base','directory-to-file'),/blob|tree|source/i,'base directory is never read as a blob');
  git('config','diff.external','/bin/false');
  assert.equal(runtime.prepareCoverage(coverageContextFile,repo,coverageEnv).files.length,coverage.files.length,'external diff helpers are disabled');
  git('config','--unset','diff.external');
  git('replace',fixedHead,ancestor);
  assert.match(evidence(read('head','a')).toString(),/^head one/,'replace refs cannot substitute reviewed contents');
  git('replace','-d',fixedHead);
  const shallowFile=path.join(coverageGitDir,'shallow');
  fs.writeFileSync(shallowFile,advancedBase+'\n');
  assert.throws(()=>runtime.inspectContext(coverageContextFile,repo,coverageEnv),/shallow/i);
  fs.unlinkSync(shallowFile);
  const tree=git('rev-parse',`${advancedBase}^{tree}`);
  const left=git('commit-tree',tree,'-p',ancestor,'-m','left');
  const right=git('commit-tree',tree,'-p',ancestor,'-m','right');
  const firstMerge=git('commit-tree',tree,'-p',left,'-p',right,'-m','first merge');
  const secondMerge=git('commit-tree',tree,'-p',right,'-p',left,'-m','second merge');
  git('checkout','--detach',firstMerge);
  writeArtifact('prepared-context.json',{...coverageContext,baseSha:firstMerge,headSha:secondMerge});
  assert.throws(()=>runtime.inspectContext(coverageContextFile,repo,coverageEnv),/merge.base|unambiguous/i);
  git('checkout','--detach',advancedBase); writeArtifact('prepared-context.json',coverageContext);
  for(const [revision,file,start,end] of [['worktree','a'],['head','../a'],['head','/a'],['head','missing'],['head','a',0,1],['head','a',2,1],['head','a',1,99]]){
    assert.throws(()=>read(revision,file,start,end),undefined,`reject invalid source request ${revision}:${file}:${start}:${end}`);
  }
  assert.equal(git('rev-parse','HEAD'),advancedBase); assert.equal(git('status','--porcelain'),checkoutBefore);
  assert.equal(fs.readFileSync(path.join(repo,'a'),'utf8'),'advanced base\n'); assert.equal(process.cwd(),cwdBefore);
  const ledgerRecords=fs.readFileSync(ledgerFile,'utf8').trim().split('\n').map(JSON.parse);
  assert.equal(new Set(ledgerRecords.map(record=>record.id)).size,ledgerRecords.length);
  assert.ok(ledgerRecords.every(record=>record.sha256&&record.evidencePath&&record.blob));
  assert.equal(fs.statSync(ledgerFile).mode&0o777,0o600);
  assert.equal(fs.statSync(headFirst.evidencePath).mode&0o777,0o600);
  const identity={schemaVersion:1,reviewId:coverageContext.runId,repository:'a/b',prNumber:1,
    baseRefOid:advancedBase,headRefOid:fixedHead,mergeBaseOid:ancestor};
  coverage.limitations=['Fixture review intentionally incomplete; no PR execution'];
  const summary={status:'partial',fileCount:coverage.files.length,reviewedCount:0,excludedCount:0,unreviewedCount:coverage.files.length};
  const metadata={...identity,...inspection,verdict:'PASS',findingCount:0,findingIds:[],coverage:summary,
    pr:{number:1,repository:'a/b',url:'https://github.com/a/b/pull/1'},
    revision:{baseRefOid:advancedBase,headRefOid:fixedHead,mergeBaseOid:ancestor},
    workspace:{kind:'orca',path:repo,worktreeId:coverageContext.worktreeId,terminalHandle:coverageContext.terminalHandle,
      owner:'orca',owned:true,cleanupStatus:'retained'}};
  const findingArtifact={...identity,verdict:'PASS',findingCount:0,findingIds:[],findings:[]};
  const checks={...identity,verdict:'PASS',findingCount:0,findingIds:[],checks:[]};
  const plan={...identity,mode:'prepared',speed:'standard',risk:'medium',profile:'focused',
    focus:['correctness'],ci:'summary',changedFileCount:coverage.files.length,specialists:[]};
  const canonical=()=>runtime.renderSummary(coverageContextFile,repo,coverageEnv).markdown;
  const report=status=>`Coverage: ${status}\nVerdict: ${findingArtifact.verdict}\n${findingArtifact.findings.map(f=>`### ${f.id} [${f.priority}] ${f.title}\n`).join('')}`;
  function saveReview(){
    metadata.review=Object.fromEntries(['mode','speed','risk','profile','focus','ci'].map(key=>[key,plan[key]]));
    metadata.specialistReviews=plan.specialists.map(lens=>({...lens}));
    const completed=plan.specialists.filter(lens=>lens.status==='completed');
    metadata.delegation={agents:completed.some(lens=>lens.route==='independent')?'omp-internal':'none',
      route:completed.some(lens=>lens.route==='independent')?'independent':completed.some(lens=>lens.route==='sequential')?'sequential':'primary',
      reason:'Fixture records the actual completed specialist routes'};
    writeArtifact('coverage.json',coverage); writeArtifact('metadata.json',metadata);
    writeArtifact('findings.json',findingArtifact); writeArtifact('checks.json',checks);
    writeArtifact('review-plan.json',plan); writeArtifact('review.md',report(coverage.status)+canonical());
  }
  const validate=()=>runtime.validateReview(coverageContextFile,repo,coverageEnv);
  const refreshReport=()=>writeArtifact('review.md',report(coverage.status)+canonical());
  saveReview(); assert.throws(validate,/partial|incomplete/i,'an incomplete review cannot claim PASS');
  for(const artifact of [metadata,findingArtifact,checks]) artifact.verdict='BLOCKED';
  saveReview(); assert.equal(validate().valid,true,'an honest partial BLOCKED review remains valid');
  coverage.status='complete'; metadata.coverage.status='complete'; saveReview();
  assert.throws(validate,/coverage|unreviewed|classification/i,'complete cannot hide unreviewed files');
  for(const artifact of [metadata,findingArtifact,checks]) artifact.verdict='PASS';
  for(const file of coverage.files){file.classification='fixture source';file.method='excluded';file.reason='Fixture-only change excluded with explicit scope limitation';}
  files.get('a').method='read'; files.get('a').reason=''; files.get('a').evidence=[headFirst.id];
  metadata.coverage={status:'complete',fileCount:coverage.files.length,reviewedCount:1,excludedCount:coverage.files.length-1,unreviewedCount:0};
  saveReview(); assert.throws(validate,/coverage|range|incomplete|truncat/i,'a truncated read does not complete file coverage');
  const headLast=read('head','a',3,3); files.get('a').evidence.push(headLast.id);
  saveReview(); assert.throws(validate,/coverage|range|incomplete|truncat/i,'disjoint ranges retain the middle-line gap');
  const headMiddle=read('head','a',2,2); files.get('a').evidence.push(headMiddle.id);
  saveReview(); assert.deepEqual(validate().coverage,metadata.coverage,'range union completes coverage');
  // Nested metadata is consumer-visible identity, not an optional free-form annotation.
  for(const [section,field,value] of [
    ['pr','number',2],['pr','repository','other/repo'],['pr','url','https://github.com/a/b/pull/2'],
    ['revision','baseRefOid',fixedHead],['revision','headRefOid',ancestor],['revision','mergeBaseOid',advancedBase],
    ['review','mode','ordinary'],['review','speed','quick'],['review','risk','high'],['review','profile','full'],
    ['review','focus',['security']],['review','ci','none'],
    ['workspace','kind','external'],['workspace','path',root],['workspace','worktreeId','wrong'],
    ['workspace','terminalHandle','wrong'],['workspace','owner','external'],['workspace','owned',false],
    ['workspace','cleanupStatus','deleted'],['delegation','agents','omp-internal'],
    ['delegation','route','independent'],['delegation','reason',''],
  ]){
    saveReview(); const original=metadata[section][field]; metadata[section][field]=value;
    writeArtifact('metadata.json',metadata); refreshReport();
    assert.throws(validate,/metadata|revision|mismatch|review|workspace|delegation|pr|owner|retained/i,`reject nested metadata ${section}.${field}`);
    metadata[section][field]=original;
  }
  for(const section of ['pr','revision','review','workspace','delegation']){
    saveReview(); const original=metadata[section]; delete metadata[section];
    writeArtifact('metadata.json',metadata); if(section!=='delegation') refreshReport();
    assert.throws(validate,/metadata|revision|review|workspace|delegation|pr/i,`nested ${section} is required`);
    metadata[section]=original;
  }
  for(const [field,value] of [['mode','ordinary'],['speed','quick']]){
    const original=plan[field]; plan[field]=value; saveReview();
    assert.throws(validate,/mode|speed|plan|context|prepared/i,`plan ${field} must match prepared context`);
    plan[field]=original;
  }
  saveReview();
  const classifiedReason=files.get('added').reason; files.get('added').reason='';
  saveReview(); assert.throws(validate,/reason|excluded|coverage/i,'excluded files require an explicit reason');
  files.get('added').reason=classifiedReason;
  const deleted=files.get('deleted'); deleted.method='read'; deleted.reason=''; deleted.evidence=[read('base','deleted').id];
  metadata.coverage.reviewedCount++; metadata.coverage.excludedCount--;
  saveReview(); assert.equal(validate().valid,true,'deleted file is reviewed from merge-base source');
  for(const [file,revision] of [
    ['file-to-directory','base'],['file-to-directory/child','head'],
    ['directory-to-file','head'],['directory-to-file/child','base'],
  ]){
    const changed=files.get(file); changed.method='read'; changed.reason='';
    changed.evidence=[read(revision,file).id];
    metadata.coverage.reviewedCount++; metadata.coverage.excludedCount--;
  }
  saveReview(); assert.equal(validate().valid,true,'file/directory replacements are reviewed on their blob side, never as trees');
  const renamed=files.get('renamed'); renamed.method='mechanical'; renamed.reason='Exact content preserved by rename';
  renamed.evidence=[read('base','old-name').id];
  metadata.coverage.reviewedCount++; metadata.coverage.excludedCount--;
  saveReview(); assert.throws(validate,/mechanical|head|evidence|coverage/i,'mechanical review needs both sides');
  renamed.evidence.push(read('head','renamed').id); saveReview(); assert.equal(validate().valid,true);
  const mechanicalReason=renamed.reason; renamed.reason='';
  saveReview(); assert.throws(validate,/reason|mechanical|coverage/i);
  renamed.reason=mechanicalReason;
  const binaryFile=files.get('binary'), binaryExcluded={...binaryFile,evidence:[...binaryFile.evidence]};
  binaryFile.method='read'; binaryFile.evidence=[binaryRead.id]; binaryFile.reason='';
  metadata.coverage.reviewedCount++; metadata.coverage.excludedCount--;
  saveReview(); assert.throws(validate,/binary|coverage/i,'binary read is not a completed text review');
  Object.assign(binaryFile,binaryExcluded); metadata.coverage.reviewedCount--; metadata.coverage.excludedCount++;
  plan.risk='high'; plan.profile='full'; coverage.behaviorPaths=[];
  saveReview(); assert.throws(validate,/behavior|risk|path/i,'high-risk review requires an important behavior path');
  coverage.behaviorPaths=[{id:'primary-flow',risk:'high',status:'unverified',evidence:[],reason:'not inspected',
    beforeAfter:'head changes the result',reachability:'caller invokes the changed function'}];
  saveReview(); assert.throws(validate,/behavior|unverified|path/i,'unverified important path cannot be complete');
  coverage.behaviorPaths[0].status='static'; coverage.behaviorPaths[0].evidence=[callerRead.id,headFirst.id];
  saveReview(); assert.equal(validate().valid,true,'static inspection may complete without executing PR code');
  coverage.status='partial'; metadata.coverage.status='partial';
  saveReview(); assert.throws(validate,/coverage|partial|full|risk/i,'full profile cannot claim partial coverage');
  coverage.status='complete'; metadata.coverage.status='complete';
  coverage.behaviorPaths[0].status='executed';
  saveReview(); assert.throws(validate,/check|execut|evidence/i,'source reads alone cannot prove execution');
  coverage.behaviorPaths[0].status='static';
  plan.specialists=[{role:'correctness',trigger:true,status:'completed',reason:'selected primary lens',route:'primary',evidence:[],limitations:'Static review only'}];
  saveReview(); assert.throws(validate,/specialist|evidence/i,'completed lens needs source evidence');
  plan.specialists[0].evidence=[callerRead.id]; saveReview(); assert.equal(validate().valid,true);
  const primaryLens=plan.specialists[0];
  plan.specialists=[primaryLens,{...primaryLens,role:'security',route:'sequential'},{...primaryLens,role:'performance',route:'independent'}];
  saveReview(); assert.equal(validate().valid,true,'independent wins over completed sequential and primary lenses');
  metadata.delegation.agents='none'; writeArtifact('metadata.json',metadata); refreshReport();
  assert.throws(validate,/delegation|route|mismatch/i,'independent completion requires omp-internal disclosure');
  plan.specialists.pop(); saveReview(); assert.equal(validate().valid,true,'sequential wins when no independent lens completed');
  plan.specialists=[primaryLens]; saveReview();
  for(const route of ['sequential','independent']){
    plan.specialists[0].route=route; saveReview();
    assert.equal(validate().valid,true,`completed ${route} lens matches delegation`);
    metadata.delegation.route='primary'; writeArtifact('metadata.json',metadata); refreshReport();
    assert.throws(validate,/delegation|route|mismatch/i,'delegation cannot hide the strongest completed route');
    plan.specialists[0].route='primary';
  }
  saveReview();
  metadata.specialistReviews.push({...metadata.specialistReviews[0],role:'security',route:'independent'});
  writeArtifact('metadata.json',metadata); assert.throws(validate,/specialist|role|mismatch/i,'metadata cannot invent an additional independent lens');
  saveReview(); metadata.specialistReviews.push({...metadata.specialistReviews[0]});
  writeArtifact('metadata.json',metadata); assert.throws(validate,/specialist|role|duplicate/i,'specialist roles must be unique');
  saveReview();
  plan.specialists[0].route='invented'; saveReview(); assert.throws(validate,/route|specialist/i);
  plan.specialists[0].route='primary';
  const finding={id:'F-001',priority:'P1',confidence:'high',category:'correctness',path:'a',line:1,
    title:'Changed output reaches the caller',evidence:'Fixed head line 1 differs from merge base',
    impact:'Caller receives changed output',recommendation:'Preserve the required output',inline:true,source:'primary',
    beforeAfter:'Ancestor output becomes head output',reachability:'Unchanged caller consumes the changed output',
    regressionBasis:'Merge-base output satisfies the caller contract',
    validation:{kind:'static',evidence:`${baseRead.id}, ${headFirst.id}, ${callerRead.id}: caller contract compared to fixed revisions`,limitations:'No PR code was executed'}};
  findingArtifact.findings=[finding];
  for(const artifact of [metadata,findingArtifact,checks]){
    artifact.verdict='NEEDS_ATTENTION'; artifact.findingCount=1; artifact.findingIds=['F-001'];
  }
  saveReview(); writeArtifact('review.md',`Coverage: complete\nVerdict: NEEDS_ATTENTION\n### ${finding.id} [${finding.priority}] ${finding.title}\n${canonical()}`);
  assert.equal(validate().valid,true,'causal finding and all summaries agree');
  const correctReport=fs.readFileSync(path.join(coverageRun,'review.md'),'utf8');
  const correctBlock=canonical();
  assert.ok(correctBlock.startsWith('<!-- pr-review-summary:start -->'));
  assert.ok(correctBlock.trimEnd().endsWith('<!-- pr-review-summary:end -->'));
  assert.ok(correctBlock.includes('"declaredMethod":"excluded"'),'summary discloses excluded files');
  assert.ok(correctBlock.includes(classifiedReason),'summary discloses exclusion reasons');
  assert.ok(correctBlock.includes(advancedBase)&&correctBlock.includes(fixedHead),'summary discloses actual checkout and fixed target');
  assert.ok(correctBlock.includes('"profile":"full"')&&correctBlock.includes('"status":"static"'),'summary discloses review policy and static behavior evidence');
  assert.ok(correctBlock.includes('Static review only'),'summary discloses lens limitations');
  const preservedReason=files.get('added').reason;
  files.get('added').reason='A changed but still explicit exclusion reason';
  writeArtifact('coverage.json',coverage);
  assert.throws(validate,/summary|canonical|stale/i,'a previously valid block becomes stale when file declarations change');
  files.get('added').reason=preservedReason; writeArtifact('coverage.json',coverage);
  writeArtifact('review.md',correctReport+'\nUnrelated prose mentions F-999; it is not a canonical finding heading.\n');
  assert.equal(validate().valid,true,'finding-like identifiers in prose are not invented finding headings');
  writeArtifact('review.md',correctReport);
  for(const [body,label] of [
    [report(coverage.status),'missing block'],
    [correctReport+correctBlock,'duplicate block'],
    [correctReport.replace(correctBlock,correctBlock.replace('<!-- pr-review-summary:start -->','<!-- pr-review-summary:start -->\nInvented summary')),'altered block'],
  ]){
    writeArtifact('review.md',body); assert.throws(validate,/summary|canonical|block|markdown|report/i,label);
  }
  writeArtifact('review.md',correctReport.replace('<!-- pr-review-summary:end -->',''));
  assert.throws(validate,/summary|canonical|block|markdown|report/i,'unterminated canonical block is rejected');
  writeArtifact('review.md',correctReport.replace('Verdict: NEEDS_ATTENTION','Verdict: PASS'));
  assert.throws(validate,/verdict|summary|report|markdown/i,'legacy verdict disclosure remains required');
  writeArtifact('review.md',correctReport.replace('Coverage: complete','Coverage: partial'));
  assert.throws(validate,/coverage|summary|report|markdown/i,'legacy coverage disclosure remains required');
  writeArtifact('review.md',correctReport.replace(`### ${finding.id} [${finding.priority}] ${finding.title}\n`,''));
  assert.throws(validate,/finding|report|markdown/i,'canonical block does not replace the finding header');
  writeArtifact('review.md',correctReport);
  // Both rename paths and exact added lines matter even when local Git config disagrees.
  const originalFinding={...finding};
  for(const [file,basePath,addedLine,unchangedLine] of [
    ['edited-renamed','edited-old',6,1],['hunks','hunks',3,5],[quotedPath,quotedPath,3,1],
  ]){
    git('config','color.ui','always'); git('config','diff.outputIndicatorNew','>');
    git('config','diff.outputIndicatorOld','<'); git('config','diff.outputIndicatorContext','.');
    const before=read('base',basePath), after=read('head',file);
    Object.assign(finding,{path:file,line:unchangedLine,
      validation:{...originalFinding.validation,evidence:`${before.id}, ${after.id}, ${callerRead.id}: compare exact source sides`}});
    git('config','diff.renames','false'); git('config','diff.interHunkContext','20');
    saveReview(); assert.throws(validate,/inline|changed.*line/i,`${file} unchanged context is not an added line`);
    finding.line=addedLine; saveReview(); assert.equal(validate().valid,true,`${file} actual addition accepts inline location`);
    if(file==='hunks'){
      finding.line=8; saveReview(); assert.equal(validate().valid,true,'second separated hunk addition remains inline eligible');
    }
    git('config','--unset','diff.renames'); git('config','--unset','diff.interHunkContext');
    git('config','--unset','color.ui'); git('config','--unset','diff.outputIndicatorNew');
    git('config','--unset','diff.outputIndicatorOld'); git('config','--unset','diff.outputIndicatorContext');
  }
  const pureBefore=read('base','old-name'), pureAfter=read('head','renamed');
  Object.assign(finding,{path:'renamed',line:1,inline:true,
    validation:{...originalFinding.validation,evidence:`${pureBefore.id}, ${pureAfter.id}, ${callerRead.id}: pure rename`}});
  saveReview(); assert.throws(validate,/inline|changed.*line/i,'old-path directory child cannot supply the renamed file inline line');
  finding.inline=false; saveReview(); assert.equal(validate().valid,true,'pure rename remains eligible for a body-only finding');
  Object.assign(finding,originalFinding); saveReview();
  for(const field of ['beforeAfter','reachability','regressionBasis','validation']){
    const original=finding[field]; delete finding[field]; writeArtifact('findings.json',findingArtifact);
    assert.throws(validate,/finding|validation|before|reachability|regression/i,`finding needs ${field}`);
    finding[field]=original;
  }
  writeArtifact('findings.json',findingArtifact);
  for(const [artifact,name,field,value] of [
    [metadata,'metadata.json','headRefOid',ancestor],
    [checks,'checks.json','verdict','PASS'],
    [findingArtifact,'findings.json','findingCount',0],
    [findingArtifact,'findings.json','findingIds',['F-other']],
    [plan,'review-plan.json','reviewId','another-run'],
  ]){
    const original=artifact[field]; artifact[field]=value; writeArtifact(name,artifact);
    assert.throws(validate,/identity|revision|mismatch|verdict|finding|count|review/i,`reject inconsistent ${name}:${field}`);
    artifact[field]=original; writeArtifact(name,artifact);
  }
  const actualCheckout=metadata.actualCheckout; metadata.actualCheckout={...actualCheckout,sha:fixedHead};
  writeArtifact('metadata.json',metadata); assert.throws(validate,/checkout|context|disclosure|mismatch/i);
  metadata.actualCheckout=actualCheckout; writeArtifact('metadata.json',metadata);
  metadata.actualCheckout={path:actualCheckout.path,sha:actualCheckout.sha,branch:actualCheckout.branch};
  writeArtifact('metadata.json',metadata); refreshReport(); assert.equal(validate().valid,true,'JSON object key order does not change artifact identity');
  const originalValidation=finding.validation;
  const originalBehavior={...coverage.behaviorPaths[0]};
  finding.validation={kind:'local',evidence:originalValidation.evidence,limitations:'Isolated fixture',checks:['fixture-test']};
  saveReview(); assert.throws(validate,/check|validation|evidence/i,'local execution claim requires a recorded check');
  checks.checks=[{name:'fixture-test',kind:'local',command:'fixture-only assertion',status:'not_run',
    evidence:'Not executed',reason:'No execution permission',at:'2026-10-15T00:00:00Z'}];
  coverage.behaviorPaths[0].status='executed'; coverage.behaviorPaths[0].checks=['fixture-test'];
  saveReview(); assert.throws(validate,/check|execut|validation/i,'not_run is not execution evidence');
  for(const kind of ['local','ci']){
    finding.validation.kind=kind;
    for(const status of ['pass','fail']){
      for(const targetSha of [undefined,ancestor]){
        checks.checks[0]={...checks.checks[0],kind,status,targetSha,evidence:'Recorded fixture execution'};
        saveReview(); assert.throws(validate,/target|revision/i,`${kind} ${status} requires the fixed head`);
      }
      checks.checks[0]={...checks.checks[0],kind,status,targetSha:fixedHead,evidence:`Fixture execution at ${fixedHead}`};
      saveReview(); assert.equal(validate().valid,true,`${kind} ${status} supports findings and an executed behavior path`);
    }
  }
  checks.checks[0].kind='ci'; finding.validation.kind='local';
  saveReview(); assert.throws(validate,/check|execution/i,'CI execution cannot be relabelled as local reproduction');
  // Execute only a trusted, harmless assertion over saved Git bytes, never PR code.
  const fixtureAssertion="require('node:assert/strict').equal(process.argv[1], 'ancestor\\nstable\\n')";
  const baseAssertion=spawnSync(process.execPath,['-e',fixtureAssertion,evidence(baseRead).toString()],{encoding:'utf8'});
  const headAssertion=spawnSync(process.execPath,['-e',fixtureAssertion,evidence(read('head','a')).toString()],{encoding:'utf8'});
  assert.equal(baseAssertion.status,0,baseAssertion.stderr); assert.equal(headAssertion.status,1);
  assert.match(headAssertion.stderr,/AssertionError/);
  checks.checks[0]={name:'fixture-test',kind:'local',command:'node -e trusted fixture assertion over fixed Git source bytes',
    status:'fail',targetSha:fixedHead,at:'2026-10-15T00:00:00Z',
    evidence:`Harmless assertion: base ${ancestor} exit ${baseAssertion.status}; head ${fixedHead} exit ${headAssertion.status}; AssertionError`};
  finding.validation={...originalValidation,kind:'local',checks:['fixture-test'],
    limitations:'Only the trusted fixture assertion executed; no PR code'};
  saveReview(); assert.equal(validate().valid,true,'base exit 0 and fixed-head exit 1 substantiate a regression finding');
  assert.ok(canonical().includes('"status":"fail"'),'canonical summary discloses failed execution rather than suppressing it');
  checks.checks[0].status='pass'; writeArtifact('checks.json',checks);
  assert.throws(validate,/summary|canonical|stale/i,'check result changes invalidate the saved canonical summary');
  checks.checks[0].status='fail'; saveReview();
  finding.validation=originalValidation; checks.checks=[];
  coverage.behaviorPaths[0]=originalBehavior;
  saveReview();
  for(const kind of ['local','ci']) for(const status of ['pass','fail']){
    checks.checks=[{name:'unused-check',kind,status,command:'fixture-only assertion',evidence:'Recorded execution',
      targetSha:ancestor,at:'2026-10-15T00:00:00Z'}];
    saveReview(); assert.throws(validate,/target|revision/i,'unused execution checks also require the fixed head');
  }
  checks.checks=[]; saveReview();
  const originalCount=metadata.coverage.reviewedCount; metadata.coverage.reviewedCount++;
  writeArtifact('metadata.json',metadata); assert.throws(validate,/coverage|count|mismatch/i);
  metadata.coverage.reviewedCount=originalCount; writeArtifact('metadata.json',metadata);
  const originalEvidence=files.get('a').evidence; files.get('a').evidence=['unknown-read'];
  writeArtifact('coverage.json',coverage); assert.throws(validate,/read|evidence|coverage/i);
  files.get('a').evidence=originalEvidence; writeArtifact('coverage.json',coverage);
  const originalBytes=evidence(headFirst);
  fs.writeFileSync(headFirst.evidencePath,'tampered fixture evidence',{mode:0o600});
  assert.throws(validate,/evidence|digest|hash|read/i,'source evidence cannot be changed after recording');
  fs.writeFileSync(headFirst.evidencePath,originalBytes,{mode:0o600});
  const runtimeFile=path.join(process.argv[2],'private_dot_local/private_share/pr-review/runtime.js');
  const cli=(command,...args)=>spawnSync(process.execPath,[runtimeFile,command,coverageContextFile,...args],
    {cwd:repo,env:{...process.env,...coverageEnv},encoding:'utf8'});
  const inspected=cli('inspect-context'); assert.equal(inspected.status,0,inspected.stderr);
  assert.deepEqual(JSON.parse(inspected.stdout),inspection,'CLI discloses the same fixed review target');
  const rendered=cli('render-summary'); assert.equal(rendered.status,0,rendered.stderr);
  assert.deepEqual(JSON.parse(rendered.stdout),runtime.renderSummary(coverageContextFile,repo,coverageEnv),
    'CLI renders the same canonical summary as the public API');
  const preparedAgain=cli('prepare-coverage'); assert.equal(preparedAgain.status,0,preparedAgain.stderr);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(coverageRun,'coverage.json'),'utf8')),coverage,
    'preparing an existing run does not erase completed coverage');
  const cliRead=cli('read-source','head','caller'); assert.equal(cliRead.status,0,cliRead.stderr);
  assert.equal(JSON.parse(cliRead.stdout).blob,callerRead.blob);
  const validated=cli('validate-review'); assert.equal(validated.status,0,validated.stderr);
  assert.equal(JSON.parse(validated.stdout).valid,true);
  const badCliRead=cli('read-source','head','../a'); assert.notEqual(badCliRead.status,0);
  writeArtifact('review.md',`Coverage: complete\nVerdict: NEEDS_ATTENTION\n${canonical()}`);
  assert.throws(validate,/finding|report|markdown/i,'report cannot omit a canonical finding');
  const rejectedCli=cli('validate-review'); assert.notEqual(rejectedCli.status,0);
  assert.equal(git('rev-parse','HEAD'),advancedBase); assert.equal(git('status','--porcelain'),checkoutBefore);
} finally { fs.rmSync(root,{recursive:true,force:true}); }
NODE
assert_eq "$result" 0 'PR preparation, fixed-object source ledger, coverage and review consistency boundaries'
assert_summary
