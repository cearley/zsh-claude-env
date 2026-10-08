# extension-hooks Specification

## Purpose
Exposes a stable, minimal surface — two state values and two optional hook points — that lets external configuration (such as a prompt theme) read or extend this plugin's behavior without the plugin itself depending on any specific prompt framework.

## Requirements

### Requirement: Active environment name as plain state
`_claude_env_name` SHALL be a function that sets `REPLY` to the active environment's name (derived from `CLAUDE_CONFIG_DIR`), or to an empty string if none is active. It SHALL NOT echo output, and callers SHALL be required to declare `local REPLY` first to avoid clobbering a concurrently-running hook's use of the global `REPLY`.

#### Scenario: Environment active
- **WHEN** `CLAUDE_CONFIG_DIR=$HOME/.claude-work` and a caller with `local REPLY` invokes `_claude_env_name`
- **THEN** `REPLY` is set to `work`

#### Scenario: No environment active
- **WHEN** `CLAUDE_CONFIG_DIR` is unset and a caller with `local REPLY` invokes `_claude_env_name`
- **THEN** `REPLY` is set to an empty string

### Requirement: Baseline label captured at load time
`_claude_env_baseline_label` SHALL be a global variable set once, when the plugin loads, to the active environment name at that moment (empty if `CLAUDE_CONFIG_DIR` was unset at load time). The plugin itself SHALL NOT read or act on this value; it exists only for external consumers to compare against the currently active environment.

#### Scenario: Environment active at load time
- **WHEN** `CLAUDE_CONFIG_DIR=$HOME/.claude-personal` is already set when the plugin sources
- **THEN** `_claude_env_baseline_label` is set to `personal` and never changes afterward

#### Scenario: No environment active at load time
- **WHEN** `CLAUDE_CONFIG_DIR` is unset when the plugin sources
- **THEN** `_claude_env_baseline_label` is set to an empty string

### Requirement: After-switch hook point
If a `claude_env_after_switch` function is defined, it SHALL be called with no arguments whenever `ccenv shell` (set or unset) performs an explicit switch. This plugin itself no longer triggers it — the trigger is the standalone `ccenv` CLI (see the `ccenv-resolution` capability). Its presence SHALL be checked at call time, not at plugin-load time, so it is safe to define in a file that sources after this plugin.

#### Scenario: Hook defined after plugin load
- **WHEN** `claude_env_after_switch` is defined later (e.g. in `~/.p10k.zsh`, which sources after this plugin) and the user later runs `ccenv shell <name>`
- **THEN** the hook is called

#### Scenario: No call on a directory change or a local/global write
- **WHEN** `claude_env_after_switch` is defined and either a `cd` or `ccenv local`/`ccenv global` changes the resolved profile with no explicit `ccenv shell` run
- **THEN** `claude_env_after_switch` is not called — the automatic, directory-triggered side of `ccenv` only keeps `CLAUDE_CONFIG_DIR` correct, it doesn't notify anything

#### Scenario: ccenv not installed
- **WHEN** `ccenv` is not installed or its shell integration is not active
- **THEN** nothing in this plugin calls `claude_env_after_switch`; `CLAUDE_CONFIG_DIR` simply remains whatever it was last set to, same as before this hook point existed

### Requirement: Git context hook point
If a `claude_env_git_context_hook` function is defined, the plugin's internal git-context resolution SHALL try it first. The hook SHALL set `REPLY` to `"<repo>"` or `"<repo> · <branch>"` and return a zero exit status on success, in which case the plugin SHALL use that value as-is and SHALL NOT fork `git`. A non-zero return SHALL cause the plugin to fall back to its own `git rev-parse --show-toplevel` / `git branch --show-current` resolution.

#### Scenario: Hook succeeds
- **WHEN** `claude_env_git_context_hook` is defined, sets `REPLY="myrepo · main"`, and returns 0
- **THEN** the terminal title's repo/branch segment uses `myrepo · main` and no `git` process is forked for it

#### Scenario: Hook declines
- **WHEN** `claude_env_git_context_hook` is defined but returns non-zero
- **THEN** the plugin falls back to resolving repo/branch via `git` directly

#### Scenario: Hook not defined
- **WHEN** no `claude_env_git_context_hook` function exists
- **THEN** the plugin resolves repo/branch via `git` directly, as if the hook had declined
