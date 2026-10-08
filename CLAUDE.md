# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

This repo is two independent pieces. `zsh-claude-env.plugin.zsh` is an **optional** oh-my-zsh plugin (one file, no build step, no package manager, no tests, no CI) providing only a terminal-title feature and two extension hook points for Claude Code (https://claude.ai/code). The other piece — profile discovery, registration, and switching across multiple `CLAUDE_CONFIG_DIR` directories — is owned entirely by the standalone `ccenv` CLI (`bin/ccenv`/`cenv`/`ccv`, `libexec/ccenv*`), which has zero dependency on this plugin or oh-my-zsh. This file documents only the plugin half; see README.md for `ccenv`.

## Development workflow

There is no build/lint/test tooling. To verify a change, source the file and exercise the functions directly:

```sh
source zsh-claude-env.plugin.zsh
zsh -n zsh-claude-env.plugin.zsh   # syntax-check without executing
```

To check the title-building logic, set `CLAUDE_CONFIG_DIR` to some value and call `_claude_env_build_title` directly after sourcing.

## Architecture

Everything lives in one file, structured top-to-bottom as:

1. **Config variable defaults** (`CLAUDE_ENV_TITLE_HOOKS`) — set with `${VAR:=default}` guards so it's safe to override later in `~/.p10k.zsh`, which sources *after* this plugin.
2. **Internal helpers** (`_claude_env_*`) — name/git-context resolution and title building. These set `REPLY` rather than echoing, specifically to avoid forking a subshell on every prompt render. `_claude_env_git_context` tries a `claude_env_git_context_hook` function first (if defined elsewhere) before falling back to a plain `git` fork.
3. **Title hooks** (`precmd`/`preexec` via `add-zsh-hook`) — registered unconditionally at load time; the `CLAUDE_ENV_TITLE_HOOKS` toggle and the Ghostty shell-integration check (`_claude_env_titles_are_managed`) are both evaluated lazily *inside* the hook body, not at registration time, because that's what makes the config var effective even when set after load.
4. **Baseline capture** — snapshots whatever `CLAUDE_CONFIG_DIR` was already set to when the plugin loaded, into `_claude_env_baseline_label`, a plain global. This plugin doesn't consume it itself; it exists for external consumers (e.g. a p10k segment defined elsewhere) that want to compare the active environment against the one active at shell-init time.

This plugin defines **no prompt-framework-specific display logic** — no p10k segment, no theme integration. Its public surface for anything that wants to display or react to the active environment is: `_claude_env_name` (function), `_claude_env_baseline_label` (variable), and two hook points called only if defined — `claude_env_after_switch` and `claude_env_git_context_hook`. Both hooks are checked via `(( $+functions[name] ))` at call time, not load time, so they're safe to define in a file that sources after this plugin. Note that this plugin's own code never calls `claude_env_after_switch` — that call now lives in `ccenv shell` (see README's "ccenv: profile resolution" section), fired on an explicit switch only (never on a plain `cd`, nor on `ccenv local`/`ccenv global`, both of which just write a file); the hook point and its calling convention are documented here only because this file is where `claude_env_git_context_hook` is actually invoked, and where both hooks' "safe to define after load" contract is implemented. See README's "Extension hooks" and "Powerlevel10k recipe" sections for an example consumer. Don't add prompt-framework-specific code directly into this file — extend via the hooks instead.

### Title-writer race avoidance

`_claude_env_titles_are_managed` checks the `GHOSTTY_SHELL_FEATURES` env var (not `$TERM` or terminal identity) to detect when the terminal already writes its own titles every prompt (Ghostty, and cmux which embeds it). When true, this plugin's title hooks no-op entirely rather than racing a second writer. If extending this check for another terminal, gate on a feature flag the same way — not a terminal-name heuristic.

## Style conventions

- Every module-level block is preceded by a comment explaining *why*, not just what — this codebase leans heavily on comments to document non-obvious ordering constraints (e.g., "must happen before X switches Y (it doesn't), and after Z is defined (it is)"). Preserve that density when editing nearby logic, since the ordering constraints are usually the whole point.
- Functions that set `REPLY` require callers to `local REPLY` first, to avoid clobbering the global `REPLY` from a concurrently-running hook — documented inline where it matters, keep doing so for new `REPLY`-setting helpers.
- Prefer zsh builtins/idioms (glob qualifiers like `(N/)`, `(Ie)` index search, `${(j.:.)array}` joins) over forking subprocesses. `_claude_env_git_context`'s `claude_env_git_context_hook` extension point exists so an external prompt integration can opt this plugin out of its `git` fork entirely, by supplying already-computed data.
- New hook points follow the existing convention: check `(( $+functions[name] ))` at call time (not load time), call if present, fall through to a sane default otherwise. Don't hardcode a specific tool's name or binary anywhere in this file — that's what the hooks are for.
