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

1. **Config variable defaults** (`CLAUDE_ENV_COLORS`, `CLAUDE_ENV_SHOW_DEFAULT`, `CLAUDE_ENV_TITLE_HOOKS`) — set with `${VAR:=default}` guards so they're safe to override later in `~/.p10k.zsh`, which sources *after* this plugin.
2. **Internal helpers** (`_claude_env_*`) — name/git-context resolution and title building. These set `REPLY` rather than echoing, specifically to avoid forking a subshell on every prompt render.
3. **Title hooks** (`precmd`/`preexec` via `add-zsh-hook`) — registered unconditionally at load time; the `CLAUDE_ENV_TITLE_HOOKS` toggle and the Ghostty shell-integration check (`_claude_env_titles_are_managed`) are both evaluated lazily *inside* the hook body, not at registration time, because that's what makes the config var effective even when set after load.
4. **Baseline capture** — snapshots whatever `CLAUDE_CONFIG_DIR` was already set to when the plugin loaded, used later by `CLAUDE_ENV_SHOW_DEFAULT` to hide the p10k segment when on that baseline (mirrors `POWERLEVEL9K_NVM_SHOW_SYSTEM`).
5. **Environment discovery** — globs `$HOME/.claude-*` once, at load time, into `_claude_env_names`. This is the plugin's core mechanism: everything downstream (wrapper functions, `claude-env` validation, `SESSION_INDEX_PROJECTS`) is generated from this array. A newly created `~/.claude-<name>` directory won't appear until a new shell re-sources the plugin (documented as a known limitation, not a bug to fix reactively).
6. **Per-environment wrapper functions** — `claude-<name>` and `claude-<name>-spec` are generated dynamically via `functions[name]="..."` string assignment, not `eval` or static `function` blocks, because the set of names is only known at runtime. Each wrapper runs in a `( ... )` subshell so the per-env `.env` file sourcing and `CLAUDE_CONFIG_DIR` assignment never leak into the interactive shell.
7. **SpecStory wrappers** (`claude-spec`, `codex-spec`, `gemini-spec`) — plain functions (not aliases) so they resolve even with alias expansion off.
8. **`SESSION_INDEX_PROJECTS`** — colon-joined `projects/` paths across every discovered env plus the default `~/.claude`, exported for external tools.
9. **`claude-env [name]`** — the session switcher. Validates `$1` against `_claude_env_names` using the zsh index-search idiom `${_claude_env_names[(Ie)$1]}` (reverse, exact match); a nonzero result means found.
10. **Powerlevel10k segment** (`prompt_claude_env` / `instant_prompt_claude_env`) — safe no-op if p10k isn't installed; must stay registered as `claude_env` in `POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS` by the user for it to render.

### Non-configurable by design

The `$HOME/.claude-<name>` directory convention, the `~/.config/claude-env/<name>.env` per-environment override file, and the p10k segment icon are intentionally hardcoded — not exposed as config vars. Don't add config surface for these without a specific reason; the README and file header both call out this is a deliberate scope decision for "a two-function plugin."

### Title-writer race avoidance

`_claude_env_titles_are_managed` checks the `GHOSTTY_SHELL_FEATURES` env var (not `$TERM` or terminal identity) to detect when the terminal already writes its own titles every prompt (Ghostty, and cmux which embeds it). When true, this plugin's title hooks no-op entirely rather than racing a second writer. If extending this check for another terminal, gate on a feature flag the same way — not a terminal-name heuristic.

## Style conventions

- Every module-level block is preceded by a comment explaining *why*, not just what — this codebase leans heavily on comments to document non-obvious ordering constraints (e.g., "must happen before X switches Y (it doesn't), and after Z is defined (it is)"). Preserve that density when editing nearby logic, since the ordering constraints are usually the whole point.
- Functions that set `REPLY` require callers to `local REPLY` first, to avoid clobbering the global `REPLY` from a concurrently-running hook — documented inline where it matters, keep doing so for new `REPLY`-setting helpers.
- Prefer zsh builtins/idioms (glob qualifiers like `(N/)`, `(Ie)` index search, `${(j.:.)array}` joins) over forking subprocesses, consistent with the existing "no extra `git` fork" optimization in `_claude_env_git_context`.
