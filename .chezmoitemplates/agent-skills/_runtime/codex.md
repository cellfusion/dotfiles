> **Runtime tool mapping**
>
> | Logical name | Implementation in this environment |
> |---|---|
> | `[ask-user]` | Present choices and wait for the user's response; never decide silently |
> | `[dispatch-subagent: X]` | Spawn subagent `X` |
> | `[resume-subagent]` | No resume mechanism; spawn a new child and pass context through a report file |
> | `[deterministic-loop]` | Unavailable; run the loop yourself and count iterations |
> | `[todo]` | Task list tool; use an external ledger file when unavailable |
> | `[web-search]` | `web_search` |
> | `[retry-outside-sandbox]` | Retry the same command with `sandbox_permissions=require_escalated` and a justification; report failure if unavailable |
