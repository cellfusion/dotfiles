# Refactor Clean

Detects dead code and performs safe cleanup.

## Arguments

- `scan` — Detection only (default)
- `clean` — Automatically deletes items categorized as SAFE after detection
- `report` — Emits a detailed report

## Steps

### 1. Project Detection

Identify the project toolchain:
- **TypeScript/JavaScript**: Check for existence of `package.json`
- **Rust**: Check for existence of `Cargo.toml`

### 2. Tool-Based Detection

Utilize existing tools if available:
- **TypeScript**: `npx knip` or `npx ts-prune` (if installed)
- **Rust**: `cargo +nightly udeps` (if installed)

If tools are not installed, fall back to manual analysis.

### 3. Manual Analysis

Detect dead code using grep and file globbing:

#### Exported but Unused
- Functions, types, and constants that are exported but not imported anywhere
- Items marked `pub` but not referenced within the crate (Rust)

#### Dead Code
- Unused variables and functions (inspect compiler warnings)
- Commented-out code blocks
- Empty files and modules

#### Dependencies
- Unused dependencies in `package.json`
- Unused dependencies in `Cargo.toml`

### 4. Classification

Classify findings into 3 risk tiers:

- **SAFE** — Confirmed unused. Zero references, no side effects.
- **CAUTION** — Likely unused, but potential dynamic references or reflection exist.
- **DANGER** — Entrypoints, plugin registrations, initialization code with side effects, etc.

### 5. Report

```
## Refactor Clean Report

### SAFE (auto-removable)
- file:line - description

### CAUTION (manual review needed)
- file:line - description

### DANGER (do not auto-remove)
- file:line - description

### Summary
- SAFE: N items
- CAUTION: N items
- DANGER: N items
```

In `clean` mode, delete only the SAFE category items, and propose each deletion as an individual commit.

$ARGUMENTS
