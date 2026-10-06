#!/bin/bash
# Run inside a Herdr popup; keep tools in the focused pane's directory.
set -euo pipefail

herdr_bin=${HERDR_BIN_PATH:-herdr}
cd "${HERDR_ACTIVE_PANE_CWD:-$PWD}"

# Keep failures visible instead of closing the popup immediately.
on_error() {
  local status=$?
  printf '\nAction failed (exit %s). Press Enter to close.\n' "$status" >&2
  read -r _ || true
  exit "$status"
}
trap on_error ERR

pick() {
  local status=0
  FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf \
    --layout=reverse --border=none --no-multi --no-sort \
    --delimiter=$'\t' --with-nth=2.. --prompt="$1 > " \
    --header='Type to search / Up Down / Enter / Esc to go back' || status=$?
  case "$status" in
    0|1|130) return 0 ;;
    *) return "$status" ;;
  esac
}

while true; do
  choice=$(printf '%s\n' \
    $'git\tlazygit — Git status / commit / branches' \
    $'review\ttuicr — code review' \
    $'files\ttelevision — file preview / open in editor' \
    $'workspaces\tWorkspace — list / switch' \
    $'worktrees\tWorktree — list / open / switch' \
    $'new-worktree\tWorktree — create' \
    $'new-tab\tTab — create' \
    $'terminal\tScratch terminal' | pick 'Herdr')
  [[ -n "$choice" ]] || exit 0
  case "${choice%%$'\t'*}" in
    git) lazygit; exit 0 ;;
    review) tuicr; exit 0 ;;
    files) tv edit; exit 0 ;;
    terminal) "${SHELL:-/bin/sh}"; exit 0 ;;
    new-tab)
      "$herdr_bin" tab create --workspace "${HERDR_ACTIVE_WORKSPACE_ID:?}" --cwd "$PWD" --focus
      exit 0
      ;;
    workspaces)
      data=$("$herdr_bin" workspace list)
      choice=$(printf '%s' "$data" | jq -r '.result.workspaces[] | [.workspace_id, (.label + " (" + (.tab_count|tostring) + " tabs)" + (if .focused then " *" else "" end))] | @tsv' | pick 'Workspace')
      [[ -n "$choice" ]] || continue
      "$herdr_bin" workspace focus "${choice%%$'\t'*}"
      exit 0
      ;;
    worktrees)
      data=$("$herdr_bin" worktree list --cwd "$PWD")
      choice=$(printf '%s' "$data" | jq -r '.result.worktrees[] | select(.is_bare | not) | [(.path|tojson), ((.branch // "detached HEAD") + " — " + .path + (if .open_workspace_id then " [open]" else "" end))] | join("\t")' | pick 'Worktree')
      [[ -n "$choice" ]] || continue
      path=$(printf '%s' "${choice%%$'\t'*}" | jq -r '.')
      "$herdr_bin" worktree open --cwd "$PWD" --path "$path" --focus
      exit 0
      ;;
    new-worktree)
      printf '\nBranch name (empty to go back): '
      read -r branch || exit 0
      [[ -n "$branch" ]] || continue
      "$herdr_bin" worktree create --cwd "$PWD" --branch "$branch" --focus
      exit 0
      ;;
  esac
done
