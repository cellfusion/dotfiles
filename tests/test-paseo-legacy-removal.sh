#!/usr/bin/env bash
# 旧 agent 設定資産の削除境界と置換先を manifest に固定する。
set -u
. "$(dirname "$0")/lib/assert.sh"

FIXTURES="${PASEO_LEGACY_FIXTURES:-$CHEZMOI_SOURCE/tests/fixtures/agent-config}"
LEGACY="$FIXTURES/legacy"
MANIFEST="${1:-$CHEZMOI_SOURCE/private_dot_config/docs/paseo-agent-config-removal-manifest.md}"
MANIFEST_ONLY=0
if [ "${1:-}" = "--manifest-only" ]; then
  MANIFEST_ONLY=1
  MANIFEST="${2:-}"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
manifest_text=""
delete_rows=""
keep_rows=""
fixtures_ready=1
for fixture in required-delete-leaves.txt required-delete-paths.txt \
    required-keep-paths.txt retained-roles.txt chezmoiremove-required-paths.txt \
    absence-patterns.txt; do
  fixture_path="$LEGACY/$fixture"
  fixture_status="$(test -f "$fixture_path" && test ! -L "$fixture_path" &&
    test -r "$fixture_path" && echo yes || echo no)"
  assert_eq "$fixture_status" "yes" "fixtures: $fixture が regular file"
  [ "$fixture_status" = yes ] || fixtures_ready=0
done

assert_eq "$(test -n "$MANIFEST" && test -f "$MANIFEST" && echo yes || echo no)" "yes" \
  "manifest: 指定された manifest が通常ファイルである"

if [ -f "$MANIFEST" ]; then
  manifest_text="$(cat "$MANIFEST")"
  malformed="$(awk '
    /^[[:space:]]*$/ { next }
    /^#[[:space:]]+/ { next }
    /^[|] [^|]+ [|] (Delete|Keep) [|] [^|]+ [|]$/ { next }
    /^[|][[:space:]]*source path[[:space:]]*[|][[:space:]]*(action|disposition)[[:space:]]*[|][[:space:]]*(replacement|replacement or reason)[[:space:]]*[|][[:space:]]*$/ { next }
    /^[|][[:space:]]*[-:]+[[:space:]]*[|][[:space:]]*[-:]+[[:space:]]*[|][[:space:]]*[-:]+[[:space:]]*[|][[:space:]]*$/ { next }
    { print NR ":" $0 }
  ' "$MANIFEST")"
  assert_eq "$malformed" "" "manifest: 3 列の行だけを持つ"
  for wildcard in '*' '?' '[' ']'; do
    assert_not_contains "$manifest_text" "$wildcard" "manifest: wildcard $wildcard を使わない"
  done
  assert_not_contains "$manifest_text" '.paseo' "manifest: runtime の root を削除しない"

  delete_rows="$(grep '| Delete |' "$MANIFEST" || true)"
  keep_rows="$(grep '| Keep |' "$MANIFEST" || true)"
  assert_eq "$(printf '%s\n' "$delete_rows" | grep -c .)" "102" "manifest: Delete 行は 102 件"
  assert_eq "$(printf '%s\n' "$keep_rows" | grep -c .)" "61" "manifest: Keep 行は 61 件"

fi

if [ "$fixtures_ready" -eq 1 ]; then
while read -r leaf; do
  [ -n "$leaf" ] || continue
  assert_contains "$delete_rows" "$leaf" "manifest: $leaf を Delete にする"
done < "$LEGACY/required-delete-leaves.txt"
while read -r source_path; do
  [ -n "$source_path" ] || continue
  assert_contains "$delete_rows" "| $source_path | Delete |" "manifest: $source_path を Delete にする"
done < "$LEGACY/required-delete-paths.txt"
while read -r keep_path; do
  [ -n "$keep_path" ] || continue
  assert_contains "$keep_rows" "| $keep_path | Keep |" "manifest: $keep_path を Keep にする"
done < "$LEGACY/required-keep-paths.txt"
while read -r role; do
  [ -n "$role" ] || continue
  assert_not_contains "$delete_rows" ".chezmoitemplates/agent-defs/prompts/$role.md " \
    "manifest: $role の prompt を削除しない"
done < "$LEGACY/retained-roles.txt"

# Delete 行の置換先は、現行の検証 test のいずれかに限定する。
while IFS='|' read -r _ _ disposition replacement _; do
  disposition="$(printf '%s' "$disposition" | sed 's/^ *//; s/ *$//')"
  replacement="$(printf '%s' "$replacement" | sed 's/^ *//; s/ *$//')"
  [ "$disposition" = Delete ] || continue
  case "$replacement" in
    tests/test-paseo-mad.sh|tests/test-manual-orchestration-contract.sh|tests/test-generate-paseo-config.sh|tests/test-distribution.sh|tests/test-paseo-legacy-removal.sh|tests/test-schemas.sh)
      assert_eq "$(test -f "$CHEZMOI_SOURCE/$replacement" && echo yes || echo no)" "yes" \
        "manifest: Delete の置換 test が実在する"
      ;;
    *) assert_eq "$replacement" "tests/test-paseo-mad.sh" "manifest: Delete の置換 test が許可一覧にある" ;;
  esac
done <<EOF
$delete_rows
EOF

if [ "${PASEO_LEGACY_SELF_TEST:-0}" -eq 0 ] && [ -f "$MANIFEST" ]; then
  extra_keep_manifest="$TMP/extra-keep.md"
  cp "$MANIFEST" "$extra_keep_manifest"
  printf '%s\n' '| private_dot_agents/skills/multi-agent-development/SKILL.md.tmpl | Keep | extra row |' \
    >> "$extra_keep_manifest"
  extra_keep_output="$(PASEO_LEGACY_SELF_TEST=1 bash "$0" --manifest-only "$extra_keep_manifest" 2>&1)"
  extra_keep_status=$?
  assert_eq "$extra_keep_status" "1" "manifest: 余分な Keep 行を拒否する"
  assert_contains "$extra_keep_output" "Keep 行は 61 件" \
    "manifest: Keep 件数の失敗理由を示す"

  malformed_manifest="$TMP/malformed.md"
  cp "$MANIFEST" "$malformed_manifest"
  printf '%s\n' 'arbitrary non-row text' >> "$malformed_manifest"
  malformed_output="$(PASEO_LEGACY_SELF_TEST=1 bash "$0" --manifest-only "$malformed_manifest" 2>&1)"
  malformed_status=$?
  assert_eq "$malformed_status" "1" "manifest: 非行の非空テキストを拒否する"
  assert_contains "$malformed_output" "3 列の行だけを持つ" \
    "manifest: 非行の失敗理由を示す"

  fixture_copy="$TMP/fixture-copy"
  mkdir -p "$fixture_copy/legacy"
  for fixture in required-delete-leaves.txt required-delete-paths.txt \
      required-keep-paths.txt retained-roles.txt chezmoiremove-required-paths.txt \
      absence-patterns.txt; do
    cp "$LEGACY/$fixture" "$fixture_copy/legacy/$fixture"
  done
  rm "$fixture_copy/legacy/required-keep-paths.txt"
  fixture_output="$(PASEO_LEGACY_SELF_TEST=1 PASEO_LEGACY_FIXTURES="$fixture_copy" \
    bash "$0" --manifest-only "$MANIFEST" 2>&1)"
  fixture_status=$?
  assert_eq "$fixture_status" "1" "fixtures: 欠落した必須 fixture を拒否する"
  assert_contains "$fixture_output" "regular file" \
    "fixtures: 欠落 fixture の失敗理由を示す"
fi
fi

if [ "$MANIFEST_ONLY" -eq 0 ] && [ "$fixtures_ready" -eq 1 ]; then
  managed="$(chezmoi managed --source "$CHEZMOI_SOURCE" --include=files,symlinks)"
  while read -r leaf; do
    [ -n "$leaf" ] || continue
    assert_not_contains "$managed" "${leaf#executable_}" "distribution: ${leaf#executable_} を配らない"
  done < "$LEGACY/required-delete-leaves.txt"
  for kept in "multi-agent-development/scripts/paseo-mcp-adapter" \
    "multi-agent-development/scripts/paseo-plan-dependency-validate" \
    "agent-defs/prompts/task-reviewer.md" "agent-defs/schemas/final-reviewer.json" \
    ".local/share/agent-config/mad-contract.js"; do
    assert_contains "$managed" "$kept" "distribution: $kept を配る"
  done

  EXCLUDES=(':!tests/fixtures/agent-config'
    ':!private_dot_config/docs/paseo-agent-config-removal-manifest.md'
    ':!.chezmoiremove'
    ':!tests/test-paseo-legacy-removal.sh')
  legacy_pattern="$(tr '\n' '|' < "$LEGACY/absence-patterns.txt" | sed 's/|$//')"
  matches="$(cd "$CHEZMOI_SOURCE" && git grep -nEi "$legacy_pattern" -- "${EXCLUDES[@]}" || true)"
  assert_eq "$matches" "" "source: native と direct と SDD の参照が残らない"

  FAST_EXCLUDES=("${EXCLUDES[@]}"
    ':!private_dot_local/private_share/agent-config/resolver.js'
    ':!tests/test-generate-paseo-config.sh'
    ':!private_dot_config/docs/tools.md')
  fast_matches="$(cd "$CHEZMOI_SOURCE" && git grep -nE '\bfast\b' -- "${FAST_EXCLUDES[@]}" || true)"
  assert_eq "$fast_matches" "" "source: fast は互換入力のコードと test と docs にしか残らない"

  present=""
  while IFS='|' read -r _ source_path _ _; do
    path_value="$(printf '%s' "$source_path" | sed 's/^ *//; s/ *$//')"
    [ -n "$path_value" ] || continue
    test ! -e "$CHEZMOI_SOURCE/$path_value" || present="$present$path_value "
  done <<EOF
$delete_rows
EOF
  assert_eq "$present" "" "removal: Delete 行の source path がすべて不在である"

  removed="$(cat "$CHEZMOI_SOURCE/.chezmoiremove")"
  while read -r destination; do
    [ -n "$destination" ] || continue
    assert_contains "$removed" "$destination" "chezmoiremove: $destination を回収する"
  done < "$LEGACY/chezmoiremove-required-paths.txt"
  assert_not_contains "$removed" '.paseo' "chezmoiremove: Paseo の root を入れない"

  plan_validate="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-plan-dependency-validate"
  node "$plan_validate" "/Users/cellfusion/docs/cellfusion/dotfiles/plans/2026-09-12-paseo-agent-config.md"
  assert_eq "$?" "0" "plan validator: 削除後もこの plan を検証できる"
  assert_contains "$(cat "$CHEZMOI_SOURCE/tests/manual/mad-orchestration-smoke.sh")" \
    'generate-paseo-config resolve' "smoke: exporter の launch を使う"
  assert_contains "$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/_workflow-table.md")" \
    'multi-agent-development' "workflow table: MAD を指す"
  hook_source="$(cat "$CHEZMOI_SOURCE/private_dot_config/claude/hooks/executable_dev-workflow-inject.sh")"
  assert_eq "$(printf '%s' "$hook_source" | grep -cEi "$legacy_pattern" || true)" "0" "hook: 旧 skill を指さない"
fi

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
