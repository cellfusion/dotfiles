> **Runtime tool mapping**
>
> | Logical name | Implementation in this environment |
> |---|---|
> | `[ask-user]` | `AskUserQuestion` |
> | `[dispatch-subagent: X]` | `Agent` with `subagent_type: X` |
> | `[resume-subagent]` | `SendMessage` only when the actual tool supports the existing recipient; never automatically replace a resource after unknown delivery |
> | `[deterministic-loop]` | `Workflow` when available |
> | `[todo]` | Task list tool; use an external ledger file when unavailable |
> | `[web-search]` | `WebSearch` |
> | `[retry-outside-sandbox]` | Retry the same command with a permission prompt outside the sandbox; report failure if unavailable |
>
> These logical mappings do not select an interaction host or checkout owner. Follow the actual
> runtime tool contract and selected environment reference; do not recreate prepared sessions.
