# ccenv-profiles Specification

## Purpose

Lets the user register, inspect, and remove named Claude Code environment profiles — pointers to real `CLAUDE_CONFIG_DIR` directories — independent of where those directories physically live.

## Requirements

### Requirement: Register an existing environment as a profile
`ccenv add <name> <path>` SHALL register `<path>` as a profile named `<name>` by creating a symlink from the profile store to `<path>`, without copying, moving, or modifying anything at `<path>`. It SHALL fail with a non-zero exit status and no changes if `<path>` does not exist, or if `<name>` is already registered.

#### Scenario: Registering an existing directory
- **WHEN** the user runs `ccenv add work ~/.claude-work` and `~/.claude-work` exists
- **THEN** a profile named `work` is registered pointing at `~/.claude-work`, and `~/.claude-work` is unmodified

#### Scenario: Path does not exist
- **WHEN** the user runs `ccenv add work /no/such/dir`
- **THEN** no profile is registered, an error is printed, and the command exits non-zero

#### Scenario: Name already registered
- **WHEN** a profile named `work` is already registered and the user runs `ccenv add work ~/.claude-work-2`
- **THEN** no change is made to the existing `work` profile, an error is printed, and the command exits non-zero

### Requirement: Bootstrap and register a new environment
`ccenv add <name> --new` SHALL create a new, empty directory and register it as a profile named `<name>`. It SHALL NOT invoke `claude` or otherwise attempt to initialize Claude Code's own state in that directory — initializing it (e.g. creating `.claude.json`) is the user's responsibility, performed by running `claude` against the new profile at least once.

#### Scenario: Bootstrapping a brand-new profile
- **WHEN** the user runs `ccenv add staging --new` and no profile named `staging` exists yet
- **THEN** a new, empty directory is created and registered as the `staging` profile, and no `claude` process is started

### Requirement: Bulk-register existing convention-based directories
`ccenv add --discover` SHALL scan `$HOME/.claude-*` directories and register each one that contains a `.claude.json` file and is not already registered, as a profile named after the directory with the `.claude-` prefix removed.

#### Scenario: First run with pre-existing convention directories
- **WHEN** `~/.claude-work/.claude.json` and `~/.claude-personal/.claude.json` both exist and neither is registered
- **THEN** both are registered as profiles named `work` and `personal`, and both are reported as newly registered

#### Scenario: Re-running after some profiles already exist
- **WHEN** `work` is already registered (from any directory) and `~/.claude-personal/.claude.json` exists but is not registered
- **THEN** only `personal` is registered; `work`'s existing registration is left unchanged and reported as already-registered

#### Scenario: Convention directory without Claude Code state
- **WHEN** `~/.claude-notes` exists but contains no `.claude.json`
- **THEN** it is not registered and is reported as not a valid Claude Code directory

### Requirement: Remove a registered profile
`ccenv remove <name>` SHALL unregister the profile named `<name>` without deleting or modifying the real directory it points to. It SHALL fail with a non-zero exit status if `<name>` is not a registered profile.

#### Scenario: Removing a registered profile
- **WHEN** `work` is a registered profile pointing at `~/.claude-work`, and the user runs `ccenv remove work`
- **THEN** `work` is no longer a registered profile, and `~/.claude-work` and its contents are untouched

#### Scenario: Removing an unknown profile
- **WHEN** no profile named `staging` is registered and the user runs `ccenv remove staging`
- **THEN** no change is made, an error is printed, and the command exits non-zero

### Requirement: List registered profiles
`ccenv list` SHALL print every registered profile name. For each one, it SHALL indicate whether it is the currently active profile and, if so, which precedence tier (shell, local, or global) made it active.

#### Scenario: Multiple profiles, one active via local
- **WHEN** `work` and `personal` are both registered, and `work` is the currently active profile because of a local `.claude-profile` file
- **THEN** `ccenv list` prints both names, marking `work` as active and attributing that to the local tier

#### Scenario: No profiles registered
- **WHEN** no profiles are registered
- **THEN** `ccenv list` prints an empty result and exits zero
