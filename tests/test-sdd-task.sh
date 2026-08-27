#!/usr/bin/env bash
# fake の backend と fake の git を挟み、ループの規律（上限・昇格・commit 前検査）を検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

SCRIPTS="$CHEZMOI_SOURCE/private_dot_agents/skills/subagent-driven-development/scripts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/wt" "$TMP/status"

# fake の backend。シナリオを環境変数で与え、呼び出しを記録する。
cat > "$TMP/fake-backend.js" <<'FAKE'
'use strict'
const fs = require('node:fs')
class BackendError extends Error {}
const LOG = process.env.FAKE_LOG
const S = JSON.parse(process.env.SCENARIO || '{}')
let calls = 0
const log = (l) => fs.appendFileSync(LOG, l + '\n')

module.exports = {
  BackendError,
  async runRole(opts) {
    calls += 1
    log(`runRole ${opts.backend} ${opts.role} round=${opts.round} tools=${opts.tools} pm=${opts.permissionMode}`)
    if (process.env.FAKE_PROMPTS) fs.appendFileSync(process.env.FAKE_PROMPTS, opts.prompt + '\n')
    if (opts.onSpawn) opts.onSpawn({ pid: process.pid, pgid: process.pid, command: 'fake' })
    if ((S.backendFail || []).includes(calls)) {
      return { ok: false, payload: null, error: 'fake backend failure', backend: opts.backend,
        exitCode: 1, signal: null, permissionDenials: [], engineSessionId: null }
    }
    const ok = (payload) => ({ ok: true, payload, error: null, backend: opts.backend,
      exitCode: 0, signal: null, permissionDenials: [], engineSessionId: 'SID' })
    if (opts.role.startsWith('sdd-implementer')) {
      const p = {
        status: (S.implStatus || {})[String(opts.round)] || 'DONE',
        round: S.wrongRound ? opts.round + 1 : opts.round,
        baseHead: S.badBaseHead ? 'WRONG' : opts.expectedHead,
        changedFiles: S.changedFiles || ['a.txt'],
        proposedCommitMessage: S.commitMessage || 'feat: add a',
        testSummary: 'ok', concerns: 'fake concern', detail: 'fake detail',
      }
      return ok(p)
    }
    if (opts.role === 'sdd-task-reviewer') {
      const f = S.findings || []
      return ok({
        specVerdict: S.specVerdict || (f.length ? 'issues' : 'compliant'),
        qualityVerdict: S.qualityVerdict || (f.length ? 'needs_fixes' : 'approved'),
        findings: f, cannotVerify: [], round: opts.round, head: opts.expectedHead,
        packageBase: S.packageBase || opts.packageBase, packageHead: opts.packageHead,
      })
    }
    const all = (S.findings || []).map((x) => ({ finding: S.rephraseAs || x.summary, addressed: false }))
    return ok({
      verdicts: S.verdictCount === undefined ? all : all.slice(0, S.verdictCount),
      newBreakage: [], outOfScope: [], round: opts.round, head: opts.expectedHead,
      packageBase: opts.packageBase, packageHead: opts.packageHead,
    })
  },
}
FAKE

# fake の registry。呼び出しを記録するだけ。
cat > "$TMP/fake-registry.js" <<'FAKE'
'use strict'
const fs = require('node:fs')
module.exports = {
  updateTask: (runPath, n, patch) =>
    fs.appendFileSync(process.env.FAKE_LOG, `updateTask ${n} ${patch.state || ''} ${JSON.stringify(patch)}\n`),
}
FAKE

# fake の git。HEAD を偽装し、呼び出しを記録する。
cat > "$TMP/bin/git" <<'FAKE'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$FAKE_LOG"
case "$*" in
  *"rev-parse HEAD"*) printf '%s\n' "$(cat "$FAKE_HEAD_FILE")" ;;
  *"diff --cached --name-only"*) printf '%s' "${FAKE_STAGED:-}" ;;
  *"status --porcelain --untracked-files=all"*) printf '%s' "${FAKE_PORCELAIN_ALL:-${FAKE_PORCELAIN:- M a.txt}}" ;;
  *commit*) n=$(( $(cat "$FAKE_HEAD_FILE" | tr -dc 0-9 | head -c 3) + 1 )); printf 'head%s\n' "$n" > "$FAKE_HEAD_FILE" ;;
  *) : ;;
esac
exit 0
FAKE
chmod +x "$TMP/bin/git"

# fake の review-package。出力先にダミーを書く。
cat > "$TMP/bin/review-package" <<'FAKE'
#!/usr/bin/env bash
printf 'review-package %s\n' "$*" >> "$FAKE_LOG"
printf '# Review package\n' > "$4"
FAKE
chmod +x "$TMP/bin/review-package"

export FAKE_LOG="$TMP/calls.log"
export FAKE_PROMPTS="$TMP/prompts.txt"
export FAKE_HEAD_FILE="$TMP/head.txt"
export PATH="$TMP/bin:$PATH"

run_task() {
  : > "$FAKE_LOG"
  : > "$FAKE_PROMPTS"
  printf 'head0\n' > "$FAKE_HEAD_FILE"
  SDD_BACKEND_MODULE="$TMP/fake-backend.js" \
  SDD_REGISTRY_MODULE="$TMP/fake-registry.js" \
  SDD_REVIEW_PACKAGE_BIN="$TMP/bin/review-package" \
    node "$SCRIPTS/executable_sdd-task" \
      --plan /tmp/plan.md --task 3 \
      --brief /tmp/brief.md --report /tmp/report.md \
      --status-dir "$TMP/status" --base head0 --workdir "$TMP/wt" \
      --run "$TMP/status/run.json" --global-constraints "なし"
}

# 指摘なしなら 1 ラウンドも回さずに COMPLETE。
out="$(SCENARIO='{}' run_task)"
assert_contains "$out" '"status": "COMPLETE"' "指摘なしで COMPLETE"
assert_contains "$out" '"rounds": 0' "指摘なしなら fix ラウンドは 0"

# backend は役割ごとに変わる。codex implementer、claude reviewer。
log="$(cat "$FAKE_LOG")"
assert_contains "$log" "runRole codex-headless sdd-implementer round=0" "implementer は codex headless"
assert_contains "$log" "runRole claude-headless sdd-task-reviewer round=0" "reviewer は claude headless"
assert_not_contains "$log" "herdr" "herdr の agent 経路を使わない"
assert_contains "$log" "sdd-implementer round=0 tools=undefined pm=auto" "write 役は auto mode で走らせる"
assert_contains "$log" "sdd-task-reviewer round=0 tools=Read,Grep,Glob pm=auto" "read 役は tools を絞ったうえで auto mode で走らせる"

# commit は controller が行う。agent には git を触らせない。
assert_contains "$log" "git -C $TMP/wt add -- a.txt" "変更ファイルだけを stage する"
assert_not_contains "$log" "add -A" "git add -A を使わない"
assert_contains "$log" "commit -m feat: add a" "提案された message で commit する"
assert_contains "$log" "review-package /tmp/plan.md head0" "controller が review package を作る"

# registry に state を記録する。
assert_contains "$log" "updateTask 3 RUNNING" "実行中を registry に記録する"
assert_contains "$log" "updateTask 3 SUCCEEDED" "完了を registry に記録する"
assert_contains "$log" '"pid":' "spawn 直後の pid を registry に記録する"
assert_contains "$log" '"command":"fake"' "spawn 直後の command を registry に記録する"

# Minor だけならループに入れずに COMPLETE。
out="$(SCENARIO='{"findings":[{"severity":"minor","summary":"m1","location":"a.js:1"}]}' run_task)"
assert_contains "$out" '"status": "COMPLETE"' "Minor だけなら COMPLETE"
assert_contains "$out" '"rounds": 0' "Minor はループに入れない"

# Critical が直らないと 5 ラウンドで打ち切り、ラウンド 4 で昇格する。
out="$(SCENARIO='{"findings":[{"severity":"critical","summary":"c1","location":"a.js:1"}]}' run_task)"
assert_contains "$out" '"status": "CAP_REACHED"' "直らない指摘は上限で打ち切る"
assert_contains "$out" '"rounds": 5' "上限は 5 ラウンド"
log="$(cat "$FAKE_LOG")"
assert_contains "$log" "runRole claude-headless sdd-implementer-think round=4" "ラウンド 4 は claude headless に昇格する"
assert_contains "$log" "runRole claude-headless sdd-re-reviewer round=1" "fix の再レビューは re-reviewer"

# re-reviewer が元の summary とは違う文言で NOT ADDRESSED を返しても、文字列一致で
# 落ちずに 5 ラウンド回り、open には言い換え後の文言が載る。
out="$(SCENARIO='{"findings":[{"severity":"critical","summary":"c1","location":"a.js:1"}],"rephraseAs":"言い換えられた未解決の指摘"}' run_task)"
assert_contains "$out" '"status": "CAP_REACHED"' "言い換えられても上限で打ち切る"
assert_contains "$out" "言い換えられた未解決の指摘" "open に言い換え後の文言が載る"
assert_not_contains "$out" '"summary": "c1"' "元の summary のままでは残らない"

# plan-mandated は人に返す。
out="$(SCENARIO='{"findings":[{"severity":"critical","summary":"p1","location":"a.js:1","planMandated":true}]}' run_task)"
assert_contains "$out" '"status": "NEEDS_HUMAN"' "plan-mandated は人に返す"

# implementer の BLOCKED / NEEDS_CONTEXT はそのまま返す。commit しない。
out="$(SCENARIO='{"implStatus":{"0":"BLOCKED"}}' run_task)"
assert_contains "$out" '"status": "BLOCKED"' "BLOCKED を返す"
assert_not_contains "$(cat "$FAKE_LOG")" "commit -m" "BLOCKED では commit しない"

out="$(SCENARIO='{"implStatus":{"0":"NEEDS_CONTEXT"}}' run_task)"
assert_contains "$out" '"status": "NEEDS_CONTEXT"' "NEEDS_CONTEXT を返す"

# DONE_WITH_CONCERNS は commit したうえで concern を返す。
out="$(SCENARIO='{"implStatus":{"0":"DONE_WITH_CONCERNS"}}' run_task)"
assert_contains "$out" '"concerns": "fake concern"' "concern を結果に載せる"
assert_contains "$(cat "$FAKE_LOG")" "commit -m" "DONE_WITH_CONCERNS でも commit する"

# commit 前検査: baseHead が違えば止める。
out="$(SCENARIO='{"badBaseHead":true}' run_task)"
assert_contains "$out" '"status": "AGENT_FAILED"' "baseHead 違いで止まる"
assert_contains "$out" '"stage": "precommit"' "止まった段を stage で示す"
assert_not_contains "$(cat "$FAKE_LOG")" "commit -m" "検査に落ちたら commit しない"

# commit 前検査: implementer の round が違えば止める。
out="$(SCENARIO='{"wrongRound":true}' run_task)"
assert_contains "$out" '"stage": "precommit"' "round 違いで precommit に止める"
assert_contains "$out" 'round が違う' "round 違いの理由を返す"

# 未追跡ディレクトリは個別ファイルまで展開されれば precommit を通る。
out="$(FAKE_PORCELAIN_ALL=$'?? newdir/a.js\n?? newdir/b.js' SCENARIO='{"changedFiles":["newdir/a.js","newdir/b.js"]}' run_task)"
assert_contains "$out" '"status": "COMPLETE"' "未追跡ディレクトリの個別ファイルを通す"
assert_contains "$(cat "$FAKE_LOG")" "status --porcelain --untracked-files=all" "未追跡ファイルを全件取得する"

# commit 前検査: index が空でなければ止める。
out="$(FAKE_STAGED="x.txt" SCENARIO='{}' run_task)"
assert_contains "$out" '"stage": "precommit"' "index が空でなければ止まる"

# commit 前検査: changedFiles に無い変更があれば止める。
out="$(FAKE_PORCELAIN=" M b.txt" SCENARIO='{}' run_task)"
assert_contains "$out" '"stage": "precommit"' "報告に無い変更があれば止まる"

# commit 前検査: commit message が Conventional Commits でなければ止める。
out="$(SCENARIO='{"commitMessage":"変更した"}' run_task)"
assert_contains "$out" '"stage": "precommit"' "commit message の形式違いで止まる"

# backend が失敗したら AGENT_FAILED。
out="$(SCENARIO='{"backendFail":[1]}' run_task)"
assert_contains "$out" '"status": "AGENT_FAILED"' "backend の失敗は AGENT_FAILED"
assert_contains "$out" '"stage": "backend"' "止まった段を stage で示す"

# verdict の矛盾で止める。
out="$(SCENARIO='{"specVerdict":"issues"}' run_task)"
assert_contains "$out" '"stage": "review-verdict"' "verdict の矛盾で止まる"

# re-reviewer が判定を落としたら止める。
out="$(SCENARIO='{"findings":[{"severity":"critical","summary":"c1","location":"a.js:1"},{"severity":"critical","summary":"c2","location":"b.js:2"}],"verdictCount":1}' run_task)"
assert_contains "$out" '"stage": "review-verdict"' "verdict の件数不足で止まる"

# レビュアーが違う範囲を見ていたら止める。
out="$(SCENARIO='{"packageBase":"deadbee"}' run_task)"
assert_contains "$out" '"stage": "review-range"' "package の範囲違いで止まる"

# 引数が足りなければエージェントを起動する前に BAD_ARGS で返る。
out="$(node "$SCRIPTS/executable_sdd-task" --plan /tmp/p.md 2>&1 || true)"
assert_contains "$out" '"status": "BAD_ARGS"' "引数不足は BAD_ARGS"

# 出力は改行を含まない 1 行。
out="$(SCENARIO='{}' run_task)"
assert_eq "$(printf '%s' "$out" | wc -l | tr -d ' ')" "0" "出力は改行を含まない 1 行"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
