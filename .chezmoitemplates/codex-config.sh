#!/usr/bin/env bash
# $CODEX_HOME/config.toml（~/.config/codex と ~/.config/codex_secondary）の model、
# automode の承認設定、sandbox 設定だけを chezmoi が保証する。
#
# 全体を管理しない理由: [projects] の trust_level は Codex が対話中に
# 「このディレクトリを信頼するか」と聞くたびに自動追記する。全体を管理すると
# 追記のたびに chezmoi diff が汚れ、apply で巻き戻ってしまう。
# MCP は原則実ファイルを正とするが、不要サーバーのみ除外する。
#
# chezmoi の modify_ スクリプトは現在のファイルを stdin で受け取り、
# 変更後の内容を stdout に出す。ファイルが無い場合は stdin が空になる。
set -eu

MODEL='gpt-5.6-terra'
EFFORT='medium'
APPROVAL_POLICY='on-request'
APPROVALS_REVIEWER='auto_review'
SANDBOX_MODE='workspace-write'
NETWORK_ACCESS='false'

# 最初のセクションヘッダ（[ で始まる行）より前だけを書き換える。
# [mcp_servers.foo] の中に model キーがあっても触らない。
# model と model_reasoning_effort は前方一致が重なるが、`^model[ \t]*=` は
# `model_reasoning_effort =` にマッチしない（model の直後が _ のため）。
awk \
  -v model="$MODEL" \
  -v effort="$EFFORT" \
  -v approval_policy="$APPROVAL_POLICY" \
  -v approvals_reviewer="$APPROVALS_REVIEWER" \
  -v sandbox_mode="$SANDBOX_MODE" \
  -v network_access="$NETWORK_ACCESS" '
BEGIN {
  in_section = 0
  in_sandbox = 0
  skip_mcp = 0
  seen_model = 0
  seen_effort = 0
  seen_approval_policy = 0
  seen_approvals_reviewer = 0
  seen_sandbox_mode = 0
  seen_sandbox_section = 0
  seen_network_access = 0
}

# 除外対象の mcp_servers テーブル（本体とその子テーブル）かどうか。
# `(\.|\])` で終端することで、serena を消しても serena-extra は前方一致で
# 誤爆させない。
function removed_mcp(header) {
  return header ~ /^\[mcp_servers\.(context7|fetch|playwright|serena|unityMCP)(\.|\])/
}

function add_top_level(added) {
  added = 0
  if (!seen_model)              { print "model = \"" model "\"";                         seen_model = 1;              added = 1 }
  if (!seen_effort)             { print "model_reasoning_effort = \"" effort "\"";       seen_effort = 1;             added = 1 }
  if (!seen_approval_policy)    { print "approval_policy = \"" approval_policy "\"";       seen_approval_policy = 1;    added = 1 }
  if (!seen_approvals_reviewer) { print "approvals_reviewer = \"" approvals_reviewer "\""; seen_approvals_reviewer = 1; added = 1 }
  if (!seen_sandbox_mode)       { print "sandbox_mode = \"" sandbox_mode "\"";             seen_sandbox_mode = 1;       added = 1 }
  return added
}

# 最初のセクションに入る直前で、まだ書いていないキーを補う。
/^\[/ {
  if (in_sandbox && !seen_network_access) {
    print "network_access = " network_access
    seen_network_access = 1
  }
  if (!in_section) {
    if (add_top_level()) print ""
    in_section = 1
  }
  in_sandbox = ($0 == "[sandbox_workspace_write]")
  if (in_sandbox) {
    seen_sandbox_section = 1
    seen_network_access = 0
  }
  skip_mcp = removed_mcp($0)
  if (skip_mcp) next
  print
  next
}

# 除外対象セクションの中身（子テーブル含む）を、次の対象外セクションまで捨てる。
skip_mcp { next }

!in_section && /^model[ \t]*=/ {
  print "model = \"" model "\""
  seen_model = 1
  next
}

!in_section && /^model_reasoning_effort[ \t]*=/ {
  print "model_reasoning_effort = \"" effort "\""
  seen_effort = 1
  next
}

!in_section && /^approval_policy[ \t]*=/ {
  print "approval_policy = \"" approval_policy "\""
  seen_approval_policy = 1
  next
}

!in_section && /^approvals_reviewer[ \t]*=/ {
  print "approvals_reviewer = \"" approvals_reviewer "\""
  seen_approvals_reviewer = 1
  next
}

!in_section && /^sandbox_mode[ \t]*=/ {
  print "sandbox_mode = \"" sandbox_mode "\""
  seen_sandbox_mode = 1
  next
}

in_sandbox && /^network_access[ \t]*=/ {
  print "network_access = " network_access
  seen_network_access = 1
  next
}

{ print }

# セクションが無い入力と、不足する sandbox 設定をここで補う。
END {
  if (!in_section) add_top_level()
  if (in_sandbox && !seen_network_access) print "network_access = " network_access
  if (!seen_sandbox_section) {
    print ""
    print "[sandbox_workspace_write]"
    print "network_access = " network_access
  }
}
'
