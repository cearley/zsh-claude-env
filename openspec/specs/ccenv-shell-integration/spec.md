# ccenv-shell-integration Specification

## Purpose

Wires `ccenv` into an interactive shell session — making state-mutating subcommands actually affect the running shell, keeping resolution live, and providing a one-shot way to run a command under a specific profile without changing any persistent state.

## Requirements

### Requirement: Shell integration setup
`ccenv init -` SHALL print shell code that, when evaluated (e.g. via `eval "$(ccenv init -)"`), prepends `ccenv`'s bin directory to `PATH`, defines a shell function intercepting state-mutating subcommands (see the next requirement), resolves and exports `CLAUDE_CONFIG_DIR` immediately, and registers the mechanism keeping it synchronized with directory changes afterward (see `ccenv-resolution`). It SHALL support both `bash` and `zsh`.

#### Scenario: Evaluating init output wires up the shell
- **WHEN** a user adds `eval "$(ccenv init -)"` to their shell startup file and opens a new shell
- **THEN** `CLAUDE_CONFIG_DIR` is already correct before the first prompt, directory-change tracking is active, and state-mutating subcommands affect that shell's environment

#### Scenario: Unsupported shell
- **WHEN** `ccenv init -` is run from a shell other than `bash` or `zsh`
- **THEN** it reports that the shell is unsupported and makes no changes

### Requirement: State-mutating subcommands affect the calling shell
`ccenv shell`, `ccenv local`, and `ccenv global` (set or `--unset`) SHALL each take effect in the calling interactive shell immediately when shell integration is active, including re-exporting `CLAUDE_CONFIG_DIR` to match, without requiring the user to manually export or unset anything.

#### Scenario: Shell-level set takes effect immediately
- **WHEN** shell integration is active and the user runs `ccenv shell personal`
- **THEN** the current shell's resolved profile is `personal` and `CLAUDE_CONFIG_DIR` reflects it, immediately after the command returns

#### Scenario: Local-level set takes effect immediately
- **WHEN** shell integration is active and the user runs `ccenv local work` in the current directory
- **THEN** `CLAUDE_CONFIG_DIR` reflects `work`'s real directory immediately after the command returns, with no `cd` or other command needed

### Requirement: One-shot profile override for a single command
`ccenv with <name> <cmd...>` SHALL run `<cmd>` with `<name>`'s real directory exported as `CLAUDE_CONFIG_DIR` for that invocation only. It SHALL NOT alter the shell-level, local, or global profile state, and SHALL NOT require shell integration to be active. It SHALL fail with a non-zero exit status and SHALL NOT run `<cmd>` if `<name>` is not a registered profile.

#### Scenario: Running a command under a specific profile
- **WHEN** `work` is a registered profile and the user runs `ccenv with work claude --resume`
- **THEN** `claude --resume` runs with `CLAUDE_CONFIG_DIR` set to `work`'s real directory, and the calling shell's own resolved profile (shell/local/global) is unchanged afterward

#### Scenario: Unknown profile name
- **WHEN** `staging` is not a registered profile and the user runs `ccenv with staging claude`
- **THEN** `claude` is not started, an error is printed, and the command exits non-zero

### Requirement: Short command aliases
`ccenv` SHALL also be reachable as `cenv` and `ccv`. Both SHALL accept the exact same subcommands and arguments as `ccenv` and SHALL behave identically to invoking `ccenv` directly, including requiring shell integration to be active for any subcommand that needs to affect the calling shell.

#### Scenario: Alias behaves identically for a read-only command
- **WHEN** the user runs `cenv list` or `ccv list`
- **THEN** the output is identical to running `ccenv list`

#### Scenario: Alias behaves identically for a state-mutating command
- **WHEN** shell integration is active and the user runs `cenv shell work` (or `ccv shell work`)
- **THEN** the current shell's resolved profile becomes `work`, exactly as `ccenv shell work` would do
