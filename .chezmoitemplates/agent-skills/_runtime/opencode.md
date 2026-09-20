> **Runtime tool mapping**
>
> | Logical name | Implementation in this environment |
> |---|---|
> | `[ask-user]` | `question`; if unavailable, present choices and wait |
> | `[dispatch-subagent: X]` | `task` with subagent `X`, or `@X` |
> | `[resume-subagent]` | No resume mechanism; spawn a new child and pass context through a report file |
> | `[deterministic-loop]` | Unavailable; run the loop yourself and count iterations |
> | `[todo]` | `todowrite` |
> | `[web-search]` | `websearch` |
> | `[retry-outside-sandbox]` | Use the available permission/escalation mechanism to retry the same command; otherwise report failure |
