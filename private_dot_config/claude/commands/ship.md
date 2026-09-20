# Ship

Executes review -> commit -> Linear update in a single streamlined step.

## Arguments

`$ARGUMENTS` — Optional flags

- `--no-linear`: Skip Linear update
- `--no-review`: Skip review and verify (urgent cases only)

## Steps

### 1. Inspect Changes

```bash
git status
git diff --stat
git diff --cached --stat
```

If there are no changes, report "No changes to commit" and exit.

### 2. Review (Skipped with `--no-review`)

Execute the following in sequence:

1. Read target files to check for security issues and code quality concerns.
2. Run checks equivalent to `/verify quick` based on detected project toolchain (build + typecheck).

If issues are found, report them and ask the user whether to fix or proceed.

### 3. Commit

1. Review all modifications via `git diff` and `git diff --cached`.
2. Craft a commit message following Conventional Commits syntax.
3. Stage relevant files (`git add` explicitly specifying target files).
4. Execute commit.

### 4. Update Linear (Skipped with `--no-linear`)

Detect Linear issue ID from branch name or commit message:

- Branch name pattern: `feat/PROJ-123-description`, `fix/PROJ-456`
- Commit message pattern: `PROJ-123` format

When detected:
1. Check current status of the issue using `mcp__claude_ai_Linear__get_issue`.
2. Post a comment based on commit content (`mcp__claude_ai_Linear__save_comment`).
3. Ask the user if a status change is appropriate (do not change status automatically).

When not detected:
- Skip silently and report.

### 5. Summary

```
## Ship Complete
- Commit: <hash> <message>
- Linear: <PROJ-123 updated/no issue detected/skipped>
```

$ARGUMENTS
