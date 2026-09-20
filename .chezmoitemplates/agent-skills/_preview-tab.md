## Preview

Once self-review passes, make target files viewable **before** presenting the approval gate. Do not ask the user whether to open.

Routing depends on the environment. Evaluate in order and execute only the first matching path:

| Condition | Route |
|---|---|
| `$PASEO_AGENT_ID` is non-empty | "Display Paseo File Link" below |
| `$HERDR_ENV` is `1` | "Open in Herdr Tab" below |
| Neither | Skip this section entirely and proceed directly to the approval gate |

Evaluate `PASEO_AGENT_ID` first. When both are present, the user is looking at Paseo's interface.

### Display Paseo File Link

```bash
[View spec](/absolute/path/spec.md)
```

In Paseo, do not create terminals, run `glow`, or launch alternative terminals upon preview failure. For plans, use `[View plan](/absolute/path/plan.md)`.

### Open in Herdr Tab

```bash
ws=$(herdr pane get "$HERDR_PANE_ID" | jq -r '.result.pane.workspace_id')
pane=$(herdr tab create --workspace "$ws" --cwd "$PWD" --focus | jq -r '.result.root_pane.pane_id')
herdr pane run "$pane" '${EDITOR:-nvim} "<absolute-path-to-file>"; exit'
```

Treat the 3 commands above (`pane get` -> `tab create --workspace` -> `pane run`) as a single preview operation. Inspect stderr or tool errors. Only if initial execution fails with `PermissionDenied`, `Permission denied`, or `Operation not permitted` (since Herdr session sockets may reside outside the sandbox), retry the identical preview command exactly once with `[retry-outside-sandbox]`. In runtimes requiring `justification`, state: "Connect to current Herdr session to open artifact in a new tab."

- Adjust retry scope based on what succeeded initially. If `pane` is empty or `null` (`pane get` or `tab create` itself failed), reacquire `ws` and `pane` and retry all 3 commands. If `pane` holds a non-empty value (only `herdr pane run` failed), reuse that `ws` and `pane` and retry only `herdr pane run`. Retrying `tab create` creates duplicate tabs and leaves the first orphaned without running `; exit`.
- If retrying outside the sandbox also fails, or failure was not due to permission denied, do not retry further; report preview failure in one line and advance to the approval gate.

- **Always pass `--workspace`.** If omitted, the tab may open in whatever workspace the user currently focuses, opening outside your workspace. Derive workspace ID from `$HERDR_PANE_ID` via `herdr pane get` and pass it to `--workspace`.
- Editor defaults to `$EDITOR`, falling back to `nvim` if unset. Wrap the string passed to `herdr pane run` in **single quotes** so `${EDITOR:-nvim}` expands within the target pane's shell. Double quotes expand it locally in the agent shell.
- **Do not omit trailing `; exit`.** Without this, the shell persists after exiting the editor, leaving empty orphaned panes.
- Pass `--focus` to direct user attention to the preview tab.
- Pass the file path as an absolute path enclosed in double quotes.
- If `herdr tab create` fails for reasons other than permission denied (`pane` is empty or `null`), state this in one line and proceed to approval gate without preview. Never halt workflow because of preview failure.

The tab closes automatically when the user exits the editor. Due to `; exit`, closing the editor terminates the pane's shell, removing the pane and tab. **Never invoke tab-closing commands autonomously.** Closing while the user is reading or editing leads to lost input.

### Common Guidelines

In the Herdr route, editors open in editable mode. Do not add read-only flags. The user can make immediate inline edits. In the Paseo route, `glow` is read-only, so manual edits do not occur. In both routes, **always re-read the file after receiving the approval gate response before creating issues or handing off to subsequent skills.** The re-read content is authoritative over what the agent initially wrote. If re-reading reveals discrepancies with the agent's prior perception, report differences in 1-2 lines before proceeding.
