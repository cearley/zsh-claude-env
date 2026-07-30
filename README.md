# zsh-claude-env

An oh-my-zsh plugin for working with multiple [Claude Code](https://claude.ai/code) config directories in the same shell — per-environment wrapper functions, a session switcher, terminal-title integration, and a [Powerlevel10k](https://github.com/romkatv/powerlevel10k) prompt segment.

Modeled directly on oh-my-zsh's built-in [`aws` plugin](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/aws) (`asp`/`agp`) — same idea, applied to `CLAUDE_CONFIG_DIR` instead of `AWS_PROFILE`.

## What it does

Claude Code reads its settings, credentials, and session history from the directory named by `CLAUDE_CONFIG_DIR` (defaulting to `~/.claude`). If you keep several — say `~/.claude-work` and `~/.claude-personal` — this plugin gives you:

- **`claude-<name>`** — a function per discovered environment (e.g. `claude-work`) that runs `claude` with `CLAUDE_CONFIG_DIR` pinned to that one environment, for that one invocation only.
- **`claude-env [name]`** — switch the active environment for the rest of the shell session (with no args, prints the current one). Calls `p10k reload` so the prompt segment updates immediately.
- **`claude-spec` / `codex-spec` / `gemini-spec` / `claude-<name>-spec`** — wrapper functions around [SpecStory](https://specstory.com/specstory-cli)'s `specstory run <cli> --no-cloud-sync`.
- A **terminal title** that reads `✳ <env> · <repo> · <branch> · <job>`, updated on every prompt and command.
- A **Powerlevel10k segment** (`claude_env`) showing the active environment, color-coded.
- **`SESSION_INDEX_PROJECTS`** — a colon-joined list of every environment's `projects/` directory, for tools that want to search across all of them.

Environments are **discovered automatically** by globbing `$HOME/.claude-*` directories when the plugin loads — there's no list to configure. Add a new `~/.claude-<name>` directory, open a new shell, and `claude-<name>` just appears.

## Install

```sh
git clone https://github.com/cearley/zsh-claude-env ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-claude-env
```

Add `zsh-claude-env` to the `plugins=(...)` array in your `~/.zshrc`:

```sh
plugins=(
    ...
    zsh-claude-env
)
```

## Config

Everything below is optional and read lazily (at prompt-render time, not at plugin-load time) — safe to set in `~/.p10k.zsh` even though it's sourced *after* this plugin loads.

| Variable | Type | Default | Purpose |
|---|---|---|---|
| `CLAUDE_ENV_COLORS` | associative array | `()` | p10k color per environment name, e.g. `typeset -gA CLAUDE_ENV_COLORS=(work 33 personal 76)`. Names not listed render in color 244 (grey). |
| `CLAUDE_ENV_SHOW_DEFAULT` | `true`/`false` | `true` | When `false`, hides the p10k segment while the active environment equals whatever `CLAUDE_CONFIG_DIR` was already set to when *this plugin* loaded (its baseline) — mirrors `POWERLEVEL9K_NVM_SHOW_SYSTEM`. There is no `CLAUDE_ENV_DEFAULT` variable: export `CLAUDE_CONFIG_DIR` before `plugins=(...)` sources this plugin if you want a baseline, and the plugin captures it itself. |
| `CLAUDE_ENV_TITLE_HOOKS` | `true`/`false` | `true` | Toggles the terminal-title `precmd`/`preexec` hooks, independent of everything else. |

Example `~/.zshrc`:

```sh
plugins=(
    ...
    zsh-claude-env
)

source "$ZSH"/oh-my-zsh.sh

# ~/.p10k.zsh, sourced later, is a fine place for these too:
typeset -gA CLAUDE_ENV_COLORS=(work 33 personal 76 bedrock 208)
CLAUDE_ENV_SHOW_DEFAULT=false
```

The `$HOME/.claude-<name>` directory convention and the `~/.config/claude-env/<name>.env` per-environment override file (sourced before `claude` runs, if present) are intentionally not configurable.

## Powerlevel10k segment

Add `claude_env` to `POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS` in your `~/.p10k.zsh`:

```sh
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    ...
    claude_env
    ...
)
```

No `POWERLEVEL9K_CLAUDE_ENV_*` variables exist — color and show/hide behavior are controlled entirely by `CLAUDE_ENV_COLORS`/`CLAUDE_ENV_SHOW_DEFAULT` above.

## Terminal title

On every prompt and command, the window/tab title is set via an OSC 0 escape sequence to `✳ <env> · <repo> · <branch> · <job>`, omitting any segment that isn't available (no git repo, no active environment, no branch). Git context is read from Powerlevel10k's already-computed gitstatus data when available (no extra `git` fork); falls back to `git rev-parse`/`git branch --show-current` otherwise.

**Ghostty / cmux caveat**: if `$GHOSTTY_SHELL_FEATURES` contains `title` (Ghostty's own shell integration is already writing titles every prompt — this includes cmux, which embeds Ghostty), this plugin registers no title hooks at all, to avoid two writers racing. The `claude_env` p10k segment and `claude-env` command are unaffected. If you're on a terminal/multiplexer with similar built-in title management not covered by this check, set `CLAUDE_ENV_TITLE_HOOKS=false` to avoid the same race.

## Known limitation

A brand-new environment has no `claude-<name>()` function until its `$HOME/.claude-<name>` directory exists on disk *and* a new shell session re-globs for it. To bootstrap one:

```sh
CLAUDE_CONFIG_DIR=$HOME/.claude-<name> claude
```

Claude Code will create the directory on first run; open a new shell afterward and `claude-<name>` will be defined.

## License

MIT — see [LICENSE](LICENSE).
