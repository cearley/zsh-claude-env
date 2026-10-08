# zsh-claude-env

An oh-my-zsh plugin for working with multiple [Claude Code](https://claude.ai/code) config directories in the same shell — per-environment wrapper functions, a session switcher, and terminal-title integration.

Modeled directly on oh-my-zsh's built-in [`aws` plugin](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/aws) (`asp`/`agp`) — same idea, applied to `CLAUDE_CONFIG_DIR` instead of `AWS_PROFILE`.

Every feature described here works identically with no prompt theme installed. The plugin exposes the active environment's name as a plain global any prompt setup can read — see [Powerlevel10k recipe](#powerlevel10k-recipe) below for an example.

## What it does

Claude Code reads its settings, credentials, and session history from the directory named by `CLAUDE_CONFIG_DIR` (defaulting to `~/.claude`). If you keep several — say `~/.claude-work` and `~/.claude-personal` — this plugin gives you:

- **`claude-<name>`** — a function per discovered environment (e.g. `claude-work`) that runs `claude` with `CLAUDE_CONFIG_DIR` pinned to that one environment, for that one invocation only.
- **`claude-env [name]`** — switch the active environment for the rest of the shell session (with no args, prints the current one).
- A **terminal title** that reads `✳ <env> · <repo> · <branch> · <job>`, updated on every prompt and command.

Environments are **discovered automatically** by globbing `$HOME/.claude-*` directories when the plugin loads, filtered to ones that actually contain a `.claude.json` (the file Claude Code itself writes on first invocation) — a stray directory that merely matches the naming convention is ignored. There's no list to configure. Add a new `~/.claude-<name>` directory, invoke `claude` against it once, open a new shell, and `claude-<name>` just appears.

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

| Variable | Type | Default | Purpose |
|---|---|---|---|
| `CLAUDE_ENV_TITLE_HOOKS` | `true`/`false` | `true` | Toggles the terminal-title `precmd`/`preexec` hooks. Set `CLAUDE_ENV_TITLE_HOOKS=false` to disable them. |

Read lazily (at prompt-render time, not at plugin-load time), so it's safe to set anywhere in your `~/.zshrc`, even before `zsh-claude-env` loads.

The `$HOME/.claude-<name>` directory convention and the `~/.config/claude-env/<name>.env` per-environment override file (sourced before `claude` runs, if present) are intentionally not configurable.

(Powerlevel10k users have two more config variables — see [Powerlevel10k recipe](#powerlevel10k-recipe) below.)

## Terminal title

On every prompt and command, the window/tab title is set via an OSC 0 escape sequence to `✳ <env> · <repo> · <branch> · <job>`, omitting any segment that isn't available (no git repo, no active environment, no branch). Git context comes from `git rev-parse --show-toplevel` / `git branch --show-current` by default, unless `claude_env_git_context_hook` is defined (see [Extension hooks](#extension-hooks)).

**Ghostty / cmux caveat**: if `$GHOSTTY_SHELL_FEATURES` contains `title` (Ghostty's own shell integration is already writing titles every prompt — this includes cmux, which embeds Ghostty), this plugin registers no title hooks at all, to avoid two writers racing. Other features are unaffected. If you're on a terminal/multiplexer with similar built-in title management not covered by this check, set `CLAUDE_ENV_TITLE_HOOKS=false` to avoid the same race.

## Extension hooks

This plugin defines no prompt-framework-specific code of its own — no p10k segment, no theme integration. Instead it exposes state and two optional hook points any prompt setup can use:

- **`_claude_env_name`** — a function; sets `REPLY` to the active environment's name (empty if none). Callers must declare `local REPLY` first.
- **`_claude_env_baseline_label`** — a variable; the environment name captured when the plugin loaded (empty if `CLAUDE_CONFIG_DIR` was unset at that point).
- **`claude_env_after_switch`** — if you define this function, `claude-env <name>` calls it after switching (e.g. to trigger a prompt redraw). Not called at all if undefined.
- **`claude_env_git_context_hook`** — if you define this function, the terminal-title feature calls it first; it should set `REPLY` to `"<repo>"` or `"<repo> · <branch>"` and return 0 on success, or return non-zero to fall through to the plain `git` fork. Useful to reuse data your prompt framework already computed instead of forking `git` again.

Both hooks are checked at call time, not at plugin-load time, so they're safe to define in a file that sources after this plugin (like `~/.p10k.zsh`).

## Known limitation

A brand-new environment has no `claude-<name>()` function until its `$HOME/.claude-<name>` directory exists on disk, contains a `.claude.json`, *and* a new shell session re-globs for it. To bootstrap one:

```sh
CLAUDE_CONFIG_DIR=$HOME/.claude-<name> claude
```

Claude Code creates the directory (and `.claude.json` inside it) on first run; open a new shell afterward and `claude-<name>` will be defined.

## Powerlevel10k recipe

Below is the author's own Powerlevel10k integration, built entirely from the globals and hooks in [Extension hooks](#extension-hooks) above — copy it into your own `~/.p10k.zsh` and adapt as you like (colors, icon, show/hide behavior, or a completely different prompt framework altogether):

```sh
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    ...
    claude_env
    ...
)

# Optional config for the recipe below — read lazily at prompt-render time.
typeset -gA CLAUDE_ENV_COLORS=(work 33 personal 76 bedrock 208)  # name -> p10k color; unlisted names render grey (244)
CLAUDE_ENV_SHOW_DEFAULT=false  # hide the segment while on the baseline env captured at plugin-load time

prompt_claude_env() {
  local color REPLY
  _claude_env_name
  [ -n "$REPLY" ] || return
  local label="$REPLY"

  if [ "$CLAUDE_ENV_SHOW_DEFAULT" != true ] \
    && [ -n "$_claude_env_baseline_label" ] \
    && [ "$label" = "$_claude_env_baseline_label" ]; then
    return
  fi

  color="${CLAUDE_ENV_COLORS[$label]:-244}"
  p10k segment -f $color -i '󰛄' -t "${label//\%/%%}"
}

instant_prompt_claude_env() {
  prompt_claude_env
}

# Extension hooks: makes `claude-env <name>` trigger an immediate p10k
# redraw, and reuses gitstatus data for the terminal title instead of
# forking git again.
claude_env_after_switch() {
  command -v p10k >/dev/null 2>&1 && p10k reload
}

claude_env_git_context_hook() {
  [ -n "$VCS_STATUS_WORKDIR" ] || return 1
  REPLY="${VCS_STATUS_WORKDIR:t}${VCS_STATUS_LOCAL_BRANCH:+ · $VCS_STATUS_LOCAL_BRANCH}"
}
```

| Variable | Type | Default | Purpose |
|---|---|---|---|
| `CLAUDE_ENV_COLORS` | associative array | `()` | p10k color per environment name. Names not listed render in color 244 (grey). |
| `CLAUDE_ENV_SHOW_DEFAULT` | `true`/`false` | `true` | When `false`, hides the segment while the active environment equals `_claude_env_baseline_label` (empty when `CLAUDE_CONFIG_DIR` was unset at plugin-load time, in which case this has no effect). |

These are plain variables read by the recipe above, not anything this plugin declares or defaults itself — set them wherever you define `prompt_claude_env`.

One plugin behavior worth knowing if you adopt this recipe: `claude-env` calls `p10k reload` after switching environments (only if `p10k` is on `$PATH`), so the segment updates immediately without a new prompt draw.

## License

MIT — see [LICENSE](LICENSE).
