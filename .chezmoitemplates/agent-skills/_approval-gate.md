## Approval gate
{{ $worktree := false }}
{{- if hasKey . "worktree" }}
{{- $worktree = .worktree }}
{{- end }}

After preview, obtain explicit approval with `[ask-user]`.
{{ if .issue }}
If the artifact needs an issue, run `gh repo view` before showing issue choices. If GitHub is
unavailable or the repository has no GitHub remote, omit issue choices and show only proceed/approve.
{{ end }}
{{- if $worktree }}
Before showing the gate, read `using-git-worktrees` and its environment/owner references.
Verify that the selected route supports the required checkout isolation and independent
interaction, with an identified owner and safe creation procedure. Verify Git repository
identity as well. If required capabilities are unavailable or ambiguous, omit the worktree
option and show only proceed/approve. Do not select a host merely to make the option available.
{{ end }}

- Question: "`{{ .artifact }}` is at `<path>`. May I {{ .nextLabel }} with this content?"
- Options:
{{- if $worktree }}
  - **Approve and delegate via worktree** — create the approved isolated checkout and independent conversation through the selected environment/owner route; write isolation alone does not create a visible conversation
{{- end }}
  - **Approve and continue** — proceed to {{ .nextLabel }}
  - **Approve only** — retain the {{ .artifact }} and stop
{{- if .issue }}
  - **Approve and create an issue, then continue** — create and link an issue, then proceed
  - **Approve and create an issue only** — create and link an issue, then stop
{{- end }}

Do not add a modification or cancellation choice. Accept modifications through free-form input. If
the user closes the prompt without a selection, stop and retain the artifact. Re-read the artifact
before processing any selected branch.
{{- if $worktree }}
### Approve and delegate via worktree

Follow the `worktree-handoff` section.
{{ end }}
### Approve and continue

Pass the artifact's absolute path to the next skill.

### Approve only

Leave the artifact in its external documentation directory, report its absolute path, and stop.
{{ if .issue }}
### Issue branches

Run `gh issue create --title "<H1>" --body-file "<absolute path>"`. On failure, do not modify the
artifact. On success, add or replace one issue link immediately after the H1 and report the URL.
Keep the artifact. Continue only for the continue branch.
{{ end }}
### Free-form modification

Apply the requested changes, re-run self-review, preview, and this approval gate.
