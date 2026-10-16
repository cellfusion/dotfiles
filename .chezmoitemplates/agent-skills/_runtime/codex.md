> **Runtime tool mapping**
>
> | Logical name | Implementation in this environment |
> |---|---|
> | `[ask-user]` | Present choices and wait for the user's response; never decide silently |
> | `[dispatch-subagent: X]` | Spawn subagent `X` |
> | `[resume-subagent]` | Use only an actual supported continuation API; unknown delivery retains the same resource, never automatically spawn a replacement |
> | `[deterministic-loop]` | Unavailable; run the loop yourself and count iterations |
> | `[todo]` | Task list tool; use an external ledger file when unavailable |
> | `[web-search]` | `web_search` |
> | `[retry-outside-sandbox]` | Retry the same command with `sandbox_permissions=require_escalated` and a justification; report failure if unavailable |
>
> These logical mappings do not select an interaction host or checkout owner. Follow the actual
> runtime tool contract and selected environment reference; do not recreate prepared sessions.
