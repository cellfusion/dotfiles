> **Runtime Tool Mapping**
>
> | Logical Name | Implementation in this Environment |
> |---|---|
> | `[ask-user]` | `question` tool. If unavailable, present options and wait for user response |
> | `[dispatch-subagent: X]` | Specify subagent `X` via `task` tool, or invoke with `@X` |
> | `[resume-subagent]` | No resumption mechanism exists. Spawn a new subagent and hand off context via report files |
> | `[deterministic-loop]` | Unavailable. Run the loop yourself and count rounds explicitly |
> | `[todo]` | `todowrite` tool |
> | `[web-search]` | `websearch` tool |
> | `[retry-outside-sandbox]` | Re-run command outside sandbox via available permission/escalation mechanism. If unavailable, treat as failure |
