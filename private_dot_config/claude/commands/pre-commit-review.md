# Pre-Commit Review

Executes local pre-commit code review, focusing on security vulnerabilities and code quality.

## Steps

### 1. Collect Changes

Fetch staged changes using `git diff --cached`.
If no changes are staged, target unstaged changes via `git diff`.

### 2. Security Check

Review changes across the following criteria:

#### Secrets and Credentials
- Hardcoded passwords, API keys, or tokens
- Committing `.env` or credential files
- Leaking private keys or certificates

#### Injection Vulnerabilities
- SQL injection (queries without parameterized placeholders)
- Command injection (executing shell commands with unescaped user input)
- XSS (rendering unsanitized user output)
- Path traversal (using raw user input in file paths)

#### Other Security Concerns
- Insecure cryptography (e.g. MD5, SHA1 for passwords)
- Overly permissive CORS configurations
- Lingering debug flags/modes intended for development
- Known vulnerabilities in newly introduced dependencies (check lockfile diffs)

### 3. Code Quality Check

#### Error Handling
- Empty catch blocks
- Silent error suppression (swallowing exceptions)
- Inappropriate or masking fallbacks

#### Code Health
- Unused imports / variables
- Lingering TODO / FIXME / HACK comments (confirm intentionality)
- Magic numbers
- Overly complex conditional branching

### 4. Output Report

```
## Pre-Commit Review

### Security Issues
- [CRITICAL] file:line - description
- [WARNING] file:line - description

### Code Quality
- [ISSUE] file:line - description
- [SUGGESTION] file:line - description

### Summary
- Security: N critical, M warnings
- Quality: N issues, M suggestions
- Verdict: PASS / NEEDS ATTENTION / BLOCK
```

If there are `CRITICAL` security issues, return `BLOCK` and strongly advise against committing.

$ARGUMENTS
