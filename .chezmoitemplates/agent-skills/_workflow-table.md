## Development Workflow

Development procedures are defined in skills. However, launch skills only when requested or needed. Never make reading user requests, inspecting relevant files, or asking clarifying questions prerequisite on launching a skill.

| Request | Initial Skill to Launch |
|---|---|
| Clear, localized change | Inspect and implement directly. Use `brainstorming` only if design alternatives remain |
| Implementation path, work class, or delegation method unclear | `task-routing` |
| Intent or expected behavior undetermined | `task-routing`. Use `brainstorming` if necessary |
| Multi-layer architectural change | `task-routing` -> `brainstorming`. Use `writing-plans` if needed |
| Bug, failure, "not working", "broken" | `systematic-debugging` if root cause is unverified |
| Implementation plan already exists | `executing-plans` if small. `multi-agent-development` if concurrency or independent reviews are needed |
| Implementation finished / ready to merge | `finishing-a-development-branch` |
| Right before asserting completion or test passage | `verification-before-completion` |
| Code review feedback received | `receiving-code-review` |

Brainstorming is not required for every change. The parent agent determines which skill to use and which path to take based on request clarity, risk, and volume of work.

Ignore these instructions when launched as a subagent.
