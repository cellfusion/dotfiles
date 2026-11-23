> **Runtime tool mapping**
>
> | Logical name | Implementation in this environment |
> |---|---|
> | `[ask-user]` | Present choices and wait for the user's response; never decide silently |
> | `[dispatch-subagent: X]` | Select the route in `agent-communication`: OMP in Rex uses native `task` for bounded children; Codex uses its supported subagent tool |
> | `[resume-subagent]` | Use the same child's supported follow-up API or the verified terminal route already selected; unknown delivery never warrants automatic replacement |
> | `[deterministic-loop]` | Unavailable; run the loop yourself and count iterations |
> | `[todo]` | Task list tool; use an external ledger file when unavailable |
> | `[web-search]` | `web_search` |
> | `[retry-outside-sandbox]` | Retry the same command with `sandbox_permissions=require_escalated` and a justification; report failure if unavailable |
>
> Identify the agent runtime and terminal host independently. In Rex, use `rex` for explicitly
> requested terminal launches and pane handoffs, not `hc`. The presence of an executable does
> not identify the host. Follow the actual tool contract; do not recreate prepared sessions.
