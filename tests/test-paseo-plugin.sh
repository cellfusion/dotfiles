#!/usr/bin/env bash
# Paseo プラグイン pr-review のソース構成を検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

plugin_dir="$CHEZMOI_SOURCE/private_dot_local/private_share/paseo-plugins/pr-review"

for name in paseo-plugin.json package.json tsconfig.json contracts.ts; do
  assert_eq "$([ -f "$plugin_dir/$name" ] && echo yes || echo no)" "yes" \
    "paseo-plugin: $name がある"
done

manifest="$(cat "$plugin_dir/paseo-plugin.json" 2>/dev/null || echo '{}')"
assert_eq "$(printf '%s' "$manifest" | jq -r '.id // "none"')" "pr-review" \
  "paseo-plugin: manifest の id が pr-review である"

pkg="$(cat "$plugin_dir/package.json" 2>/dev/null || echo '{}')"
assert_eq "$(printf '%s' "$pkg" | jq -r '.scripts.typecheck // "none"')" "tsc --noEmit" \
  "paseo-plugin: typecheck スクリプトがある"
assert_eq "$(printf '%s' "$pkg" | jq -r '.devDependencies["@getpaseo/plugin"] // "none"')" "0.7.2" \
  "paseo-plugin: プラグイン SDK のバージョンを固定する"

contracts="$(cat "$plugin_dir/contracts.ts" 2>/dev/null || true)"
assert_contains "$contracts" "listPullRequests" "paseo-plugin: PR 一覧の RPC 契約がある"
assert_contains "$contracts" "preparePullRequest" "paseo-plugin: 起動準備の RPC 契約がある"
assert_contains "$contracts" "instructionsChanged" "paseo-plugin: 指示ファイルの変更有無を返す"

gitignore="$(cat "$CHEZMOI_SOURCE/.gitignore" 2>/dev/null || true)"
assert_contains "$gitignore" "paseo-plugins/pr-review/node_modules" \
  "paseo-plugin: node_modules を git 追跡から外す"

for name in commands.ts index.ts instructions.ts; do
  assert_eq "$([ -f "$plugin_dir/$name" ] && echo yes || echo no)" "yes" \
    "paseo-plugin: $name がある"
done

commands="$(cat "$plugin_dir/commands.ts" 2>/dev/null || true)"
assert_contains "$commands" "/opt/homebrew/bin" \
  "paseo-plugin: daemon の PATH に Homebrew を足す"
assert_contains "$commands" "execFile" "paseo-plugin: shell を経由せずに実行する"

index="$(cat "$plugin_dir/index.ts" 2>/dev/null || true)"
assert_contains "$index" "plugin.handle(listPullRequests" \
  "paseo-plugin: PR 一覧の RPC を登録する"
assert_contains "$index" "plugin.handle(preparePullRequest" \
  "paseo-plugin: 起動準備の RPC を登録する"
assert_contains "$index" "gh pr diff" "paseo-plugin: gh pr diff で変更パスを取る"
assert_contains "$index" 'from "./instructions"' \
  "paseo-plugin: 指示ファイルの判定を instructions.ts から取る"

instructions="$(cat "$plugin_dir/instructions.ts" 2>/dev/null || true)"
assert_contains "$instructions" "INSTRUCTION_FILE_NAMES" \
  "paseo-plugin: 指示ファイルの名前を named export で持つ"
assert_contains "$instructions" "INSTRUCTION_DIR_NAMES" \
  "paseo-plugin: 指示ディレクトリの名前を named export で持つ"

# 判定そのものを実際に呼んで固定する。node v22 は .ts を型を剥がして直接実行できる。
touches_instructions() {
  node --no-warnings --input-type=module -e "
const { touchesInstructions } = await import('$plugin_dir/instructions.ts');
console.log(touchesInstructions([process.argv[1]]));
" -- "$1" 2>&1
}

# gh pr diff --name-only はリポジトリのルートからの相対パスを返すので、
# 入れ子に置かれた指示ファイルも拾う必要がある。
for path in CLAUDE.md AGENTS.md packages/api/CLAUDE.md docs/AGENTS.md \
            .claude/settings.json apps/web/.agents/skills/foo/SKILL.md; do
  assert_eq "$(touches_instructions "$path")" "true" \
    "paseo-plugin: $path を指示ファイルと判定する"
done

# 名前の一部が一致するだけのパスは指示ファイルではない。
for path in README.md src/claude.ts docs/claude-notes.md; do
  assert_eq "$(touches_instructions "$path")" "false" \
    "paseo-plugin: $path を指示ファイルと判定しない"
done

assert_eq "$([ -f "$plugin_dir/main.client.tsx" ] && echo yes || echo no)" "yes" \
  "paseo-plugin: main.client.tsx がある"

surface="$(cat "$plugin_dir/main.client.tsx" 2>/dev/null || true)"
assert_contains "$surface" "PullRequestSurface" "paseo-plugin: 画面を名前付きで export する"
assert_contains "$surface" "theme.colors" "paseo-plugin: 文字色を theme から取る"
assert_contains "$surface" "layout.compact" "paseo-plugin: 余白を layout から決める"
assert_contains "$surface" "paseo.projects.list" "paseo-plugin: プロジェクト一覧を SDK から取る"
assert_contains "$surface" "paseo.workspaces.create" "paseo-plugin: workspace を SDK で作る"
assert_contains "$surface" "change_request" "paseo-plugin: PR のチェックアウトを指定する"
assert_contains "$surface" "claude/claude-opus-5" "paseo-plugin: provider の既定値を持つ"
assert_contains "$surface" "agentProfiles" "paseo-plugin: agent profile があれば使う"
assert_contains "$surface" 'prompt: `/pr-review ${number}`' \
  "paseo-plugin: prompt を pr-review スキルの引数の契約に合わせる"
# スキルは引数を正の整数 1 個だけと定めている。説明を連結すると引数が一致しない。
assert_not_contains "$surface" 'notice' \
  "paseo-plugin: prompt に説明文を連結しない"
assert_contains "$surface" '"[base] "' \
  "paseo-plugin: base から分岐した workspace の title に印を付ける"
assert_contains "$surface" "startingNumber" \
  "paseo-plugin: 起動中は PR 行を押せないようにする"

assert_contains "$index" "addSurface" "paseo-plugin: surface を登録する"
assert_contains "$index" "addSidebarItem" "paseo-plugin: サイドバー項目を登録する"
assert_contains "$index" "addCommandCenterItem" "paseo-plugin: Command Center 項目を登録する"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
