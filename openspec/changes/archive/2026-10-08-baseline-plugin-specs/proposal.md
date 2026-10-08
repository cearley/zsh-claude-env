# Proposal

## Why

This project adopted OpenSpec after the plugin's core behavior already shipped (environment discovery, wrapper functions, session switching, terminal titles — see README). There are no specs yet, so there's no behavior contract to check future changes against. This change writes baseline specs that describe the plugin exactly as it already behaves, so OpenSpec has a starting point to diff against going forward.

## What Changes

- Document the existing, shipped behavior as specs — no code changes.
- Four capabilities, matching the plugin's real feature boundaries:
  - Environment discovery (globbing `$HOME/.claude-*`, filtering by `.claude.json`, generating `claude-<name>` wrapper functions)
  - Environment switching (`claude-env [name]`, the `claude_env_after_switch` hook)
  - Terminal title (precmd/preexec hooks, title format, `CLAUDE_ENV_TITLE_HOOKS` toggle, Ghostty/cmux race avoidance)
  - Extension hooks (`_claude_env_name`, `_claude_env_baseline_label`, `claude_env_git_context_hook` — the public surface for external prompt integrations)

## Capabilities

### New Capabilities
- `environment-discovery`: Discovers `~/.claude-*` directories at plugin load and generates a `claude-<name>` wrapper function per valid environment.
- `environment-switching`: `claude-env [name]` reads/validates/switches the active environment for the rest of the shell session.
- `terminal-title`: precmd/preexec hooks render `✳ <env> · <repo> · <branch> · <job>` in the terminal title, toggleable and race-aware.
- `extension-hooks`: Public hook points (`claude_env_after_switch`, `claude_env_git_context_hook`) and state (`_claude_env_name`, `_claude_env_baseline_label`) that let external configs (e.g. a prompt theme) integrate without this plugin depending on them.

### Modified Capabilities
(none — this is the first set of specs for this project)

## Impact

- No code changes. `zsh-claude-env.plugin.zsh` and `README.md` are the source of truth this change transcribes from.
- Adds `openspec/specs/environment-discovery/spec.md`, `openspec/specs/environment-switching/spec.md`, `openspec/specs/terminal-title/spec.md`, `openspec/specs/extension-hooks/spec.md` once archived.
