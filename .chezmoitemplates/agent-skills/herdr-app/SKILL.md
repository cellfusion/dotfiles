---
name: herdr-app
description: >-
  Inspect or change the new Herdr application's visible spaces, tabs, panes, focus and mods.
  Use for explicit Herdr app UI requests, not background agent orchestration; herdr-core (hc)
  owns persistent programs and communication. Not the legacy herdr CLI.
---

# Herdr App

Read the installed, version-matched official manual first:

```bash
herdr-app --skill
```

Use `herdr-app commands` to learn current command shapes. Never launch bare `herdr-app` for
inspection: it opens or raises the window. The official manual is authoritative; do not translate
legacy `herdr workspace`, `tab` or `pane` commands mechanically.

## Separate display from execution

- Use `herdr-core` for starting, reading, messaging, waiting and cleaning up programs/agents.
- `HC_TERMINAL_ID` is a core terminal address, not an app pane ID.
- App operations change what the person sees. Only create spaces/tabs or change focus when asked;
  ordinary workers remain hidden. Do not add display labels just to run a background worker.
- To show an existing core terminal when requested, use its verified terminal address with
  `terminal.keep` or the manual's space/tab labels; these are distinct from pane IDs. Choose the
  requested placement and inspect the result. Do not attach labels merely to communicate.
- `terminal.park` removes the pane and disables core keep, but leaves the terminal running.
  Closing a pane, tab or space ends its terminal(s); `terminal.kill` ends the terminal and its
  sub-agents. These are not equivalent to closing the window; do not use them as display-only
  cleanup without authorization.
- Inspect `herdr-app ls` and `herdr-app status` before acting. Use returned IDs and explicit useful
  names. Read the creation response and inspect the resulting state; launch acceptance does not
  prove the program started successfully.
- Remote folders belong to the selected machine. Use core's remote command/file surfaces rather
  than local tools for remote paths.
- Never stop, restart or signal the person's app/core. Closing a window does not end core terminals.

## Mods and configuration

For requested customization, follow the installed guide and generated type declarations identified
by the official manual. Do not edit generated files. Clone shipped mods/layouts before customizing.
In this dotfiles repository edit only chezmoi sources, inspect targeted `chezmoi diff` first, and
apply only explicitly approved targets. Saving live settings may reload them immediately; source
editing alone does not authorize applying or mutating the user's running display.

After an approved live mod change, run `herdr-app check <mod-path>`, inspect `status`, and examine
an actual `herdr-app shot <temporary-png>` image. A passing load check is not visual verification.
Never test pointer/key automation on the user's display; use an isolated environment for experiments.
