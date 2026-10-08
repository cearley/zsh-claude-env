# zsh-claude-env

This repo has two independent parts for working with multiple [Claude Code](https://claude.ai/code) `CLAUDE_CONFIG_DIR` environments: the standalone **`ccenv`** CLI (see [ccenv: installation](#ccenv-installation) below), which owns profile discovery, registration, and switching; and an **optional** oh-my-zsh plugin, documented in this section, providing terminal-title integration only.

**If you're new here, start with `ccenv`** — it works standalone, outside oh-my-zsh, and is the thing that actually manages and switches profiles. The plugin below is a nice-to-have on top of it (or on top of plain `CLAUDE_CONFIG_DIR` exports), not a replacement.

**Already using this plugin's old `claude-env`/`claude-<name>` commands?** Those are gone — see [Migrating from `claude-env`](#migrating-from-claude-env) below.

Modeled directly on oh-my-zsh's built-in [`aws` plugin](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/aws) (`asp`/`agp`) — same idea, applied to `CLAUDE_CONFIG_DIR` instead of `AWS_PROFILE`.

Every feature described here works identically with no prompt theme installed. The plugin exposes the active environment's name as a plain global any prompt setup can read — see [Powerlevel10k recipe](#powerlevel10k-recipe) below for an example.

## What it does

Claude Code reads its settings, credentials, and session history from the directory named by `CLAUDE_CONFIG_DIR` (defaulting to `~/.claude`). This **optional** plugin gives you:

- A **terminal title** that reads `✳ <env> · <repo> · <branch> · <job>`, updated on every prompt and command, reflecting whatever `CLAUDE_CONFIG_DIR` currently is.
- Two extension hook points (`claude_env_after_switch`, `claude_env_git_context_hook`) any prompt setup can use — see [Extension hooks](#extension-hooks) below.

That's it — the plugin itself does nothing to set or switch `CLAUDE_CONFIG_DIR`. Pair it with `ccenv` (recommended) for per-directory/per-session profile switching, or just export `CLAUDE_CONFIG_DIR` yourself; the title and hooks work either way.

## Migrating from `claude-env`

Earlier versions of this plugin auto-discovered `~/.claude-*` directories and provided `claude-<name>` wrapper functions and a `claude-env [name]` switcher. All of that has moved to the standalone `ccenv` CLI:

```sh
ccenv add --discover
```

run once, bulk-registers every existing `~/.claude-*` directory (that contains a `.claude.json`) as a `ccenv` profile, named after the directory with its `.claude-` prefix stripped. From there, `ccenv shell <name>` / `ccenv local <name>` / `ccenv global <name>` replace `claude-env <name>`, and `ccenv with <name> claude` replaces `claude-<name>`. See [ccenv: installation](#ccenv-installation) onward below.

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

(Powerlevel10k users have two more config variables — see [Powerlevel10k recipe](#powerlevel10k-recipe) below.)

## Terminal title

On every prompt and command, the window/tab title is set via an OSC 0 escape sequence to `✳ <env> · <repo> · <branch> · <job>`, omitting any segment that isn't available (no git repo, no active environment, no branch). Git context comes from `git rev-parse --show-toplevel` / `git branch --show-current` by default, unless `claude_env_git_context_hook` is defined (see [Extension hooks](#extension-hooks)).

**Ghostty / cmux caveat**: if `$GHOSTTY_SHELL_FEATURES` contains `title` (Ghostty's own shell integration is already writing titles every prompt — this includes cmux, which embeds Ghostty), this plugin registers no title hooks at all, to avoid two writers racing. Other features are unaffected. If you're on a terminal/multiplexer with similar built-in title management not covered by this check, set `CLAUDE_ENV_TITLE_HOOKS=false` to avoid the same race.

## Extension hooks

This plugin defines no prompt-framework-specific code of its own — no p10k segment, no theme integration. Instead it exposes state and two optional hook points any prompt setup can use:

- **`_claude_env_name`** — a function; sets `REPLY` to the active environment's name (empty if none). Callers must declare `local REPLY` first.
- **`_claude_env_baseline_label`** — a variable; the environment name captured when the plugin loaded (empty if `CLAUDE_CONFIG_DIR` was unset at that point).
- **`claude_env_after_switch`** — if you define this function, `ccenv shell <name>`/`ccenv shell --unset` calls it after switching (e.g. to trigger a prompt redraw). `ccenv local`/`ccenv global` and a plain `cd` never call it — see [ccenv: profile resolution](#ccenv-profile-resolution) below. This plugin's own code never calls it. Not called at all if undefined, or if `ccenv` isn't installed or its shell integration isn't active.
- **`claude_env_git_context_hook`** — if you define this function, the terminal-title feature calls it first; it should set `REPLY` to `"<repo>"` or `"<repo> · <branch>"` and return 0 on success, or return non-zero to fall through to the plain `git` fork. Useful to reuse data your prompt framework already computed instead of forking `git` again.

Both hooks are checked at call time, not at plugin-load time, so they're safe to define in a file that sources after this plugin (like `~/.p10k.zsh`).

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

# Extension hooks: makes a ccenv-driven profile change trigger an immediate
# p10k redraw, and reuses gitstatus data for the terminal title instead of
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

One behavior worth knowing if you adopt this recipe: with `ccenv`'s shell integration active and `claude_env_after_switch` defined as above, running `ccenv shell <name>`/`ccenv shell --unset` calls `p10k reload` (only if `p10k` is on `$PATH`), so the segment updates immediately. A `cd` into a directory with a different local profile, or running `ccenv local`/`ccenv global`, updates `CLAUDE_CONFIG_DIR` too but does NOT call `p10k reload` — the segment still catches up at the very next prompt draw regardless, since p10k re-renders its segments every prompt anyway.

## ccenv: installation

`ccenv` (and its aliases `cenv`/`ccv`) is a standalone CLI, independent of oh-my-zsh and of the plugin documented above:

```sh
git clone https://github.com/cearley/zsh-claude-env ~/.ccenv
```

Add the following to your shell startup file (`~/.zshrc` for zsh, `~/.bash_profile` or `~/.bashrc` for bash):

```sh
export PATH="$HOME/.ccenv/bin:$PATH"
eval "$(ccenv init -)"
```

Open a new shell afterward. `eval "$(ccenv init -)"` is what makes `ccenv shell`/`local`/`global` (and the identical `cenv`/`ccv` aliases) actually take effect, and what keeps `CLAUDE_CONFIG_DIR` exported to match the resolved profile on every prompt — without it, `ccenv add`/`list`/`remove`/`profile`/`with` all still work (they don't touch shell state); `ccenv local`/`global` still write their files but warn to stderr since nothing is watching their output; `ccenv shell` fails outright, since it has no file to fall back on (see [ccenv: profile resolution](#ccenv-profile-resolution) below).

If you cloned somewhere other than `~/.ccenv`, adjust the `PATH` line accordingly and set `CCENV_ROOT` to wherever you want profiles themselves stored (defaults to `~/.ccenv`, independent of where the CLI's own code lives).

## ccenv: profile registration

Alongside the oh-my-zsh plugin, this repo also ships `ccenv` (and its aliases `cenv`/`ccv`), a standalone CLI in `bin/`/`libexec/` for managing `CLAUDE_CONFIG_DIR` **profiles** — named symlinks at `$CCENV_ROOT/profiles/<name>` (default `CCENV_ROOT=~/.ccenv`, overridable via the `CCENV_ROOT` environment variable), each pointing at a real config directory.

- **`ccenv add <name> <path>`** — register an existing `CLAUDE_CONFIG_DIR` directory at `<path>` as profile `<name>`. Never copies, moves, or modifies anything at `<path>`. Fails with no change if `<path>` doesn't exist or `<name>` is already registered.
- **`ccenv add <name> --new`** — create a brand-new, empty directory and register it as `<name>`. `ccenv` never invokes `claude` itself — run `ccenv with <name> claude` once afterward to let Claude Code initialize it.
- **`ccenv add --discover`** — bulk-migrate the old convention: registers every `~/.claude-*` directory that contains a `.claude.json` and isn't already registered (under any name), naming each profile after the directory with its `.claude-` prefix stripped. Directories already registered are left untouched.
- **`ccenv remove <name>`** — unregister a profile. Removes only the symlink; the real directory and its contents are never touched.
- **`ccenv list`** — list every registered profile, flagging the active one and which tier (shell/local/global) made it active.

## ccenv: profile resolution

The active profile is resolved using **shell > local > global** precedence — the first tier below that yields a value wins:

1. **shell** — the `CCENV_PROFILE` environment variable, if set and non-empty.
2. **local** — a `.claude-profile` file, searched for starting in `$PWD` and then each parent directory in turn (stopping at `/`); its trimmed content is the profile name.
3. **global** — the trimmed content of `$CCENV_ROOT/profile`, if that file exists.

If none of the three yield a value, no profile is active.

### Commands

- **`ccenv global [<name>|--unset]`** — get, set, or clear the machine-wide default profile (`$CCENV_ROOT/profile`). Setting requires `<name>` to already be a registered profile; an unregistered name leaves the file unchanged and exits non-zero.
- **`ccenv local [<name>|--unset]`** — get, set, or clear the profile for the current directory (`.claude-profile`). `ccenv local <name>` always writes to `$PWD`, never an ancestor; `ccenv local` with no argument prints the local tier's resolved value (walking up from `$PWD`); `ccenv local --unset` removes only `$PWD`'s own file, leaving any ancestor's file untouched.
- **`ccenv shell [<name>|--unset]`** — get, set, or clear the shell-session override (`CCENV_PROFILE`), for the current shell only — never persists to a new shell. Requires shell integration to be active (see [Installation](#ccenv-installation) above): it works by having the `ccenv()` function installed by `ccenv init -` `eval` the output of the internal `ccenv sh-shell` variant in the current shell, since a subprocess can never otherwise alter its parent shell's environment.
- **`ccenv profile`** — prints the currently resolved profile and which tier produced it (e.g. `work (local)`), or reports that no profile is active. Always exits `0` — this is a query, not an error condition.
- **`ccenv with <name> <cmd...>`** — runs `<cmd>` with `CLAUDE_CONFIG_DIR` set to `<name>`'s real directory, for that invocation only. Touches no shell/local/global state and needs no shell integration — it's a plain subprocess `exec`, usable even in a shell where `eval "$(ccenv init -)"` was never run. Fails non-zero without starting `<cmd>` if `<name>` isn't a registered profile.

`global` and `local` (set or `--unset`, not the no-argument get) print a warning to stderr — without failing — if run while shell integration isn't active (`CCENV_LOADED` unset), since the file they write still works regardless. `shell` has no file to fall back on — without integration it fails outright (non-zero exit) rather than warning, since there's nothing a bare subprocess can do to affect its parent shell's environment at all.

## License

MIT — see [LICENSE](LICENSE).
