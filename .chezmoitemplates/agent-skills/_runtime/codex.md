> **Runtime Tool Mapping**
>
> | Logical Name | Implementation in this Environment |
> |---|---|
> | `[ask-user]` | Present options and await user response. Never make unilateral decisions |
> | `[dispatch-subagent: X]` | Spawn subagent `X` |
> | `[resume-subagent]` | No resumption mechanism exists. Spawn a new subagent and hand off context via report files |
> | `[deterministic-loop]` | Unavailable. Run the loop yourself and count rounds explicitly |
> | `[todo]` | Task list management tool; if absent, substitute with ledger file |
> | `[web-search]` | `web_search` tool |
> | `[retry-outside-sandbox]` | Re-run same command with `sandbox_permissions=require_escalated`, providing rationale for running outside sandbox in `justification` |
