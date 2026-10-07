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
| Ordinary bounded delegation | OMP internal child; no separate CLI or pane |
| Independent CLI conversation or user intervention | `herdr`, existing cwd or one explicitly owned pane; agents do not steal focus |
| Child write isolation only | `using-git-worktrees` hidden Worktrunk route; no Herdr workspace/tab/pane |
| GitHub PR review | `pr-review` shell entry (agents use `--no-focus`); prepared context runs in the existing OMP root pane |
| Implementation complete or integration requested | `finishing-a-development-branch` |
| About to claim completion or test passage | `verification-before-completion` |
| Code-review feedback received | `receiving-code-review` |

The parent chooses the route from clarity, risk, and workload. Do not chain skills automatically.
If invoked as a subagent, ignore this routing table and follow the parent's bounded contract.
