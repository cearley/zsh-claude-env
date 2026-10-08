# Spec Delta

## Purpose

Discovers which `CLAUDE_CONFIG_DIR` environments exist on the machine and exposes each one as a one-shot `claude-<name>` wrapper function, with no configuration step required.

## ADDED Requirements

### Requirement: Environment discovery at load time
The plugin SHALL glob `$HOME/.claude-*` directories once, at plugin-load time, and SHALL include a directory in the discovered set only if it contains a `.claude.json` file.

#### Scenario: Directory matches naming convention but has no .claude.json
- **WHEN** `$HOME/.claude-notes` exists but contains no `.claude.json`
- **THEN** it is excluded from the discovered environment set and no `claude-notes` function is generated

#### Scenario: Directory has been initialized by Claude Code
- **WHEN** `$HOME/.claude-work/.claude.json` exists
- **THEN** `work` is included in the discovered environment set

#### Scenario: New environment created after shell start
- **WHEN** a new `$HOME/.claude-<name>` directory with `.claude.json` is created after the current shell already sourced the plugin
- **THEN** no `claude-<name>` function appears in that shell until a new shell session re-sources the plugin

### Requirement: Discovered name validation for generated functions
For each discovered environment name, the plugin SHALL generate a `claude-<name>` function only if the name contains exclusively letters, digits, `_`, or `-`. A name that fails this check SHALL be skipped with a warning printed to stderr, and SHALL NOT prevent switching to that environment via `claude-env <name>`.

#### Scenario: Name contains a disallowed character
- **WHEN** a discovered environment name is `"foo bar"` (contains a space)
- **THEN** no `claude-foo bar` function is generated, a warning is printed to stderr naming the skipped environment, and `claude-env "foo bar"` still succeeds

#### Scenario: Name contains only safe characters
- **WHEN** a discovered environment name is `work-2`
- **THEN** a `claude-work-2` function is generated

### Requirement: Per-environment wrapper function behavior
Each generated `claude-<name>` function SHALL run in a subshell, SHALL source `$HOME/.config/claude-env/<name>.env` first if that file exists, SHALL set `CLAUDE_CONFIG_DIR` to `$HOME/.claude-<name>` for that invocation only, and SHALL exec `claude` with all arguments passed through. No part of this SHALL leak into the interactive shell's environment.

#### Scenario: Wrapper invoked with arguments
- **WHEN** the user runs `claude-work --resume`
- **THEN** `claude` is invoked with `CLAUDE_CONFIG_DIR=$HOME/.claude-work` and argument `--resume`, inside a subshell, and the interactive shell's `CLAUDE_CONFIG_DIR` is unchanged afterward

#### Scenario: Per-environment override file present
- **WHEN** `$HOME/.config/claude-env/work.env` exists and `claude-work` is invoked
- **THEN** that file is sourced inside the subshell before `CLAUDE_CONFIG_DIR` is set and `claude` is execed
