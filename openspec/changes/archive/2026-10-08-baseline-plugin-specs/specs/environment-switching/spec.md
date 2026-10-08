# Spec Delta

## Purpose

Lets the user switch the active Claude Code environment for the rest of the current shell session, independent of whether a one-shot `claude-<name>` wrapper exists for it.

## ADDED Requirements

### Requirement: Print current environment with no argument
Calling `claude-env` with no argument SHALL print the active environment's name derived from `CLAUDE_CONFIG_DIR`, or `(none)` if no environment is active.

#### Scenario: An environment is active
- **WHEN** `CLAUDE_CONFIG_DIR=$HOME/.claude-work` and the user runs `claude-env`
- **THEN** `work` is printed

#### Scenario: No environment is active
- **WHEN** `CLAUDE_CONFIG_DIR` is unset and the user runs `claude-env`
- **THEN** `(none)` is printed

### Requirement: Switch to a valid discovered environment
Calling `claude-env <name>` SHALL switch the session by exporting `CLAUDE_CONFIG_DIR=$HOME/.claude-<name>` only if `<name>` exactly matches one of the environment names discovered at load time. The switch SHALL persist for the rest of the shell session (not just one command).

#### Scenario: Valid name
- **WHEN** `work` is in the discovered environment set and the user runs `claude-env work`
- **THEN** `CLAUDE_CONFIG_DIR` is exported as `$HOME/.claude-work` and remains set for subsequent commands in that shell

### Requirement: Reject an unknown environment name
Calling `claude-env <name>` with a name that is not in the discovered environment set SHALL leave `CLAUDE_CONFIG_DIR` unchanged, SHALL print a usage message listing the valid names to stderr, and SHALL return a non-zero exit status.

#### Scenario: Unknown name
- **WHEN** `staging` is not in the discovered environment set and the user runs `claude-env staging`
- **THEN** `CLAUDE_CONFIG_DIR` is left unchanged, a `Usage: claude-env [...]` message listing the known names is printed to stderr, and the command exits non-zero

### Requirement: Invoke the after-switch hook on success
If a `claude_env_after_switch` function is defined at the time of a successful switch, `claude-env <name>` SHALL call it immediately after exporting `CLAUDE_CONFIG_DIR`. If no such function is defined, this SHALL be a no-op.

#### Scenario: Hook defined
- **WHEN** `claude_env_after_switch` is defined and `claude-env work` succeeds
- **THEN** `claude_env_after_switch` is called after `CLAUDE_CONFIG_DIR` is exported

#### Scenario: Hook not defined
- **WHEN** no `claude_env_after_switch` function exists and `claude-env work` succeeds
- **THEN** the switch completes with no error and nothing extra is called
