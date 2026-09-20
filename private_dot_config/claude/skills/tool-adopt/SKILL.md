---
name: tool-adopt
description: >-
  Standard workflow for adopting new CLI tools (research, configuration, chezmoi management,
  documentation). Activates automatically when the user mentions keywords such as "adopt tool",
  "new tool", "brew install", "add configuration", "tool-adopt", "install", etc.
  Can also be invoked manually with /tool-adopt.
---

# Tool Adoption Skill

Automates the standard workflow for adopting and integrating new CLI tools.

## Usage

### Workflow

1. **Research**: Investigate tool features, config file locations, and primary options.
2. **Install Check**: Verify installation status with `brew info <tool>` or `which <tool>`.
3. **Configuration**: Create configuration files within chezmoi source directory.
4. **Shell Integration**: Add aliases or wrappers if needed.
5. **Documentation**: Append an entry to the corresponding table in `private_dot_config/docs/tools.md`.
6. **Apply Reminder**: Advise the user to run `chezmoi apply` (never run automatically).

### Configuration File Placement

Follow chezmoi path conventions:

| Actual Path | chezmoi Source Path |
|---|---|
| `~/.config/tool/config.toml` | `private_dot_config/tool/config.toml` |
| `~/.tool.conf` | `dot_tool.conf` |
| `~/.local/bin/tool-wrapper` | `private_dot_local/bin/executable_tool-wrapper` |

### Shell Integration

When adding aliases or settings to `.zshrc`:
- chezmoi source: `private_dot_config/zsh/dot_zshrc`
- Inspect existing layout and insert at an appropriate position.

### Herdr Integration

When adding keybindings to Herdr:
- chezmoi source: `private_dot_config/herdr/config.toml`
- Inspect existing layout and insert at an appropriate position.
- If modifying keybindings, update `private_dot_config/docs/keybindings.md` in the same commit.

### Television Cable Channel Integration

When creating custom channels for television:
- Add channel definitions under `private_dot_config/television/cable/`.
- Use existing channels (such as `custom-herdr-sessions.toml`) as reference.

## Auto-Activation Guidelines

Automatically activate this skill in situations such as:

- The user discusses installing or configuring a new CLI tool.
- A `brew install` command was executed or is about to be executed.
- The user mentions "I want to try this tool" or "How should I configure this?".

Automatic actions:
- Research official tool documentation via WebSearch.
- Inspect existing configuration patterns across the chezmoi source tree.

## Important Notes

- **Never execute `chezmoi apply` automatically** — explicit user approval is strictly required.
- Edit only inside the chezmoi source directory (`~/.local/share/chezmoi/`).
- Ensure changes to `.zshrc` or `herdr/config.toml` do not break existing structure.
- Executable scripts in chezmoi require the `executable_` prefix.

## Recording in Tool Inventory

Once tool adoption is complete, record it in `private_dot_config/docs/tools.md`:

- Add a row to the table matching the installation route (core / dev-tools / macOS-only, etc.).
- Add to the manifest: `.chezmoitemplates/install/brewfile` for Homebrew,
  `private_dot_config/mise/config.toml` for mise,
  `private_dot_config/install/npm-globals.txt` for npm,
  `private_dot_config/install/cargo-globals.txt` for cargo.
