# Proposal

## Why

`zsh-claude-env.plugin.zsh` only works inside oh-my-zsh, has no notion of a per-directory default, and its `claude-env` switcher is cumbersome to type and complete. A standalone CLI, modeled on `jenv`, gives shell-independent `add`/`list`/`global`/`local`/`shell` profile management with jenv's shell>local>global precedence — without the baggage of jenv's PATH-shimming, which an empirical test (shadowing `claude` with a decoy script ahead of the real binary on `PATH`) proved doesn't work here: the user's `claude()` wrapper delegates to `specstory run claude`, and specstory resolves the agent binary through its own fixed discovery logic, not a `PATH` search — confirmed via its debug log reporting the real binary's path even with the decoy earlier on `PATH`. Precedence therefore has to be enforced by exporting `CLAUDE_CONFIG_DIR` directly, not by intercepting the `claude` command.

## What Changes

- Add a new standalone CLI, `ccenv` ("Claude Code env"), installed independently of oh-my-zsh via `git clone` + `PATH` + `eval "$(ccenv init -)"`, mirroring jenv's own install flow. It has zero dependency on `zsh-claude-env.plugin.zsh` or oh-my-zsh.
- `ccenv` manages named **profiles** (not "versions" — jenv's term, intentionally not reused) at `~/.ccenv/profiles/<name>`, each a symlink to a real `CLAUDE_CONFIG_DIR` directory wherever it lives.
- `ccenv` resolves the active profile via shell (`CCENV_PROFILE`) > local (`.claude-profile`, found by walking up from `$PWD`) > global (`~/.ccenv/profile`) precedence, and its own shell integration (`ccenv init -`) exports `CLAUDE_CONFIG_DIR` from that resolution every prompt — so any command that eventually execs the real `claude` binary (directly, through `specstory`, through `cmux`, or otherwise) inherits the right value, regardless of how that caller finds the binary.
- `ccenv with <name> <cmd...>` runs a command with a specific profile active for one invocation, replacing the plugin's generated `claude-<name>` wrapper functions (and their character-set validation guard) with a single generic command.
- `ccenv` is also reachable as `cenv` and `ccv` — shorter aliases for day-to-day typing, both full equivalents accepting the exact same subcommands and arguments, not restricted subsets.
- **BREAKING**: `zsh-claude-env.plugin.zsh` drops `~/.claude-*` auto-discovery, the generated `claude-<name>` functions, and the `claude-env` switcher entirely. The plugin becomes a thin, optional layer providing only the terminal-title feature and the two extension hook points; it still works with zero `ccenv` installed (it just reads whatever `CLAUDE_CONFIG_DIR` happens to be set to, same as today), but something else — normally `ccenv` — now has to be the thing keeping that variable populated for per-directory/per-session switching to do anything.
- The `claude_env_after_switch` hook point is now invoked by `ccenv shell` on an explicit switch, rather than by the now-removed `claude-env` switcher. `ccenv local`/`ccenv global` and a plain `cd` never fire it — they only ever write a file or change directory, picked up automatically without notification.
- The repo is restructured jenv-style (`bin/ccenv` -> `libexec/ccenv`, one `libexec/ccenv-<command>` file per subcommand) alongside the existing, slimmed plugin file at the repo root. One repo, two independent install paths, documented separately in the README.

## Capabilities

### New Capabilities
- `ccenv-profiles`: Registering, listing, and removing named Claude Code environment profiles (`add` from an existing directory, `add --new` to bootstrap one, `add --discover` to bulk-migrate existing `~/.claude-*` directories, `remove`, `list`).
- `ccenv-resolution`: Resolving the active profile from shell/local/global precedence, keeping `CLAUDE_CONFIG_DIR` in sync automatically (directory changes, a plain `local`/`global` write) and immediately for an explicit `shell`/`local` switch, reporting the resolved profile and its origin (`ccenv profile`), and invoking `claude_env_after_switch` on an explicit `shell` switch.
- `ccenv-shell-integration`: `ccenv init -` shell setup (the eval-wrapper function needed for state-mutating subcommands to affect the live shell, matching jenv's `jenv()` function trick) and `ccenv with <name> <cmd...>` for one-shot profile overrides.

### Modified Capabilities
- `environment-discovery`: All three requirements (load-time `~/.claude-*` discovery, generated-function name validation, per-environment wrapper function behavior) are removed from the plugin; superseded by `ccenv-profiles`.
- `environment-switching`: All four requirements (print-current, switch, reject-unknown, invoke-after-switch-hook) are removed from the plugin; superseded by `ccenv-resolution`'s `shell`/`local`/`global` setters and `ccenv profile`.
- `extension-hooks`: The "After-switch hook point" requirement is modified — it's no longer tied to a `claude-env <name>` call (that command no longer exists); it's now invoked by `ccenv`'s resolution step whenever the resolved profile changes. The other three requirements (`_claude_env_name`, `_claude_env_baseline_label`, the git-context hook) are unchanged.

`terminal-title` is unaffected — title rendering still just reads `CLAUDE_CONFIG_DIR` and forks `git` (or the context hook) exactly as today, regardless of what now keeps that variable populated.

## Impact

- New: `bin/ccenv`, `libexec/ccenv`, `libexec/ccenv-add`, `libexec/ccenv-list`, `libexec/ccenv-remove`, `libexec/ccenv-global`, `libexec/ccenv-local`, `libexec/ccenv-shell`, `libexec/ccenv-profile`, `libexec/ccenv-with`, `libexec/ccenv-init`, plus the `sh-*` eval-target variants for state-mutating subcommands.
- Modified: `zsh-claude-env.plugin.zsh` (discovery loop, generated functions, and `claude-env` removed; title/hook code kept), `README.md` (two install paths), `CLAUDE.md` (architecture doc update — handled in tasks, not specs).
- Out of scope for this change: chezmoi's `claude_default` static export (a natural follow-up to replace with `ccenv global`, in a different repo, handled separately); any changes to `specstory`, `cmux`, or the user's own `claude()` wrapper function.
