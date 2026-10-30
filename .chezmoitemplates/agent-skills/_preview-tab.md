## Preview

After self-review and before the approval gate, make the artifact available for inspection. Do not
ask whether the user wants a preview.

Choose the first matching route:

| Condition | Route |
|---|---|
| `$HC_TERMINAL_ID` is set or herdr-core is the selected host | Provide the artifact's absolute path; show UI only if the user requested it |
| `$HERDR_ENV` is `1` (legacy Herdr) | Open the file in a separate Herdr tab |
| Neither | Provide the artifact's absolute path and continue to the approval gate |

### herdr-core / herdr-app

Do not create a space, tab, pane or labeled worker automatically for a preview. Read `herdr-core`
and the live `hc --skill`; use `herdr-app` and its live `herdr-app --skill` only when the user
requested visible UI. Inspect current IDs and supported commands before targeting a named preview
tab. Never launch bare `herdr-app`, steal focus, or infer a pane ID from `$HC_TERMINAL_ID`.
On a remote host, identify the machine with the artifact's absolute path; local file tools cannot
open remote files. A returned path makes the artifact available without changing the user's display.

### Herdr

```bash
ws=$(herdr pane get "$HERDR_PANE_ID" | jq -r '.result.pane.workspace_id')
pane=$(herdr tab create --workspace "$ws" --cwd "$PWD" --focus \
  | jq -r '.result.root_pane.pane_id')
herdr pane run "$pane" '${EDITOR:-nvim} "/absolute/path/artifact.md"; exit'
```

Treat these commands as one preview operation. Inspect errors. Retry the identical operation once
outside the sandbox only for permission errors. If the pane was created, retry only `pane run`; do
not create a duplicate tab. If preview fails for another reason, report it and continue to approval.
Always pass `--workspace`, use an editable editor, quote the absolute path, pass `--focus`, and keep
`; exit` so the tab closes when the editor exits. Never close the tab autonomously while the user may
be reading or editing.

After the approval response, re-read the artifact before issue creation or handoff. On-disk content,
including manual edits, is authoritative.
