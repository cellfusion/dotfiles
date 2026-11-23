# OMP Delegation and Handoffs

OMP is the agent runtime, not the terminal host. Select one route before dispatch:

| Context | Bounded same-repository child | Explicit terminal session or handoff |
| --- | --- | --- |
| Verified Rex | Native OMP `task` | [Rex communication](rex.md) |
| Verified herdr-core, not Rex | [HC communication](herdr-core.md), subject to runtime policy | [HC communication](herdr-core.md) |
| Neither host selected or verified | Native OMP `task` if available | Verify the requested host before acting |

In Rex, confirm inherited `REX_SESSION` and `REX_BLOCK` with `rex whoami --json` before
terminal operations. A confirmed Rex host or explicit Rex request does not select HC even
if `hc` is installed or `HC_TERMINAL_ID` leaked into the environment. For an explicit HC request
or a candidate HC session without Rex, verify live HC identity according to its reference.
Do not reinterpret missing or ambiguous terminal identity as permission to start a terminal.

## Native children

Use the exposed `task` tool for justified bounded work. Give each child a `request_id`, exact cwd,
files and non-goals, acceptance criteria, verification owner and stop conditions. Do not delegate
permissions or unrelated conversation. Record the returned ID. Follow up via `write agent://<actual-id>`
if supported; read `agent://<actual-id>` for status or result. Consume completion notifications and
wait only when blocked. When using the Eval agent API instead, read `xd://eval/agents` before
dispatch and keep the same handle for follow-up.

`agent://` does not address a separate OMP conversation in a terminal. For that, use the selected
host's reference. If the chosen route is unavailable or delivery is uncertain, report the blocker
and inspect the same resource; do not silently switch transports or spawn a replacement.
