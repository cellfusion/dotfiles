# Publish only the saved, approved revision

The preview and approval gate in SKILL.md applies to every route: ready PR, draft PR, GitHub CLI,
REST/GraphQL/MCP and browser. Never use `gh pr create --dry-run` for preview: it may still push.
Never invoke `--web`, `--fill*`, `--editor` or an interactive create flow as an approval shortcut.

## Before preview

Establish as much as permitted with read-only operations:
- Actual GitHub host/base repo and head repo/owner; base/head branch names and immutable SHAs.
- Whether the intended remote head exists and equals the local committed `HEAD_SHA`.
  `git ls-remote --heads <verified-remote> "refs/heads/<branch>"` can inspect without fetch/push.
  Handle credential-bearing remote URLs privately; never persist them in context or shell logs.
- Current base branch SHA on the intended base repository, and the matching locally available
  commit. If the object is unavailable, a scoped read-only fetch may be used if permitted; do not
  checkout/reset or silently substitute a stale base. Unavailable remote evidence blocks creation.
- Existing open PRs for the exact head **repository and branch** in the selected base repository;
  inspect the returned head identity/base, not just a matching branch name. An existing PR means
  do not create another or edit it automatically. Report its URL and keep the local proposal.
- Publication mode/options. Default ready unless the user explicitly wants draft or unresolved
  work makes readiness doubtful; propose draft in that case, but still require approval to create.
  Do not automatically add reviewers, labels, assignees, projects, uploads or issue-closing text.

Target GitHub reads explicitly: `gh repo view "$REPO"` uses a positional repository argument;
`gh pr list/view --repo "$REPO"` uses the repository flag. CLI authentication/permission/network
failures mean unavailable, not “no existing PR”. Read-only preflight may happen before approval;
creation must not.
No remote head yet? Save the proposal and name the missing push. Do not commit, push or fork; request
separate permission only when the user wishes to resolve that prerequisite. After an authorized push,
recheck SHA/context and obtain approval for the final preview, not the earlier blocked proposal.

## Approval identity

Bind an explicit post-preview create decision to:
- run/revision and body SHA-256;
- title, base repo/host, head repo/owner, base/head branches;
- base/head SHAs and merge-base SHA;
- ready/draft mode and every publication option shown.

Store the sanitized decision and approved identity in `context.json` without raw conversation text.
“本文はOK”, “保存して”, earlier preapproval or a response to a different question means no creation.
If intent is ambiguous, clarify the action. When interaction is unavailable, retain the proposal;
a host permission prompt cannot substitute for the user's review of the text.

## Immediately before creation

Re-read saved body/context, recompute the body SHA-256, and check all approved identity fields.
Check current checkout/head and the intended remote head/base again, plus existing PRs. If anything
changed since preview, invalidate approval, preserve that revision, update the draft/evidence and
preview a new revision. Do not overwrite the approved text, silently retarget or auto-accept a changed
SHA. Freshness checks are not a transaction: remote branches can move afterwards; report mismatches
observed on the resulting PR and do not claim it exactly matches approval.

If any prerequisite is missing, stop with the concrete reason and artifact path. Never publish
a misleading body to a different branch just to complete the workflow.

## Creation command

Read live `gh pr create --help`; verify supported flags. For a pushed branch in the base repository,
pass the branch as `HEAD_SELECTOR`. For a supported personal fork, pass verified `owner:branch`.
Some gh versions do not support organization-owned fork selectors; do not omit `--head` or fall back
to an interactive push/fork. Report the unsupported route and retain the approved proposal.

After approval AND matching preflight, construct an argument array (do not evaluate title/body as
shell code). Use absolute `BODY_PATH` and all explicit target fields:

```bash
gh pr create --repo "$REPO" --base "$BASE_BRANCH" --head "$HEAD_SELECTOR" \
  --title "$TITLE" --body-file "$BODY_PATH"
```

Add `--draft` only when the approved mode is draft. Add other options only if displayed and approved.
Explicit `--head` skips gh's implicit push/fork behavior; never rely on default branch/remote guesses.
Never modify the body or append attachments after approval. No automatic login, scope refresh,
installation or permission bypass to force publication.

## Outcome and recovery

Capture exit status and returned URL. Confirm the actual PR with a read-only `gh pr view` or API:
repo, base/head repo and branches/SHAs, title, body and draft status. If output differs, disclose the
mismatch; do not silently edit/close it. Only report verified creation state, URL and retained files.

A timeout or nonzero exit is not proof that no PR exists. Check the same repo and exact head identity
for a newly created PR before doing anything else; some side effects can succeed before failure.
If a matching created PR is confirmed, report it. If outcome cannot be established, mark
**作成結果未確認** and retain evidence; never blindly retry and risk duplicates. Do not substitute
another repository, API, browser or create route to conceal uncertainty. A later retry requires a
resolved outcome, matching freshness checks and a fresh explicit create decision.

## Primary source

[GitHub CLI: gh pr create](https://cli.github.com/manual/gh_pr_create) documents `--body-file`,
`--repo`, `--base`, `--head`, `--draft`, implicit push/fork behavior, and the potentially mutating
`--dry-run`. Approval semantics above are this skill's safety policy, not a GitHub guarantee.
