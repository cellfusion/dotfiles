# Rust Development Assistant

Skill supporting Rust development workflows.

## Provided Features

### Code Quality Checks
Runs the following commands to verify code quality:
- `cargo fmt --check` - Formatting check
- `cargo clippy -- -D warnings` - Lint warning check
- `cargo test` - Test execution

### Development Workflow

1. **Build Check**: `cargo build`
2. **Apply Formatting**: `cargo fmt`
3. **Fix Lints**: `cargo clippy --fix --allow-dirty`
4. **Run Tests**: `cargo test`

## Best Practices

- Prefer `?` operator or `expect()` over raw `unwrap()`
- Use `thiserror` or `anyhow` for error types
- Add `#[derive(Debug, Clone)]` where appropriate
- Add doc comments `///` to public APIs

## Usage

Provide the task as arguments. Examples:
- `/rust-dev create a new module`
- `/rust-dev improve error handling`
- `/rust-dev add tests`

$ARGUMENTS
