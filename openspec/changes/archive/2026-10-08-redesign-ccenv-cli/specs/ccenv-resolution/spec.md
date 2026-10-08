# Spec Delta

## Purpose

Determines which registered profile is active at any moment, using shell > local (per-directory) > global precedence, and keeps `CLAUDE_CONFIG_DIR` exported to match — so any command that eventually runs the real `claude` binary inherits the right value regardless of how that command locates the binary.

## ADDED Requirements

### Requirement: Shell, local, and global precedence tiers
The active profile SHALL be resolved, in order, from: (1) a shell-level override set for the current session, (2) a local `.claude-profile` file found by searching the current directory and each ancestor directory in turn, (3) a global default. The first tier that yields a value SHALL be used; if none do, no profile is active.

#### Scenario: Shell override takes priority
- **WHEN** a shell-level override is set to `personal` and a local `.claude-profile` file containing `work` exists in the current directory
- **THEN** the resolved profile is `personal`

#### Scenario: Local file found in an ancestor directory
- **WHEN** no shell-level override is set, `$PWD` is `~/code/myproject/src`, and `.claude-profile` containing `work` exists at `~/code/myproject` but nowhere closer
- **THEN** the resolved profile is `work`

#### Scenario: Falls through to global
- **WHEN** no shell-level override is set and no `.claude-profile` file is found in `$PWD` or any ancestor
- **THEN** the resolved profile is the global default, if one is set

#### Scenario: Nothing set at any tier
- **WHEN** no shell-level override, no local file, and no global default exist
- **THEN** no profile is active

### Requirement: Get and set the global default profile
`ccenv global <name>` SHALL set `<name>` as the global default, persisting across shell sessions, and SHALL affect the calling shell immediately if shell integration is active and no shell or local override outranks it. `ccenv global` with no argument SHALL print the current global default, or indicate that none is set. `ccenv global --unset` SHALL clear it. Setting a name that is not a registered profile SHALL fail with a non-zero exit status and no change.

#### Scenario: Setting the global default
- **WHEN** `work` is a registered profile, no shell or local override is active, and the user runs `ccenv global work`
- **THEN** the global default is set to `work`, `CLAUDE_CONFIG_DIR` reflects it immediately in the current shell, and it remains the default in subsequently started shells too

#### Scenario: Setting an unregistered name
- **WHEN** `staging` is not a registered profile and the user runs `ccenv global staging`
- **THEN** the global default is unchanged, an error is printed, and the command exits non-zero

### Requirement: Get and set the local (per-directory) profile
`ccenv local <name>` SHALL write a `.claude-profile` file containing `<name>` in the current directory. `ccenv local` with no argument SHALL print the local profile in effect for the current directory, or indicate that none is set. `ccenv local --unset` SHALL remove `.claude-profile` from the current directory only. Setting a name that is not a registered profile SHALL fail with a non-zero exit status and no file written.

#### Scenario: Setting a local profile
- **WHEN** `work` is a registered profile and the user runs `ccenv local work` in `~/code/myproject`
- **THEN** `~/code/myproject/.claude-profile` is created containing `work`

#### Scenario: Unsetting removes only the current directory's file
- **WHEN** `.claude-profile` exists in both `~/code/myproject` and its ancestor `~/code`, and the user runs `ccenv local --unset` from `~/code/myproject`
- **THEN** `~/code/myproject/.claude-profile` is removed and `~/code/.claude-profile` is untouched

### Requirement: Get and set the shell-session profile
`ccenv shell <name>` SHALL set `<name>` as an override for the current shell session only, taking priority over local and global. `ccenv shell` with no argument SHALL print the current shell-session override, or indicate that none is set. `ccenv shell --unset` SHALL clear it. Setting a name that is not a registered profile SHALL fail with a non-zero exit status and no change. The override SHALL NOT persist to new shell sessions.

#### Scenario: Setting a shell override
- **WHEN** `personal` is a registered profile and the user runs `ccenv shell personal`
- **THEN** the resolved profile for the rest of this shell session is `personal`, regardless of any local file or global default

#### Scenario: Override does not persist to a new shell
- **WHEN** a shell override of `personal` is set in one terminal session
- **THEN** a newly started shell session resolves its profile from local/global precedence alone, with no shell-level override active

### Requirement: Report the resolved profile and its origin
`ccenv profile` SHALL print the currently resolved profile name (per the precedence requirement above), or indicate that none is active, along with which tier (shell, local, or global) produced it.

#### Scenario: Resolved via local tier
- **WHEN** the resolved profile is `work`, determined by a local `.claude-profile` file
- **THEN** `ccenv profile` reports `work` and attributes it to the local tier

#### Scenario: Nothing active
- **WHEN** no tier yields a profile
- **THEN** `ccenv profile` reports that no profile is active

### Requirement: Keep CLAUDE_CONFIG_DIR exported to match resolution automatically
Once shell integration is active (see `ccenv-shell-integration`), `CLAUDE_CONFIG_DIR` SHALL be re-exported to match the resolved profile no later than the next prompt, with no `ccenv` command run, whenever a plain `cd` changes the resolved profile OR a `ccenv local`/`ccenv global` file write changes it. (`ccenv shell` updates it immediately as part of running instead, per its own requirement above — the only case that needs to.)

#### Scenario: Changing directories changes the exported value
- **WHEN** the shell has no override active, `~/code/a` has a local profile of `work` and `~/code/b` has a local profile of `personal`, and the user runs `cd` from `~/code/a` to `~/code/b`
- **THEN** `CLAUDE_CONFIG_DIR` is exported to `personal`'s real directory no later than the next prompt, with no other command run (a shell that can react to the directory change itself, rather than only at the next prompt, MAY do so sooner)

#### Scenario: A plain local or global write is picked up the same way
- **WHEN** the shell has no override active and the user runs `ccenv local work` (or `ccenv global work`) in the current directory
- **THEN** `CLAUDE_CONFIG_DIR` is exported to `work`'s real directory no later than the next prompt

### Requirement: Invoke the after-switch hook on an explicit shell-level switch
If a `claude_env_after_switch` function is defined, `ccenv shell`/`ccenv shell --unset` (not the no-argument get) SHALL call it with no arguments after updating `CLAUDE_CONFIG_DIR`. Nothing else calls it: not a plain `cd`, and not `ccenv local`/`ccenv global` — both only ever write a file and are picked up by the requirement above, same as a `cd`, with no notification. Its presence SHALL be checked at call time, not at shell-integration-load time.

#### Scenario: Hook fires on an explicit shell-level switch
- **WHEN** `claude_env_after_switch` is defined and the user runs `ccenv shell personal`
- **THEN** `claude_env_after_switch` is called once, after `CLAUDE_CONFIG_DIR` reflects `personal`

#### Scenario: No call on a directory change or a local/global write
- **WHEN** `claude_env_after_switch` is defined and either `cd`-ing between two directories with different local profiles, or running `ccenv local work`/`ccenv global work`, changes the resolved profile
- **THEN** `claude_env_after_switch` is not called

#### Scenario: Hook not defined
- **WHEN** no `claude_env_after_switch` function exists and the user runs `ccenv shell personal`
- **THEN** the switch completes with no error and nothing extra is called
