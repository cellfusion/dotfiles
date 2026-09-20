## Approval Gate
{{ $worktree := false }}
{{- if hasKey . "worktree" }}
{{- $worktree = .worktree }}
{{- end }}

Once the preview is open, obtain approval using `[ask-user]`.
{{ if .issue }}
Execute `gh repo view` before presenting the gate. If the exit status is non-zero (`gh` missing, unauthenticated, or no GitHub remote), **drop the two issue options and present only "Approve & Proceed" and "Approve only"**. Do not expose the check command's output to the user.
{{ end }}
{{- if $worktree }}
Verify the following two conditions before presenting the gate. If either fails, **remove the worktree option and present only "Approve & Proceed" and "Approve only"**. Do not expose the check command's output to the user.

```bash
test "${HERDR_ENV:-}" = 1
git rev-parse --git-dir
```
{{ end }}
- Question: "{{ .artifact }} written to `<path>`. May I proceed to {{ .nextLabel }} with this content?"
- Options:
{{- if $worktree }}
  - **Approve & Delegate via worktree** — Create worktree as a new workspace and pass {{ .nextLabel }} to a Claude session started there (only shown under herdr management)
{{- end }}
  - **Approve & Proceed** — Advance to {{ .nextLabel }}
  - **Approve only** — Keep {{ .artifact }} in `~/docs/<owner>/<repo>/` and end here
{{- if .issue }}
  - **Approve & Proceed (Create Issue)** — Create issue, record issue number, and advance to {{ .nextLabel }} (only shown when `gh` is available)
  - **Approve (Create Issue)** — Create issue, record issue number, and end here (only shown when `gh` is available)
{{- end }}

**Do not include modification options.** Edits are accepted via free-form input ("Other"). **Do not include cancellation options.** If closed without selection, halt there.

Regardless of selection, re-read the file before processing to incorporate manual edits.

{{- if $worktree }}
### Approve & Delegate via worktree

Follow the "Delegating to Worktree" section below.
{{ end }}
### Approve & Proceed

Pass the absolute file path and proceed according to the handoff section below.

### Approve only

{{ .artifact }} remains in `~/docs/<owner>/<repo>/`. Do not launch the next skill. Report the file's absolute path and finish.
{{ if .issue }}
### Issue Creation Branches

Both "Approve & Proceed (Create Issue)" and "Approve (Create Issue)" execute the following steps:

1. Run `gh issue create --title "<File H1 Title>" --body-file "<Absolute Path to File>"`. Pass the entire file body directly (do not trim title duplication with H1).
2. If it fails, do not modify the file; report failure and return to approval gate.
3. If it succeeds, insert the following line immediately following the H1 heading. If a line of this format already exists, replace it (preventing line duplication on re-issue creation):

   ```markdown
   > Issue: [#123](https://github.com/owner/repo/issues/123)
   ```

4. Do not delete the file. Keep it in `~/docs/<owner>/<repo>/`.
5. Report the issue number and URL.

Then, for "Approve & Proceed (Create Issue)", advance according to the handoff section below, passing the issue number forward. For "Approve (Create Issue)", report the absolute file path and issue number, then terminate.
{{ end }}
### Other (Free-form Input)

Treat as modification instructions. Apply requested changes, re-run self-review, and present preview and approval gate once more.

### If Nothing Selected

Treat as cancellation and halt execution. Keep file in `~/docs/<owner>/<repo>/`.
