# Specification-First Workflow

Enforces a specification-first development workflow.

## Workflow Steps

Follow this order of execution:

### 1. Planning
- Map the scope of impact of the proposed changes
- Create an implementation plan

### 2. Documentation Update
- Update relevant documentation under `docs/` **first**
- Bring specifications, API contracts, and design docs up to date

### 3. Implementation
- Implement code strictly following the updated documentation
- Commit in small, logical units

### 4. Testing
- Add and update tests
- Verify all tests pass

## Key Rules

- **Never begin implementation before updating documentation**
- **Each commit represents a single logical change**
- **Prevent divergence between documentation and code**

## Usage

When this command is invoked, proceed according to the steps above.
Explicitly report the completion of each phase, and obtain user confirmation before advancing to the next phase.

$ARGUMENTS
