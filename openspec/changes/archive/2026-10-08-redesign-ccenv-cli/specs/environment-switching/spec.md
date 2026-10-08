# Spec Delta

## REMOVED Requirements

### Requirement: Print current environment with no argument
**Reason**: `claude-env` is removed entirely in favor of the standalone `ccenv` CLI, which works outside oh-my-zsh and adds per-directory resolution this command never had.
**Migration**: Use `ccenv profile` to see the resolved profile and which tier set it. See `ccenv-resolution`.

### Requirement: Switch to a valid discovered environment
**Reason**: Superseded by `ccenv`'s three explicit precedence tiers, which this plugin-only command had no equivalent of (it only ever offered a single, shell-session-only override).
**Migration**: Use `ccenv shell <name>` for a session-only switch, `ccenv local <name>` for a per-directory default, or `ccenv global <name>` for the machine-wide default. See `ccenv-resolution`.

### Requirement: Reject an unknown environment name
**Reason**: Equivalent validation now lives in `ccenv`'s own setters.
**Migration**: `ccenv shell`/`ccenv local`/`ccenv global` each reject a name that isn't a registered profile the same way. See `ccenv-resolution`.

### Requirement: Invoke the after-switch hook on success
**Reason**: The hook point itself is retained (see the `extension-hooks` delta in this change), but its trigger moves from this now-removed command to `ccenv shell`, its direct successor for an explicit, session-scoped switch.
**Migration**: No action needed if `claude_env_after_switch` is already defined; it now fires on `ccenv shell <name>`/`ccenv shell --unset` once `ccenv` shell integration is active, the same scope `claude-env` had. See `ccenv-resolution`.
