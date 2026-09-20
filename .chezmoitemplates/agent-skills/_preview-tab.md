## Preview

After self-review and before the approval gate, make the artifact available for inspection. Do not
ask whether the user wants a preview.

Choose the first matching route:

| Condition | Route |
|---|---|
| `$PASEO_AGENT_ID` is non-empty | Show a Paseo file link |
| `$HERDR_ENV` is `1` | Open the file in a separate Herdr tab |
| Neither | Skip preview and continue to the approval gate |

Check `$PASEO_AGENT_ID` first. When both are set, the user is viewing Paseo.

### Paseo

```text
[View artifact](/absolute/path/artifact.md)
```

Do not create a terminal, run `glow`, or launch a fallback terminal in Paseo. Use `[View plan]` for a
plan artifact.

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
