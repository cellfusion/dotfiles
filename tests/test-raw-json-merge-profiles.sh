#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
SHARE="$ROOT/private_dot_local/private_share/agent-config"

out="$(node -e '
const { mergeManagedPaseo, removeManagedPaseoProfiles } = require(process.argv[1])
const raw = JSON.stringify({
  daemon: { agentProfiles: [
    { id: "agent_profile_managed_a", name: "a" },
    { id: "keep", name: "keep" },
    { id: "agent_profile_managed_b", name: "b" },
  ] },
  agents: { providers: {} },
}, null, 2)
const pruned = removeManagedPaseoProfiles(raw)
const ids = JSON.parse(pruned.raw).daemon.agentProfiles.map((p) => p.id).join(",")
const withoutDaemon = JSON.stringify({ agents: { providers: {} } })
const merged = mergeManagedPaseo(withoutDaemon, { providers: {}, warnings: [] })
const again = removeManagedPaseoProfiles(pruned.raw)
console.log(pruned.changed, ids, merged.changed, again.changed)
' "$SHARE/raw-json-merge.js")"
assert_eq "$out" "true keep false false" "raw-json-merge: managed profile の回収と daemon 無しの merge"

# managed profile が隣り合う入力。連続する 2 件をそれぞれ別の編集にすると
# applyEdits が overlapping JSON edit として ConfigError を投げる。
adjacent="$(node -e '
const { removeManagedPaseoProfiles } = require(process.argv[1])
const raw = JSON.stringify({
  daemon: { agentProfiles: [
    { id: "agent_profile_managed_a", name: "a" },
    { id: "agent_profile_managed_b", name: "b" },
    { id: "keep", name: "keep" },
  ] },
  agents: { providers: {} },
}, null, 2)
const pruned = removeManagedPaseoProfiles(raw)
const parsed = JSON.parse(pruned.raw)
console.log(pruned.changed, parsed.daemon.agentProfiles.map((p) => p.id).join(","))
' "$SHARE/raw-json-merge.js")"
assert_eq "$adjacent" "true keep" "raw-json-merge: 隣り合う managed profile を 1 つの編集で取り除く"

# 先頭も末尾も managed な入力。すべて取り除いても JSON として読める。
all_managed="$(node -e '
const { removeManagedPaseoProfiles } = require(process.argv[1])
const raw = JSON.stringify({
  daemon: { agentProfiles: [
    { id: "agent_profile_managed_a", name: "a" },
    { id: "agent_profile_managed_b", name: "b" },
  ] },
  agents: { providers: {} },
}, null, 2)
const pruned = removeManagedPaseoProfiles(raw)
console.log(pruned.changed, JSON.parse(pruned.raw).daemon.agentProfiles.length)
' "$SHARE/raw-json-merge.js")"
assert_eq "$all_managed" "true 0" "raw-json-merge: すべて managed なら空配列にする"
