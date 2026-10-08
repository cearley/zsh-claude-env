# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An oh-my-zsh plugin, entirely contained in `zsh-claude-env.plugin.zsh` (one file, no build step, no package manager, no tests, no CI). It manages multiple Claude Code `CLAUDE_CONFIG_DIR` environments (e.g. `~/.claude-work`, `~/.claude-personal`) from a single shell, modeled directly on oh-my-zsh's built-in `aws` plugin (`asp`/`agp`).

## Development workflow

There is no build/lint/test tooling. To verify a change, source the file and exercise the functions directly:

```sh
source zsh-claude-env.plugin.zsh
claude-env                 # should print current env or "(none)"
zsh -n zsh-claude-env.plugin.zsh   # syntax-check without executing
```

Since environment discovery happens at plugin-load time (globbing `$HOME/.claude-*`), test discovery-related changes by creating a scratch `~/.claude-<name>` directory and opening a fresh shell (or re-sourcing the plugin) rather than trying to fake it in-process.

## Architecture

Everything lives in one file, structured top-to-bottom as:

1. **Config variable defaults** (`CLAUDE_ENV_TITLE_HOOKS`) — set with `${VAR:=default}` guards so it's safe to override later in `~/.p10k.zsh`, which sources *after* this plugin.
2. **Internal helpers** (`_claude_env_*`) — name/git-context resolution and title building. These set `REPLY` rather than echoing, specifically to avoid forking a subshell on every prompt render. `_claude_env_git_context` tries a `claude_env_git_context_hook` function first (if defined elsewhere) before falling back to a plain `git` fork.
3. **Title hooks** (`precmd`/`preexec` via `add-zsh-hook`) — registered unconditionally at load time; the `CLAUDE_ENV_TITLE_HOOKS` toggle and the Ghostty shell-integration check (`_claude_env_titles_are_managed`) are both evaluated lazily *inside* the hook body, not at registration time, because that's what makes the config var effective even when set after load.
4. **Baseline capture** — snapshots whatever `CLAUDE_CONFIG_DIR` was already set to when the plugin loaded, into `_claude_env_baseline_label`, a plain global. This plugin doesn't consume it itself; it exists for external consumers (e.g. a p10k segment defined elsewhere) that want to compare the active environment against the one active at shell-init time.
5. **Environment discovery** — globs `$HOME/.claude-*` once, at load time, filtered to entries containing `.claude.json` — the marker Claude Code itself writes on first invocation against a `CLAUDE_CONFIG_DIR` (verified empirically; `settings.json` is NOT a safe marker, since Claude Code does not create it unprompted) — into `_claude_env_names`. This is the plugin's core mechanism: everything downstream (wrapper functions, `claude-env` validation) is generated from this array. A newly created `~/.claude-<name>` directory won't appear until `claude` has been invoked against it at least once (writing `.claude.json`) and a new shell re-sources the plugin (documented as a known limitation, not a bug to fix reactively).
6. **Per-environment wrapper functions** — `claude-<name>` is generated dynamically via `functions[name]="..."` string assignment, not `eval` or static `function` blocks, because the set of names is only known at runtime. Each wrapper runs in a `( ... )` subshell so the per-env `.env` file sourcing and `CLAUDE_CONFIG_DIR` assignment never leak into the interactive shell.
7. **`claude-env [name]`** — the session switcher. Validates `$1` against `_claude_env_names` using the zsh index-search idiom `${_claude_env_names[(Ie)$1]}` (reverse, exact match); a nonzero result means found. Calls a `claude_env_after_switch` function, if defined elsewhere, after switching.

This plugin defines **no prompt-framework-specific display logic** — no p10k segment, no theme integration. Its public surface for anything that wants to display or react to the active environment is: `_claude_env_name` (function), `_claude_env_baseline_label` (variable), and two hook points called only if defined — `claude_env_after_switch` and `claude_env_git_context_hook`. Both hooks are checked via `(( $+functions[name] ))` at call time, not load time, so they're safe to define in a file that sources after this plugin. See README's "Extension hooks" and "Powerlevel10k recipe" sections for an example consumer. Don't add prompt-framework-specific code directly into this file — extend via the hooks instead.

### Non-configurable by design

The `$HOME/.claude-<name>` directory convention and the `~/.config/claude-env/<name>.env` per-environment override file are intentionally hardcoded — not exposed as config vars. Don't add config surface for these without a specific reason; the README and file header both call out this is a deliberate scope decision for "a two-function plugin."

### Title-writer race avoidance

`_claude_env_titles_are_managed` checks the `GHOSTTY_SHELL_FEATURES` env var (not `$TERM` or terminal identity) to detect when the terminal already writes its own titles every prompt (Ghostty, and cmux which embeds it). When true, this plugin's title hooks no-op entirely rather than racing a second writer. If extending this check for another terminal, gate on a feature flag the same way — not a terminal-name heuristic.

## Style conventions

- Every module-level block is preceded by a comment explaining *why*, not just what — this codebase leans heavily on comments to document non-obvious ordering constraints (e.g., "must happen before X switches Y (it doesn't), and after Z is defined (it is)"). Preserve that density when editing nearby logic, since the ordering constraints are usually the whole point.
- Functions that set `REPLY` require callers to `local REPLY` first, to avoid clobbering the global `REPLY` from a concurrently-running hook — documented inline where it matters, keep doing so for new `REPLY`-setting helpers.
- Prefer zsh builtins/idioms (glob qualifiers like `(N/)`, `(Ie)` index search, `${(j.:.)array}` joins) over forking subprocesses. `_claude_env_git_context`'s `claude_env_git_context_hook` extension point exists so an external prompt integration can opt this plugin out of its `git` fork entirely, by supplying already-computed data.
- New hook points follow the existing convention: check `(( $+functions[name] ))` at call time (not load time), call if present, fall through to a sane default otherwise. Don't hardcode a specific tool's name or binary anywhere in this file — that's what the hooks are for.
