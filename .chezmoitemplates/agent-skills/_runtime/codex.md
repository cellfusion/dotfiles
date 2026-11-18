> **Runtime tool mapping**
>
> | Logical name | Implementation in this environment |
> |---|---|
> | `[ask-user]` | Present choices and wait for the user's response; never decide silently |
> | `[dispatch-subagent: X]` | In OMP, use `hc run` per `agent-communication`; in Codex, use its supported subagent route |
> | `[resume-subagent]` | In OMP, follow up via `hc send` to the same verified terminal; otherwise use only an actual supported continuation API; unknown delivery never warrants automatic replacement |
> | `[deterministic-loop]` | Unavailable; run the loop yourself and count iterations |
> | `[todo]` | Task list tool; use an external ledger file when unavailable |
> | `[web-search]` | `web_search` |
> | `[retry-outside-sandbox]` | Retry the same command with `sandbox_permissions=require_escalated` and a justification; report failure if unavailable |
>
> This mapping is shared by Codex and OMP. Identify the actual runtime, not the template's tool
> value. Higher-priority runtime policy controls; if it conflicts with HC or HC is unavailable,
> report the blocker rather than silently falling back to OMP `task`. Follow the actual tool
> contract and selected environment reference; do not recreate prepared sessions.
