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

## Inspect without steering

- For status or a result, read `agent://<actual-id>` for a known native child. For a
  separate Rex session, verify the server, session, block, and foreground OMP process,
  then use `rex block call ... program_status` or `rex capture ... --trim`. A status or
  transcript excerpt does not prove completion. Read only what is needed.
- For a question about work in progress, use `/btw <question>` in the target OMP session.
  Ask for facts already in context, for example: `/btw What have you verified so far,
  and what is still unknown? Use only this session's context.` The side turn uses no
  tools and does not add a turn to the main transcript. Its answer may be incomplete
  or stale; saved sessions retain separate BTW history.
- From another device using Rex, open the same verified pane and invoke `/btw` there.
  Inspect the composer first: do not overwrite someone else's draft or input into an
  approval prompt. For automation, a host that already owns the target OMP process's
  stdio RPC connection can send `type: "btw"` and correlate the final `btw_record` by
  record ID. An ordinary TUI process is not an RPC endpoint; do not start another OMP
  on the same session just to attach.
- Side questions do not assign work. Do not inject an answer, branch, send a normal
  prompt, or steer the running agent unless the user asks to change its work. A
  manually submitted `/btw` still makes a model request using the session's context.

See [OMP 19.1 RPC side questions](https://github.com/can1357/oh-my-pi/blob/v19.1.0/docs/rpc.md#side-questions-btw).

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
