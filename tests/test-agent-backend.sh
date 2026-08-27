#!/usr/bin/env bash
# fake の codex を PATH の先頭に置き、agent-backend が正しい引数を組み立て、
# 出力を正規化することを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

SCRIPT="$CHEZMOI_SOURCE/private_dot_agents/skills/subagent-driven-development/scripts/executable_agent-backend"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/cwd"

# fake codex。引数を記録し、--output-last-message の指すファイルに payload を書く。
cat > "$TMP/bin/codex" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
last=""
prev=""
for a in "$@"; do
  [ "$prev" = "--output-last-message" ] && last="$a"
  prev="$a"
done
printf '{"type":"thread.started","thread_id":"TID-1"}\n'
printf '{"type":"turn.completed","usage":{}}\n'
if [ -n "$last" ]; then
  if [ -n "${FAKE_PAYLOAD+x}" ]; then
    printf '%s' "$FAKE_PAYLOAD" > "$last"
  else
    printf '%s' '{"status":"DONE","round":0,"head":"abc"}' > "$last"
  fi
fi
exit "${FAKE_EXIT:-0}"
FAKE
chmod +x "$TMP/bin/codex"

export FAKE_LOG="$TMP/calls.log"
export PATH="$TMP/bin:$PATH"
export SDD_VALIDATOR_MODULE="$CHEZMOI_SOURCE/private_dot_agents/skills/_shared/scripts/executable_json-schema"

SCHEMA='{"type":"object","required":["status","round","head"],"additionalProperties":false,"properties":{"status":{"type":"string","enum":["DONE","BLOCKED"]},"round":{"type":"integer"},"head":{"type":"string"}}}'

run_js() { node -e "const b = require('$SCRIPT'); $1"; }

# 初回の引数。sandbox と approval は毎回明示する。
out="$(run_js "console.log(b.codexArgs({model:'gpt-5.6-luna', effort:'high', schemaPath:'/s.json', lastPath:'/l.json', writableRoots:['/d1','/d2']}).join(' '))")"
assert_contains "$out" "exec --json" "codex: JSONL を出す"
assert_contains "$out" "--output-schema /s.json" "codex: 出力スキーマを渡す"
assert_contains "$out" "--output-last-message /l.json" "codex: 最終出力をファイルに書かせる"
assert_contains "$out" "-m gpt-5.6-luna" "codex: モデルを渡す"
assert_contains "$out" "model_reasoning_effort=high" "codex: effort を渡す"
assert_contains "$out" 'approval_policy="never"' "codex: 承認を切る"
assert_contains "$out" 'sandbox_mode="workspace-write"' "codex: sandbox を明示する"
assert_contains "$out" 'sandbox_workspace_write.writable_roots=["/d1","/d2"]' "codex: 書ける範囲を明示する"
assert_not_contains "$out" "--ask-for-approval" "codex exec は -a を受け付けない"
assert_not_contains "$out" "--add-dir" "codex exec resume に無いフラグを初回でも使わない"

# resume の引数。sandbox は継承に頼らず毎回渡す。
out="$(run_js "console.log(b.codexArgs({model:'m', effort:'high', schemaPath:'/s.json', lastPath:'/l.json', writableRoots:['/d1'], sessionId:'TID-1'}).join(' '))")"
assert_contains "$out" "exec resume TID-1" "codex: session を resume する"
assert_contains "$out" 'sandbox_mode="workspace-write"' "codex resume: sandbox を再指定する"
assert_contains "$out" 'approval_policy="never"' "codex resume: 承認を再指定する"

# 実行して正規化する。
: > "$FAKE_LOG"
out="$(run_js "
  b.runRole({
    backend: 'codex-headless', role: 'sdd-implementer',
    model: 'm', effort: 'high', cwd: '$TMP/cwd', prompt: 'やれ',
    schema: $SCHEMA, writableRoots: ['$TMP'],
    logPath: '$TMP/log.jsonl', lastPath: '$TMP/last.json', timeoutMs: 30000,
  }).then((r) => console.log(JSON.stringify(r)))
")"
assert_contains "$out" '"ok":true' "runRole: 正常終了は ok"
assert_contains "$out" '"engineSessionId":"TID-1"' "runRole: thread_id を拾う"
assert_contains "$out" '"status":"DONE"' "runRole: payload を返す"
assert_contains "$out" '"backend":"codex-headless"' "runRole: backend を返す"
TESTS_RUN=$((TESTS_RUN + 1))
if [ -s "$TMP/log.jsonl" ]; then _pass "runRole: JSONL をログに残す"; else _fail "runRole: JSONL をログに残す" "空だった"; fi
TESTS_RUN=$((TESTS_RUN + 1))
mode="$(stat -f '%Lp' "$TMP/log.jsonl")"
if [ "$mode" = "600" ]; then _pass "runRole: ログは 0600"; else _fail "runRole: ログは 0600" "実際: $mode"; fi

# onSpawn は待つ前に pid を渡す。
out="$(run_js "
  let seen = null
  b.runRole({
    backend: 'codex-headless', role: 'sdd-implementer',
    model: 'm', effort: 'high', cwd: '$TMP/cwd', prompt: 'やれ',
    schema: $SCHEMA, writableRoots: ['$TMP'],
    logPath: '$TMP/log2.jsonl', lastPath: '$TMP/last2.json', timeoutMs: 30000,
    onSpawn: (s) => { seen = s },
  }).then(() => console.log(JSON.stringify({pid: typeof seen.pid, cmd: seen.command.split(' ')[0]})))
")"
assert_contains "$out" '"pid":"number"' "onSpawn: pid を渡す"
assert_contains "$out" '"cmd":"codex"' "onSpawn: command を渡す"

# スキーマに合わない payload は ok=false にする。
out="$(FAKE_PAYLOAD='{"status":"Done","round":0,"head":"abc"}' run_js "
  b.runRole({
    backend: 'codex-headless', role: 'sdd-implementer',
    model: 'm', effort: 'high', cwd: '$TMP/cwd', prompt: 'やれ',
    schema: $SCHEMA, writableRoots: ['$TMP'],
    logPath: '$TMP/log3.jsonl', lastPath: '$TMP/last3.json', timeoutMs: 30000,
  }).then((r) => console.log(JSON.stringify(r)))
")"
assert_contains "$out" '"ok":false' "スキーマ違反は ok=false"
assert_contains "$out" "enum" "違反の内容を error に出す"

# 非ゼロ終了は ok=false にし、exitCode を返す。
out="$(FAKE_EXIT=3 run_js "
  b.runRole({
    backend: 'codex-headless', role: 'sdd-implementer',
    model: 'm', effort: 'high', cwd: '$TMP/cwd', prompt: 'やれ',
    schema: $SCHEMA, writableRoots: ['$TMP'],
    logPath: '$TMP/log4.jsonl', lastPath: '$TMP/last4.json', timeoutMs: 30000,
  }).then((r) => console.log(JSON.stringify(r)))
")"
assert_contains "$out" '"ok":false' "非ゼロ終了は ok=false"
assert_contains "$out" '"exitCode":3' "終了コードを返す"

# fake claude。引数を記録し、-p の応答 JSON を stdout に出す。
cat > "$TMP/bin/claude" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
cat > /dev/null
if [ -n "${FAKE_CLAUDE_OUT+x}" ]; then
  printf '%s\n' "$FAKE_CLAUDE_OUT"
else
  printf '%s\n' '{"session_id":"SID-1","permission_denials":[],"structured_output":{"status":"DONE","round":0,"head":"abc"},"is_error":false}'
fi
exit "${FAKE_EXIT:-0}"
FAKE
chmod +x "$TMP/bin/claude"

# read 役は tools を絞り、safe-mode で customization を切る。
out="$(run_js "console.log(b.claudeArgs({model:'sonnet', effort:'high', schema:{type:'object'}, tools:'Read,Grep,Glob', addDirs:['/d1'], permissionMode:'auto'}).join(' '))")"
assert_contains "$out" "-p" "claude: print モードで走らせる"
assert_contains "$out" "--safe-mode" "claude: CLAUDE.md / skills / hooks を切る"
assert_contains "$out" "--output-format json" "claude: JSON で受け取る"
assert_contains "$out" "--json-schema" "claude: 出力スキーマを渡す"
assert_contains "$out" '{"type":"object"}' "claude: スキーマは JSON 本体で渡す（パスではない）"
assert_contains "$out" "--tools Read,Grep,Glob" "claude: read 役の tools を絞る"
assert_contains "$out" "--add-dir /d1" "claude: 読める範囲を渡す"
assert_not_contains "$out" "dontAsk" "claude: dontAsk を使わない"
assert_contains "$out" "--permission-mode auto" "claude: read 役も auto mode で走らせる"

# claudeArgs は渡されたときだけフラグを足す builder である。既定値を持たせない。
out="$(run_js "console.log(b.claudeArgs({model:'sonnet', effort:'high', schema:{}}).join(' '))")"
assert_not_contains "$out" "--permission-mode" "claude: permissionMode を渡さなければフラグは出ない"

# --setting-sources は空文字を渡すことが目的である。join では値を見られないので、
# argv 配列の該当する 2 要素をそのまま取り出して見る。
PAIR="const i = a.indexOf('--setting-sources'); console.log(JSON.stringify(a.slice(i, i + 2)))"
out="$(run_js "const a = b.claudeArgs({model:'sonnet', effort:'high', schema:{type:'object'}, tools:'Read,Grep,Glob'}); $PAIR")"
assert_eq "$out" '["--setting-sources",""]' "claude: read 役は setting-sources に空文字を渡す"

# write 役も同じ auto mode で走らせる。read 役との違いは --tools の有無だけである。
out="$(run_js "console.log(b.claudeArgs({model:'opus', effort:'high', schema:{}, permissionMode:'auto'}).join(' '))")"
assert_contains "$out" "--permission-mode auto" "claude: write 役は auto mode で走らせる"
out="$(run_js "const a = b.claudeArgs({model:'opus', effort:'high', schema:{}, permissionMode:'auto'}); $PAIR")"
assert_eq "$out" '["--setting-sources",""]' "claude: write 役も setting-sources に空文字を渡す"

# resume は --resume、初回は --session-id。
out="$(run_js "console.log(b.claudeArgs({model:'m', effort:'high', schema:{}, sessionId:'S1'}).join(' '))")"
assert_contains "$out" "--session-id S1" "claude: 初回は session-id を決め打つ"
out="$(run_js "console.log(b.claudeArgs({model:'m', effort:'high', schema:{}, sessionId:'S1', resume:true}).join(' '))")"
assert_contains "$out" "--resume S1" "claude: 継続は resume する"

# 実行して正規化する。structured_output を payload にする。
: > "$FAKE_LOG"
out="$(run_js "
  b.runRole({
    backend: 'claude-headless', role: 'sdd-task-reviewer',
    model: 'sonnet', effort: 'high', cwd: '$TMP/cwd', prompt: 'みろ',
    schema: $SCHEMA, tools: 'Read,Grep,Glob', permissionMode: 'auto', addDirs: ['$TMP'],
    logPath: '$TMP/clog.jsonl', timeoutMs: 30000,
  }).then((r) => console.log(JSON.stringify(r)))
")"
assert_contains "$out" '"ok":true' "claude: 正常終了は ok"
assert_contains "$out" '"engineSessionId":"SID-1"' "claude: session_id を拾う"
assert_contains "$out" '"status":"DONE"' "claude: structured_output を payload にする"
assert_contains "$out" '"backend":"claude-headless"' "claude: backend を返す"

# runRole が組んだ argv を fake claude 側で見る。claudeArgs の単体テストとの間で
# 引数が落ちても気付けるようにする。read 役にも permission-mode は出る。
log="$(cat "$FAKE_LOG")"
assert_contains "$log" "--setting-sources" "runRole: read 役の argv に setting-sources を渡す"
assert_contains "$log" "--permission-mode auto" "runRole: read 役の argv に permission-mode auto を渡す"

# write 役は permissionMode を argv まで運ぶ。
: > "$FAKE_LOG"
out="$(run_js "
  b.runRole({
    backend: 'claude-headless', role: 'sdd-implementer-think',
    model: 'opus', effort: 'high', cwd: '$TMP/cwd', prompt: 'やれ',
    schema: $SCHEMA, permissionMode: 'auto', addDirs: ['$TMP'],
    logPath: '$TMP/cwlog.jsonl', timeoutMs: 30000,
  }).then((r) => console.log(JSON.stringify(r)))
")"
assert_contains "$out" '"ok":true' "claude: write 役も正常終了は ok"
log="$(cat "$FAKE_LOG")"
assert_contains "$log" "--permission-mode auto" "runRole: write 役の argv に permission-mode auto を渡す"
assert_contains "$log" "--setting-sources" "runRole: write 役の argv にも setting-sources を渡す"
assert_not_contains "$log" "--tools" "runRole: write 役の argv に tools を渡さない"

# permission_denials は診断として持ち帰る。
out="$(FAKE_CLAUDE_OUT='{"session_id":"S","permission_denials":[{"tool_name":"Write"}],"structured_output":{"status":"DONE","round":0,"head":"a"},"is_error":false}' run_js "
  b.runRole({
    backend: 'claude-headless', role: 'sdd-task-reviewer',
    model: 'sonnet', effort: 'high', cwd: '$TMP/cwd', prompt: 'みろ',
    schema: $SCHEMA, tools: 'Read,Grep,Glob', logPath: '$TMP/clog2.jsonl', timeoutMs: 30000,
  }).then((r) => console.log(JSON.stringify(r)))
")"
assert_contains "$out" '"permissionDenials":[{"tool_name":"Write"}]' "claude: 拒否ログを持ち帰る"

# structured_output が無い（is_error）ときは ok=false。
out="$(FAKE_CLAUDE_OUT='{"session_id":"S","permission_denials":[],"is_error":true,"result":"Not logged in"}' run_js "
  b.runRole({
    backend: 'claude-headless', role: 'sdd-task-reviewer',
    model: 'sonnet', effort: 'high', cwd: '$TMP/cwd', prompt: 'みろ',
    schema: $SCHEMA, tools: 'Read,Grep,Glob', logPath: '$TMP/clog3.jsonl', timeoutMs: 30000,
  }).then((r) => console.log(JSON.stringify(r)))
")"
assert_contains "$out" '"ok":false' "claude: structured_output が無ければ ok=false"
assert_contains "$out" "Not logged in" "claude: エラー本文を error に出す"

# backend は 2 つだけ。未知の backend は例外にする。
out="$(run_js "b.runRole({backend:'claude-tui'}).catch((e) => console.log(e.message))")"
assert_contains "$out" "未知の backend: claude-tui" "claude-tui は受け付けない"
assert_not_contains "$(cat "$SCRIPT")" "herdr" "agent-backend は herdr を呼ばない"

# validateSchema は _shared に移した。使っているキーワードだけを見る。
V="$CHEZMOI_SOURCE/private_dot_agents/skills/_shared/scripts/executable_json-schema"
vsc='{"type":"object","required":["a","b"],"additionalProperties":false,"properties":{"a":{"type":"string","enum":["x","y"]},"b":{"type":"integer"},"c":{"type":"array","items":{"type":"object","required":["s"],"properties":{"s":{"type":"boolean"}}}}}}'
v() { node -e "const j = require('$V'); console.log(JSON.stringify(j.validateSchema($vsc, $1)))"; }

assert_eq "$(v '{"a":"x","b":1}')" "[]" "validateSchema: 正しい値は通る"
assert_contains "$(v '{"a":"x"}')" "b" "validateSchema: 必須項目の欠落を検出する"
assert_contains "$(v '{"a":"z","b":1}')" "enum" "validateSchema: enum 外の値を検出する"
assert_contains "$(v '{"a":"x","b":"1"}')" "integer" "validateSchema: 型違いを検出する"
assert_contains "$(v '{"a":"x","b":1,"d":true}')" "未知" "validateSchema: 未知の項目を検出する"
assert_contains "$(v '{"a":"x","b":1,"c":[{"s":"false"}]}')" "boolean" "validateSchema: 配列要素の型違いを検出する"
assert_contains "$(v '{"a":"x","b":1,"c":[{}]}')" "s" "validateSchema: nested required を検出する"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
