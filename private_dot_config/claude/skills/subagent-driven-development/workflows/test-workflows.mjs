// workflow script の回帰テスト。エージェントを 1 つも起動しない。
//
//   node ~/.config/claude/skills/subagent-driven-development/workflows/test-workflows.mjs
//
// agent / phase / log を差し替えた fake ランタイムでスクリプト本体を実行し、
// 生成される dispatch プロンプトと戻り値を検証する。workflow のランタイムは
// スクリプト本体を async 関数として実行するので、ここでも同じ形で包む。
//
// 一番大事な検証: args が JSON 文字列で届いてもプロンプトが "undefined" にならないこと。
// 実測では Workflow ツールにオブジェクトを渡しても script には文字列で届く。
//
// canned 応答は、スクリプトが agent() に渡してきたスキーマに照らして検証する。
// 契約が変わったのに canned が古いままだと、このテストが緑のまま何も守らなくなる。
import fs from 'node:fs'
import path from 'node:path'

const HERE = import.meta.dirname

// overrides: agentType ごとに canned 応答を差し替える。fix 波のように、既定の
// 「指摘なし」応答では到達しない分岐を踏ませたいときに使う。
async function runScript(file, argsValue, overrides = {}) {
  const src = fs.readFileSync(file, 'utf8').replace(/^export const meta =/m, 'const meta =')
  const calls = []
  const logs = []
  const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor

  const canned = Object.assign({}, {
    'sdd-implementer': {
      status: 'DONE',
      commits: ['abc1234 feat: do the thing'],
      round: 0,
      baseHead: null,
      changedFiles: null,
      proposedCommitMessage: null,
      head: 'abc1234def',
      reviewPackagePath: '/tmp/pkg.diff',
      testSummary: '3/3 passing',
      concerns: null,
      detail: null,
    },
    'sdd-task-reviewer': {
      specVerdict: 'compliant',
      qualityVerdict: 'approved',
      findings: [],
      cannotVerify: [],
      strengths: 'clean',
      round: 0,
      head: 'abc1234def',
      packageBase: 'base9999',
      packageHead: 'abc1234def',
    },
    'sdd-final-reviewer': {
      status: 'CLEAN',
      readyToMerge: 'yes',
      findings: [],
      triage: [],
      strengths: 'clean',
      reasoning: 'ok',
      round: 0,
      head: 'head0000',
      packageBase: 'mb00000',
      packageHead: 'head0000',
    },
    'sdd-re-reviewer': {
      verdicts: [], newBreakage: [], outOfScope: [], round: 0, head: 'head0000',
      packageBase: 'head0000', packageHead: 'abc1234def',
    },
  }, overrides)

  // canned 応答をスクリプトが渡してきたスキーマに照らす。契約が変わったのに canned が
  // 古いままだと、このテストは緑のまま何も守らなくなる。
  const validate = (agentType, schema, value) => {
    if (!schema) return
    const missing = (schema.required || []).filter((k) => !(k in value))
    if (missing.length) {
      throw new Error(`canned(${agentType}) に必須項目が無い: ${missing.join(', ')}`)
    }
    const props = schema.properties || {}
    if (schema.additionalProperties === false) {
      const extra = Object.keys(value).filter((k) => !(k in props))
      if (extra.length) {
        throw new Error(`canned(${agentType}) にスキーマ外の項目がある: ${extra.join(', ')}`)
      }
    }
    for (const [k, p] of Object.entries(props)) {
      if (p.enum && k in value && !p.enum.includes(value[k])) {
        throw new Error(`canned(${agentType}) の ${k} が enum 外: ${value[k]}`)
      }
    }
  }

  const agent = async (prompt, opts = {}) => {
    calls.push({ prompt, opts })
    if (!(opts.agentType in canned)) throw new Error('unexpected agentType: ' + opts.agentType)
    const value = canned[opts.agentType]
    validate(opts.agentType, opts.schema, value)
    return value
  }

  const fn = new AsyncFunction('args', 'agent', 'parallel', 'pipeline', 'log', 'phase', 'budget', src)
  const result = await fn(
    argsValue,
    agent,
    async () => [],
    async () => [],
    (m) => logs.push(m),
    () => {},
    { total: null, spent: () => 0, remaining: () => Infinity }
  )
  return { result, calls, logs }
}

const taskArgs = {
  plan: '_cellfusion/plans/2026-07-31-thing.md',
  taskNumber: 1,
  taskName: 'スライスを選ぶと次のスライス点で止まる',
  briefPath: '_cellfusion/sdd/2026-07-31-thing/task-1-brief.md',
  reportPath: '_cellfusion/sdd/2026-07-31-thing/task-1-report.md',
  base: 'base9999',
  globalConstraints: '- core は platform-agnostic を保つ',
  context: 'サンプラーのスライス機能の 1 段目',
}

const finalArgs = {
  plan: '_cellfusion/plans/2026-07-31-thing.md',
  packagePath: '_cellfusion/sdd/2026-07-31-thing/review-mb..head.diff',
  mergeBase: 'mb00000',
  head: 'head0000',
  description: 'サンプラーのスライス機能',
  deferred: ['minor 1'],
  parked: [],
}

let failures = 0
const check = (name, cond, detail) => {
  if (cond) return console.log(`  PASS  ${name}`)
  failures++
  console.log(`  FAIL  ${name}${detail ? '\n        ' + detail : ''}`)
}
const undefLines = (s) =>
  s.split('\n').filter((l) => l.includes('undefined')).slice(0, 3).join('\n        ')

for (const [label, argsValue] of [
  ['args = JSON 文字列（実測の到着形）', JSON.stringify(taskArgs)],
  ['args = オブジェクト（ドキュメント上の契約）', taskArgs],
]) {
  console.log(`\n[sdd-task.js] ${label}`)
  try {
    const { result, calls } = await runScript(path.join(HERE, 'sdd-task.js'), argsValue)
    const first = calls[0]?.prompt ?? ''
    check('implementer が dispatch された', calls.length >= 1)
    check('プロンプトに undefined が出ない', !first.includes('undefined'), undefLines(first))
    check('プロンプトに実際のタスク名が入る', first.includes(taskArgs.taskName))
    check('プロンプトに brief パスが入る', first.includes(taskArgs.briefPath))
    check('status が COMPLETE', result?.status === 'COMPLETE', `status=${result?.status}`)
  } catch (e) {
    failures++
    console.log(`  FAIL  実行中に例外: ${e.message}`)
  }
}

for (const [label, argsValue] of [
  ['args = JSON 文字列（実測の到着形）', JSON.stringify(finalArgs)],
  ['args = オブジェクト（ドキュメント上の契約）', finalArgs],
]) {
  console.log(`\n[sdd-final-review.js] ${label}`)
  try {
    const { result, calls } = await runScript(path.join(HERE, 'sdd-final-review.js'), argsValue)
    const first = calls[0]?.prompt ?? ''
    check('final-reviewer が dispatch された', calls.length >= 1)
    check('プロンプトに undefined が出ない', !first.includes('undefined'), undefLines(first))
    check('プロンプトに package パスが入る', first.includes(finalArgs.packagePath))
    check('status が CLEAN', result?.status === 'CLEAN', `status=${result?.status}`)
  } catch (e) {
    failures++
    console.log(`  FAIL  実行中に例外: ${e.message}`)
  }
}

console.log('\n[workdir を渡すと作業ディレクトリの指示が入る]')
try {
  const wd = '/repo/.worktrees/task-1'
  const { calls } = await runScript(
    path.join(HERE, 'sdd-task.js'),
    JSON.stringify({ ...taskArgs, workdir: wd })
  )
  const first = calls[0]?.prompt ?? ''
  check('プロンプトに worktree のパスが入る', first.includes(wd))
  check('コマンドが worktree で実行される形になる', first.includes(`cd ${wd} &&`))
  check('並行していることが伝わる', first.includes('並行'))
} catch (e) {
  failures++
  console.log(`  FAIL  実行中に例外: ${e.message}`)
}

console.log('\n[workdir なしなら cd を挟まない]')
try {
  const { calls } = await runScript(path.join(HERE, 'sdd-task.js'), JSON.stringify(taskArgs))
  const first = calls[0]?.prompt ?? ''
  check('cd が入らない', !first.includes('cd /'))
  check('作業ディレクトリ節が出ない', !first.includes('## 作業ディレクトリ'))
} catch (e) {
  failures++
  console.log(`  FAIL  実行中に例外: ${e.message}`)
}

// scripts の実体は ~/.agents/skills 側の 1 箇所にしかない。既定値が旧パスに戻ると、
// 旧ディレクトリを掃除した環境で review-package が見つからず全タスクが失敗する。
console.log('\n[scriptsDir 未指定なら review-package は ~/.agents/skills を叩く]')
const SHARED_SCRIPTS = '~/.agents/skills/subagent-driven-development/scripts'
const OLD_SCRIPTS = '~/.config/claude/skills/subagent-driven-development/scripts'
// sdd-final-review.js は blocking な指摘があって初めて fix 波の
// review-package コマンドを組み立てるので、指摘ありの応答を差し込む。
const blockingReview = {
  'sdd-final-reviewer': {
    status: 'ISSUES',
    readyToMerge: 'with_fixes',
    findings: [{
      severity: 'important', summary: '境界値が未検証', location: 'a.ts:1',
      fix: null, planMandated: null,
    }],
    triage: [],
    strengths: '',
    reasoning: 'ng',
    round: 0,
    head: 'head0000',
    packageBase: 'mb00000',
    packageHead: 'head0000',
  },
}
for (const [file, argsValue, overrides] of [
  ['sdd-task.js', JSON.stringify(taskArgs), {}],
  ['sdd-final-review.js', JSON.stringify(finalArgs), blockingReview],
]) {
  try {
    const { calls } = await runScript(path.join(HERE, file), argsValue, overrides)
    const prompts = calls.map((c) => c.prompt).join('\n')
    check(`${file}: 共有 scripts パスで review-package を叩く`, prompts.includes(`${SHARED_SCRIPTS}/review-package`))
    check(`${file}: 旧 scripts パスが残っていない`, !prompts.includes(OLD_SCRIPTS))
  } catch (e) {
    failures++
    console.log(`  FAIL  ${file} 実行中に例外: ${e.message}`)
  }
}

console.log('\n[scriptsDir を渡せば上書きできる]')
try {
  const { calls } = await runScript(
    path.join(HERE, 'sdd-task.js'),
    JSON.stringify({ ...taskArgs, scriptsDir: '/custom/scripts' })
  )
  const prompts = calls.map((c) => c.prompt).join('\n')
  check('渡した scriptsDir が使われる', prompts.includes('/custom/scripts/review-package'))
  check('既定値が混ざらない', !prompts.includes(SHARED_SCRIPTS))
} catch (e) {
  failures++
  console.log(`  FAIL  実行中に例外: ${e.message}`)
}

console.log('\n[必須 args の欠落はエージェントを起動する前に弾く]')
for (const [file, argsValue] of [
  ['sdd-task.js', JSON.stringify({ taskNumber: 1 })],
  ['sdd-final-review.js', JSON.stringify({ plan: 'x.md' })],
]) {
  try {
    const { result, calls } = await runScript(path.join(HERE, file), argsValue)
    check(`${file}: エージェントを起動しない`, calls.length === 0, `${calls.length} 件起動した`)
    check(`${file}: status が BAD_ARGS`, result?.status === 'BAD_ARGS', `status=${result?.status}`)
  } catch (e) {
    failures++
    console.log(`  FAIL  ${file} 実行中に例外: ${e.message}`)
  }
}

console.log('\n[args が壊れた JSON でも落ちない]')
try {
  const { result, calls } = await runScript(path.join(HERE, 'sdd-task.js'), '{"plan": ')
  check('エージェントを起動しない', calls.length === 0, `${calls.length} 件起動した`)
  check('status が BAD_ARGS', result?.status === 'BAD_ARGS', `status=${result?.status}`)
} catch (e) {
  failures++
  console.log(`  FAIL  実行中に例外: ${e.message}`)
}

console.log(`\n=== ${failures === 0 ? 'ALL PASS' : failures + ' FAILURES'} ===`)
process.exit(failures === 0 ? 0 : 1)
