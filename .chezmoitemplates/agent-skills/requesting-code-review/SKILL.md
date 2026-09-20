---
name: requesting-code-review
description: >-
  Use when requesting reviews at task boundaries, after substantial feature implementation,
  or before merging. Provide review children with only precisely crafted context for evaluation,
  preserving your own context for coordination.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# Requesting Code Review

Use MAD's `review` recipe to catch issues before they propagate. Provide reviewers with **precisely assembled context tailored for evaluation**. Do not pass your session history.

**Core**: Review early and frequently.

## When to Request

**Mandatory**:
- After each task in `multi-agent-development`
- After completing a substantial feature
- Before merging into main

**Optional but recommended**:
- When stuck (to gain a fresh perspective)
- Before refactoring (to capture a baseline)
- After fixing an intricate bug

## How to Request

**1. Consolidate diff into a file**

Load the diff into the reviewer's context with a single Read. Build the review package with:

```bash
BASE_SHA=$(git merge-base master HEAD)   # or base of target range
HEAD_SHA=$(git rev-parse HEAD)
```

Create the authoritative file in the directory returned by `agent-docs-dir reviews`. Avoid `/tmp` so that the authoritative package remains readable even after review completes. Assembly is delegated to `review-bundle`, matching MAD. Because requesting a second review over the same commit range targets the same path, only this call passes `--force`. `review-bundle` creates the parent directory of `--out` with mode 0700 if missing. Since the directory returned by `agent-docs-dir reviews` already exists, its mode is not modified.

```bash
REVIEWS="$(~/.agents/skills/_shared/scripts/agent-docs-dir reviews)"
OUT="$REVIEWS/review-${BASE_SHA:0:7}..${HEAD_SHA:0:7}.diff"
~/.agents/skills/multi-agent-development/scripts/review-bundle \
  --cwd "$(git rev-parse --show-toplevel)" \
  --base "$BASE_SHA" --head "$HEAD_SHA" --out "$OUT" --force
```

**2. Request review**

Use MAD's `review` recipe. Invocation details reside in the `multi-agent-development` skill.

Across both routes, pass only these 4 items (never pass session history):
- Overview of what was implemented
- Absolute path to plan or requirements (or a concise summary if unavailable)
- Absolute path to review package
- List of deferred or parked findings (if any)

MAD's `review` spawns perspective-specific `reviewer` instances in parallel, synthesized by `review-synthesizer` into actionable findings. The synthesized outcome is `approved` only when zero critical or important findings remain.

Both the review package and plan reside outside the working tree. Because child agents must function in engine configurations that disallow reading outside cwd, copy them into a unique directory under `<repo-root>/.agent-review/` before passing, providing the copied absolute paths:

```bash
# Source requirements file; if plan, resides under agent-docs-dir plans
REQ_SRC="$(~/.agents/skills/_shared/scripts/agent-docs-dir plans)/PLAN.md"

# Children cannot read outside cwd; stage into repository before passing
STAGE_ROOT="$(git rev-parse --show-toplevel)/.agent-review"
mkdir -p "$STAGE_ROOT"
if [ ! -e "$STAGE_ROOT/.gitignore" ]; then
  printf '*\n' > "$STAGE_ROOT/.gitignore"
fi
STAGE="$(mktemp -d "$STAGE_ROOT/run.XXXXXX")"
cleanup() { rm -rf -- "$STAGE"; }
trap cleanup EXIT
# Trap removes unique staged directory on exit regardless of success or failure
cp "$OUT" "$STAGE/"
cp "$REQ_SRC" "$STAGE/"
STAGED_REVIEW="$STAGE/$(basename "$OUT")"
STAGED_REQ="$STAGE/$(basename "$REQ_SRC")"
```

If passing requirements as text rather than a file, supply the summary text directly instead of `STAGED_REQ`. Only the review package requires staging.

`.gitignore` inside `.agent-review/` ignores everything inside. Even in environments without global gitignore, staged copies will not accidentally enter commits. Even if cleanup fails, it will not appear in `git status`.

**3. Address feedback**

- Fix Critical findings immediately. Fixes are performed by child agents; parent passes findings and review package path to MAD's `implement` recipe.
- Fix Important findings before proceeding. Route and payload match Critical.
- Record Minor findings for later handling.
- If the reviewer is mistaken, push back with technical rationale.

**The parent must not fix Critical and Important findings directly.** Fixes written by the parent do not receive independent reviewer evaluation. The fix diff and test logs would also persist in parent context, re-read on every subsequent turn.

Follow `receiving-code-review` for receiving etiquette.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "Inspect diff myself without a reviewer" | You are the coordinator. Reading diffs inline burdens your context across all subsequent turns, leaving less room for coordination. Spawning a reviewer subagent confines the diff and evaluation to their context, returning only the findings |
| "Reviewer needs my session history" | Pass precisely assembled context. Omit history. The reviewer evaluates the artifact, not your thought process |
| "Too simple to need review" | What simple changes break is rarely simple |

## Prohibited Behaviors

- Ignoring Critical findings
- Advancing without fixing Important findings
- Arguing with valid technical feedback
- Instructing reviewers not to raise specific issues

**When a reviewer is incorrect**:
- Push back with technical rationale
- Provide tests or code demonstrating behavior
- Ask for clarification
