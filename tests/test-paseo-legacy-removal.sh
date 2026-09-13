#!/usr/bin/env bash
# 旧 agent 設定資産の削除境界と置換先を manifest に固定する。
set -u
. "$(dirname "$0")/lib/assert.sh"

FIXTURES="${PASEO_LEGACY_FIXTURES:-$CHEZMOI_SOURCE/tests/fixtures/agent-config}"
LEGACY="$FIXTURES/legacy"
MANIFEST="${1:-$CHEZMOI_SOURCE/private_dot_config/docs/paseo-agent-config-removal-manifest.md}"
if [ "${1:-}" = "--manifest-only" ]; then
  MANIFEST="${2:-}"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
manifest_text=""
delete_rows=""
keep_rows=""
fixtures_ready=1
for fixture in required-delete-leaves.txt required-delete-paths.txt \
    required-keep-paths.txt retained-roles.txt chezmoiremove-required-paths.txt; do
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

  for rows in delete keep; do
    case "$rows" in delete) selected="$delete_rows" ;; keep) selected="$keep_rows" ;; esac
    missing_leaf=""
    while IFS='|' read -r _ source_path _ _; do
      path_value="$(printf '%s' "$source_path" | sed 's/^ *//; s/ *$//')"
      [ -n "$path_value" ] || continue
      if [ ! -f "$CHEZMOI_SOURCE/$path_value" ]; then
        missing_leaf="$missing_leaf$path_value "
      fi
    done <<EOF
$selected
EOF
    assert_eq "$missing_leaf" "" "manifest: $rows 行の source path がすべて実在する leaf"
  done

  missing=""
  while IFS='|' read -r _ source_path _ _; do
    path_value="$(printf '%s' "$source_path" | sed 's/^ *//; s/ *$//')"
    [ -n "$path_value" ] || continue
    test -e "$CHEZMOI_SOURCE/$path_value" || missing="$missing$path_value "
  done <<EOF
$delete_rows
EOF
  assert_eq "$missing" "" "manifest: Delete 行の source path がすべて実在する"
fi

if [ "$fixtures_ready" -eq 1 ]; then
while read -r leaf; do
  [ -n "$leaf" ] || continue
  assert_contains "$delete_rows" "$leaf" "manifest: $leaf を Delete にする"
done < "$LEGACY/required-delete-leaves.txt"
while read -r source_path; do
  [ -n "$source_path" ] || continue
  assert_contains "$delete_rows" "| $source_path | Delete |" "manifest: $source_path を Delete にする"
  assert_eq "$(test -e "$CHEZMOI_SOURCE/$source_path" && echo yes || echo no)" "yes" \
    "manifest: $source_path は現在の作業ツリーに実在する"
done < "$LEGACY/required-delete-paths.txt"
while read -r keep_path; do
  [ -n "$keep_path" ] || continue
  assert_contains "$keep_rows" "| $keep_path | Keep |" "manifest: $keep_path を Keep にする"
  assert_eq "$(test -e "$CHEZMOI_SOURCE/$keep_path" && echo yes || echo no)" "yes" \
    "manifest: $keep_path は現在の作業ツリーに実在する"
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
      required-keep-paths.txt retained-roles.txt chezmoiremove-required-paths.txt; do
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

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
