## Workflow selection

The skill owns its detailed procedure. Start a skill only when the request requires it; reading the
request, inspecting files, and asking a necessary clarification are not themselves reasons to start
a skill.

| Request | First route |
|---|---|
| Clear local change | Implement directly; use brainstorming only if a design choice remains |
| Unknown implementation route, work class, or delegation | `task-routing` |
| Unsettled intent or behavior | `task-routing`, then `brainstorming` when needed |
| Multi-layer design change | `task-routing` -> `brainstorming`, then `writing-plans` when needed |
| Bug, failure, or unexpected behavior | `systematic-debugging` when root cause is unknown |
| Existing implementation plan | `executing-plans` for a small sequential plan; `multi-agent-development` for parallel or independent review |
| Implementation complete or integration requested | `finishing-a-development-branch` |
| About to claim completion or test passage | `verification-before-completion` |
| Code-review feedback received | `receiving-code-review` |

The parent chooses the route from clarity, risk, and workload. Do not chain skills automatically.
If invoked as a subagent, ignore this routing table and follow the parent's bounded contract.
