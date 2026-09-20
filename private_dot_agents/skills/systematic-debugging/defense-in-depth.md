# Defense-in-Depth Validation

## Overview

When fixing a bug caused by invalid data, adding validation at a single location may seem sufficient. However, that single check can be bypassed by an alternate code path, refactoring, or a mock.

**Core**: Validate at every layer data traverses. Make bugs structurally impossible.

## Why Multiple Layers?

Single-point validation "fixes the bug." Multiple layers "make the bug impossible."

Each layer catches different failure modes:

- Entrypoint validation catches the vast majority of invalid inputs
- Business logic validation catches domain edge cases
- Environment guards protect against context-specific hazards
- Debug logging captures details when other layers fail to catch an anomaly

## Four Layers

### Layer 1: Entrypoint Validation

**Purpose**: Reject clearly invalid input at API boundaries

```typescript
function createProject(name: string, workingDirectory: string) {
  if (!workingDirectory || workingDirectory.trim() === '') {
    throw new Error('workingDirectory cannot be empty');
  }
  if (!existsSync(workingDirectory)) {
    throw new Error(`workingDirectory does not exist: ${workingDirectory}`);
  }
  if (!statSync(workingDirectory).isDirectory()) {
    throw new Error(`workingDirectory is not a directory: ${workingDirectory}`);
  }
}
```

### Layer 2: Business Logic Validation

**Purpose**: Ensure data is meaningful in the context of this specific operation

```typescript
function initializeWorkspace(projectDir: string, sessionId: string) {
  if (!projectDir) {
    throw new Error('projectDir required for workspace initialization');
  }
}
```

### Layer 3: Environment Guards

**Purpose**: Prevent dangerous actions in specific execution contexts

```typescript
async function gitInit(directory: string) {
  // During tests, refuse git init outside temp directory
  if (process.env.NODE_ENV === 'test') {
    const normalized = normalize(resolve(directory));
    const tmpDir = normalize(resolve(tmpdir()));

    if (!normalized.startsWith(tmpDir)) {
      throw new Error(
        `Refusing git init outside temp dir during tests: ${directory}`
      );
    }
  }
}
```

### Layer 4: Debug Instrumentation

**Purpose**: Retain context for post-mortem analysis

```typescript
async function gitInit(directory: string) {
  const stack = new Error().stack;
  logger.debug('About to git init', {
    directory,
    cwd: process.cwd(),
    stack,
  });
}
```

## How to Apply

When a bug is discovered:

1. **Trace the Data Flow** — Where was the invalid value born, and where is it consumed?
2. **Identify All Transit Points** — Enumerate every point through which the data passes.
3. **Add Validation at Each Layer** — Entrypoint, business logic, environment, debug.
4. **Test Each Layer** — Bypass layer 1 to ensure layer 2 reliably catches the error.

## Real Example

Bug: Empty `projectDir` triggered `git init` in the source repository root.

**Data Flow**:
1. Test setup -> Empty string
2. `Project.create(name, '')`
3. `WorkspaceManager.createWorkspace('')`
4. `git init` ran in `process.cwd()`

**Added 4 Layers**:
- Layer 1: `Project.create()` asserts non-empty, existing, writable directory
- Layer 2: `WorkspaceManager` asserts `projectDir` is non-empty
- Layer 3: `WorktreeManager` refuses `git init` outside tmpdir during tests
- Layer 4: Recorded stack traces before invoking `git init`

**Result**: All tests pass, and the bug cannot be reproduced through any entrypoint.

## Summary

All four layers were necessary. During verification, each layer caught edge cases missed by the others:

- An alternate execution path bypassed entrypoint validation
- A mock bypassed business logic validation
- Platform-specific quirks required environment guards
- Debug logs pinpointed structural misuse

**Do not stop at one validation check.** Place guards across every layer.
