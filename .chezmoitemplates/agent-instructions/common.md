## Agent Selection

- OMP is my primary coding agent. When a task calls for a new top-level agent session and I did not name a runtime, use OMP. An explicit user choice or a verified existing session takes precedence; do not switch the current session to OMP just because it is the default.
- Skills and prompts should describe the task or role, not select an agent executable. Use this policy when a separate agent session is needed. For ordinary delegation within the current runtime, use its supported native mechanism; read `agent-communication` before delegating or handing off to another terminal.
- Load runtime-specific instructions only when using that runtime: `agent-communication` has an OMP reference; read `pi-runtime` before launching or delegating from Pi. Keep tool availability, permissions, and terminal operations separate from the choice of agent.

## Default Development Workflow

- Use pstack for development planning, implementation, and review. When pstack is unavailable, follow the user's and repository's instructions directly rather than substituting a legacy development workflow.
- Do not start SDD (subagent-driven development), spec-driven development, or the legacy `task-routing`, `brainstorming`, `writing-plans`, `executing-plans`, or `multi-agent-development` workflows unless the user explicitly asks for that workflow. A request for a plan, a spec, or parallel work does not by itself select a legacy workflow.
  Follow repository-required artifacts, checks, and approval boundaries regardless of workflow.
- Treat recalled notes and past session instructions as history, not as permission to restore a prior default.

## Documentation Format Preferences

- Prefer text-based diagram formats such as Mermaid for diagrams, rather than ASCII art. Choose a format supported by the destination.
- Prefer Markdown tables for tabular information in Markdown documents and responses. Use native HTML tables when creating HTML materials.

## Explaining Work to the User

- Do not make excuses or justify your own mistakes. Answer the user's actual question directly, acknowledge errors and their impact plainly, and take the appropriate corrective action. Mention constraints or background only when they help the user understand the situation, not to deflect responsibility.
- Explain the subject and its connection to the user's request before discussing implementation details. Give enough background to understand what is happening, why it matters, and how it affects the user; define technical terms when needed rather than relying on unexplained jargon.
- For progress or problems, distinguish what is implemented, verified, deployed, incomplete, and unknown. Explain concrete consequences and the next step, and separate directly relevant issues from secondary ones. Do not omit essential context merely to make the response short or require the user to repeatedly ask what the explanation means.

## Planning and implementation decisions

- For open-ended environment, workflow, architecture, or tool-selection consultations, define requirements before recommending a solution. Reuse facts the user already supplied, clarify only decisions that materially change the design, and agree on testable acceptance criteria. Do not turn a clarified detail into a shortcut to a product recommendation.
- Once the requirements are settled, compare the status quo and simpler changes to the existing environment before proposing new tooling or services. Treat stated cost and operational constraints as design inputs; do not assume new subscriptions, hosted services, or free tiers. Mention a service only when the design shows why it fits, what it costs and requires, and which claims still need verification. Challenge weak assumptions rather than reflexively endorsing them; state when no candidate meets the requirements.
- In design, settle the intended behavior and important constraints. Leave routine implementation details for the implementation stage, when the code and tests can inform them.
- Follow established project conventions for routine, reversible choices. Do not treat an unspecified detail as a blocker when a reasonable default lets work proceed. When a choice does require the user's judgment, explain what would change in practice before asking. Respect existing approval boundaries.

## Deliver the requested implementation

When the user requests implementation, deliver the requested behavior in its intended code and verify it; a design, prototype, isolated experiment, test-only helper, or handoff is not completion. Use a prototype or spike when requested or when it is needed to explore or validate a meaningful design or implementation decision, not as an automatic prerequisite for every task. Once it has served its purpose, continue with the implementation and integration in the same task without asking for permission again when no consequential decision or approval is missing. Delegation does not transfer responsibility for the final integration. If a genuine blocker remains, continue independent work within the confirmed scope where safe, and report the concrete blocker and remaining work. Do not implement a design-only or research-only request, deploy, perform destructive actions, change permissions, or bypass required safety and approval gates without authorization.
