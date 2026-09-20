# Verify

Validates project health across toolchains in a single command.

## Arguments

- `quick` — Build and typecheck only
- `full` — Run all checks (default)
- `pre-commit` — Pre-commit checks (build, type, lint, security)
- `pre-pr` — Full check before creating a PR (full + console.log audit)

## Steps

Execute the following steps in sequence. Certain steps are skipped depending on arguments.

### 1. Project Detection

Identify the project root and detect toolchains:
- `package.json` -> Node.js/TypeScript project
- `Cargo.toml` -> Rust project
- If both exist, target both

### 2. Build Check (All Modes)

- **Node.js**: `npm run build` or `bun run build` (inspect package.json scripts)
- **Rust**: `cargo build`

If build errors occur, stop here and report errors.

### 3. Type Check (All Modes)

- **TypeScript**: `npx tsc --noEmit`
- **Rust**: Covered during build step

### 4. Lint (full, pre-commit, pre-pr)

- **Node.js**: `npx biome check .` or `npx eslint .` (according to project config)
- **Rust**: `cargo clippy -- -D warnings`

### 5. Run Tests (full, pre-pr)

- **Node.js**: `npm test` or `bun test`
- **Rust**: `cargo test`

Report any test failures.

### 6. console.log / dbg! Audit (pre-pr)

Search source code for unintended debug statements:
- `console.log`, `console.debug`, `console.warn` (outside test files)
- `dbg!`, `println!` (outside test modules)

### 7. Git Status

Display `git status` and `git diff --stat` to summarize current modifications.

## Output

Summarize results of each step in this format:

```
## Verify Results (mode)
- [ ] Build: PASS/FAIL
- [ ] Type Check: PASS/FAIL
- [ ] Lint: PASS/FAIL (N issues)
- [ ] Tests: PASS/FAIL (N passed, M failed)
- [ ] Debug Statements: N found
- [ ] Git Status: clean/N files changed
```

$ARGUMENTS
