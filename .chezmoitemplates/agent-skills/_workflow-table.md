## Workflow selection

The skill owns its detailed procedure. Start a skill only when the request requires it; reading the
request, inspecting files, and asking a necessary clarification are not themselves reasons to start
a skill.

| Request | First route |
|---|---|
| Clear local change | Implement directly; use brainstorming only if a design choice remains |
| Unknown implementation route, work class, or delegation | `task-routing`; follow only the selected path |
| Unsettled intent or behavior | `brainstorming` when a design choice needs clarification; `task-routing` only if the implementation route is also unclear |
| Multi-layer design change | `task-routing` if route/delegation is unclear; `brainstorming` for unsettled design, `writing-plans` for multi-stage planning when needed |
| Bug, failure, or unexpected behavior | `systematic-debugging` when root cause is unknown |
| Existing implementation plan | `executing-plans` for a small sequential plan; `multi-agent-development` for parallel or independent review |
| Ordinary bounded delegation | In OMP, `agent-communication` via HC; otherwise the host's internal child route |
| Independent CLI conversation or user intervention | `agent-communication` and the selected environment reference; agents do not steal focus |
| Child write isolation only | `using-git-worktrees` recorded checkout-owner route; no interaction workspace/tab/pane |
| GitHub PR review | `pr-review` selects/validates the host (agents use `--no-focus`); prepared context reuses its existing validated session |
| Integration, merge, push, or owned-resource cleanup requested | `finishing-a-development-branch` |
| About to claim completion or test passage | `verification-before-completion` |
| Code-review feedback received | `receiving-code-review` |

The parent chooses the route from clarity, risk, and workload. Do not chain skills automatically.
When the requested outcome and implementation approach are settled, investigate only what is needed
to implement safely, then connect the requested product path. Do not make an extra experiment,
proof, compatibility requirement, or review an implementation gate without tying it to an
acceptance criterion, an applicable rule, or a concrete safety risk. State the failure and the
smallest necessary check; keep optional investigations separate from completion. Never bypass
required safety, permissions, or provider checks.
If invoked as a subagent, ignore this routing table and follow the parent's bounded contract.
