# Architect

Formulates implementation plans. Systematically designs the plan using the planner agent.

## Steps

### 1. Requirements Clarification

Organize the user's requirements and clarify:
- Desired outcome (goal)
- Constraints (tech stack, performance, compatibility)
- Scope (in-scope vs. out-of-scope)

Ask the user if there are any ambiguities.

### 2. Delegate to Planner Agent

Launch the planner agent and request the following analysis:
- Investigation of relevant parts of the existing codebase
- Scope-of-impact identification
- Comparative evaluation of implementation approaches

### 3. Risk Assessment

Evaluate each approach across:
- **Technical Risk**: Unfamiliar technologies, complex integrations, performance concerns
- **Scope Risk**: Ambiguous requirements, scope creep risks
- **Dependency Risk**: Dependencies on external libraries, APIs, or other teams

### 4. Phase Breakdown

Decompose the implementation into small phases:

```
## Phase N: Title
- Goal:
- Files to change:
- Estimated commit count:
- Dependencies: Phase X (if any)
```

### 5. User Confirmation

Present the plan and await user approval. Do not begin implementation without explicit approval.

$ARGUMENTS
