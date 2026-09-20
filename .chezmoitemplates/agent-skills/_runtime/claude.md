> **Runtime tool mapping**
>
> | Logical name | Implementation in this environment |
> |---|---|
> | `[ask-user]` | `AskUserQuestion` |
> | `[dispatch-subagent: X]` | `Agent` with `subagent_type: X` |
> | `[resume-subagent]` | `SendMessage` |
> | `[deterministic-loop]` | `Workflow` when available |
> | `[todo]` | Task list tool; use an external ledger file when unavailable |
> | `[web-search]` | `WebSearch` |
> | `[retry-outside-sandbox]` | Retry the same command with a permission prompt outside the sandbox; report failure if unavailable |
