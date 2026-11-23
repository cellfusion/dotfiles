---
name: pi-runtime
description: Load when explicitly launching Pi, handing off work from Pi, or checking Pi's permissions and session isolation. Not a reason to choose Pi.
---

# Pi Runtime

- Follow Agent Selection in `~/.agents/AGENTS.md` when choosing a new agent. Do not launch Pi just because the current session uses Pi or a role was previously distributed as a Pi template.
- Do not assume Pi provides OMP's native `task`, `agent://` addresses, computer-use API, or approval mode. Check the tools and restrictions actually exposed by the running session. A role prompt is not a sandbox. If the task requires enforcement the current setup cannot prove, stop rather than launch a less restricted session.
- When Pi is explicitly selected, check the installed `pi --help` before adding flags. For terminal handoffs, read `agent-communication`; in Rex use `rex` with a verified session and block. Do not use hc or assume parent-child completion notifications.
- Pi's authentication and sessions are separate from OMP's. Use the intended account/profile; never copy credentials or histories to make the launch work.
