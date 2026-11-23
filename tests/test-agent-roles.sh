#!/usr/bin/env bash
# Check shared and Claude role definitions without applying dotfiles.
set -u
. "$(dirname "$0")/lib/assert.sh"

render() {
  chezmoi cat --source "$CHEZMOI_SOURCE" "$HOME/$1"
}

for role in implement debug review security-review plan-auditor research question ui; do
  if shared="$(render ".agents/skills/role-$role/SKILL.md")" &&
     claude="$(render ".config/claude/skills/role-$role/SKILL.md")"; then
    assert_eq "$shared" "$claude" "$role: shared and Claude skills render identically"
    assert_contains "$shared" "name: role-$role" "$role: skill name matches its directory"
    assert_not_contains "$shared" 'hc send' "$role: portable skill has no hc reply command"
    assert_not_contains "$shared" 'command:' "$role: portable skill has no startup command"
  else
    fail_check "$role: render shared and Claude role skills"
  fi
done

assert_summary
