# Spec Delta

## REMOVED Requirements

### Requirement: Environment discovery at load time
**Reason**: Plugin-side auto-discovery is replaced by the standalone `ccenv` CLI's explicit profile registration, which works without oh-my-zsh and without requiring a new shell session to pick up a new directory.
**Migration**: Use `ccenv add --discover` once to bulk-register existing `~/.claude-*` directories, or `ccenv add <name> <path>` for one at a time. See `ccenv-profiles`.

### Requirement: Discovered name validation for generated functions
**Reason**: This requirement only existed to guard dynamically-generated `claude-<name>` shell functions, which are removed (see `environment-switching`'s removal and `ccenv-shell-integration`'s `ccenv with`).
**Migration**: `ccenv add <name> <path>` takes an explicit name with no shell-function-safety character restriction, since it never generates a function body from it.

### Requirement: Per-environment wrapper function behavior
**Reason**: Superseded by a single generic command instead of one generated function per profile.
**Migration**: Use `ccenv with <name> <cmd...>` (see `ccenv-shell-integration`). The per-environment override file at `$HOME/.config/claude-env/<name>.env` is not carried forward; equivalent per-profile setup, if needed, should be arranged via the profile's own directory contents instead.
