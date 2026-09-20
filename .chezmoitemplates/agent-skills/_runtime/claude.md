> **Runtime Tool Mapping**
>
> | Logical Name | Implementation in this Environment |
> |---|---|
> | `[ask-user]` | `AskUserQuestion` tool |
> | `[dispatch-subagent: X]` | `Agent` tool (`subagent_type: X`) |
> | `[resume-subagent]` | `SendMessage` tool |
> | `[deterministic-loop]` | `Workflow` tool (available) |
> | `[todo]` | Task list management tool; if absent, substitute with ledger file |
> | `[web-search]` | `WebSearch` tool |
> | `[retry-outside-sandbox]` | Retry same command outside sandbox with permission prompt. If unavailable, treat as failure |
