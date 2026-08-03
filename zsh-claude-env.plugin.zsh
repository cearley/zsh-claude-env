# zsh-claude-env — multi-environment wrapper functions, session switcher,
# terminal-title integration, and a Powerlevel10k segment for Claude Code
# (https://claude.ai/code). Modeled on oh-my-zsh's built-in `aws` plugin
# (`asp`/`asr`): https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/aws
#
# Environments are discovered by globbing $HOME/.claude-* directories at
# load time — there is nothing to configure to make wrapper functions or
# the switcher appear. Only display preferences for the p10k segment are
# configurable, via the variables below.
#
# ------------------------------------------------------------------------
# Config variables (all optional; set anywhere, read lazily at prompt-render
# time — safe to set in ~/.p10k.zsh even though it's sourced after this
# plugin loads)
# ------------------------------------------------------------------------
#   CLAUDE_ENV_COLORS        Associative array of name -> p10k color number, e.g.
#                            typeset -gA CLAUDE_ENV_COLORS=(work 33 personal 76 bedrock 208)
#                            Names not present here render in color 244 (grey).
#
#   CLAUDE_ENV_SHOW_DEFAULT  true|false, default true. When false, the p10k
#                            segment is hidden while the active environment
#                            equals whatever CLAUDE_CONFIG_DIR was already
#                            set to at the moment THIS PLUGIN loaded (its
#                            baseline) — mirrors POWERLEVEL9K_NVM_SHOW_SYSTEM
#                            / the convention most p10k tool segments use:
#                            only show state that differs from baseline.
#                            There is no CLAUDE_ENV_DEFAULT variable — if you
#                            want a baseline, export CLAUDE_CONFIG_DIR before
#                            this plugin loads (i.e. before `plugins=(...)`
#                            sources it), and the plugin captures it itself.
#
#   CLAUDE_ENV_TITLE_HOOKS   true|false, default true. Toggles the OSC-0
#                            terminal-title feature (precmd/preexec hooks
#                            below), independent of everything else.
#
# The claude config dir path convention ($HOME/.claude-<name>), the
# per-env local override file ($HOME/.config/claude-env/<name>.env), and the
# segment icon (nf-md-asterisk, U+F06C4) are intentionally NOT configurable —
# not worth the surface area for a two-function plugin. Open an issue if you
# disagree.
#
# Limitation: a brand-new environment has no claude-<name>() function until
# its $HOME/.claude-<name> directory exists on disk and a new shell session
# re-globs. Bootstrap one with `CLAUDE_CONFIG_DIR=$HOME/.claude-<name> claude`
# once, then open a new shell.

(( ${+CLAUDE_ENV_COLORS} )) || typeset -gA CLAUDE_ENV_COLORS=()
: ${CLAUDE_ENV_SHOW_DEFAULT:=true}
: ${CLAUDE_ENV_TITLE_HOOKS:=true}

# ------------------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------------------

# Sets REPLY to the active environment name (e.g. "personal"), empty if none.
# Callers MUST declare `local REPLY`: zsh's `read` builtin also stores into
# the global REPLY by default, so an undeclared caller could clobber it from
# a concurrently-running hook. Sets a variable rather than echoing to avoid
# a subshell fork on every prompt.
_claude_env_name() {
  REPLY="${CLAUDE_CONFIG_DIR##*/}"
  REPLY="${REPLY#.}"
  REPLY="${REPLY#claude-}"
}

# Sets REPLY to "<repo>" or "<repo> · <branch>", empty when not in a work tree.
_claude_env_git_context() {
  local repo branch
  REPLY=""
  if [ -n "${VCS_STATUS_WORKDIR}" ]; then
    # Reuse gitstatus data already computed by p10k's vcs segment — no git fork.
    repo="${VCS_STATUS_WORKDIR##*/}"
    branch="${VCS_STATUS_LOCAL_BRANCH}"
  else
    repo=$(git rev-parse --show-toplevel 2>/dev/null) || return
    repo="${repo##*/}"
    branch=$(git branch --show-current 2>/dev/null)
  fi
  REPLY="$repo${branch:+ · $branch}"
}

# Emits the terminal title: ✳ <label> · <repo> · <branch> · <job>, ordered
# general -> specific, omitting any unavailable segment. The ${title:+...}
# guard adds a separator only when something precedes it, making a
# leading/trailing/doubled " · " impossible. OSC 0 sets the icon name as
# well as the window title (OSC 2 sets only the latter), and is what
# Claude Code itself emits — matching it means shell-set and Claude-set
# titles read as one family.
_claude_env_build_title() {
  local job="$1" title="" REPLY
  _claude_env_name
  [ -n "$REPLY" ] && title="✳ $REPLY"
  _claude_env_git_context
  [ -n "$REPLY" ] && title="${title:+$title · }$REPLY"
  [ -n "$job" ] && title="${title:+$title · }$job"
  printf '\033]0;%s\007' "$title"
}

# True when the terminal runs its own shell integration that writes a title
# every prompt (Ghostty does; cmux embeds Ghostty). In that case the title
# hooks below no-op, rather than racing a second writer whose winner depends
# on hook ordering. Tests the feature flag, not the terminal identity, so
# disabling that integration hands title management back to this plugin —
# do not reduce this to a $TERM check.
_claude_env_titles_are_managed() {
  case "${GHOSTTY_SHELL_FEATURES-}" in
    *title*) return 0 ;;
    *) return 1 ;;
  esac
}

# CLAUDE_ENV_TITLE_HOOKS and the Ghostty check are both evaluated here, at
# invocation time, rather than at hook-registration time above — this is
# what makes it safe to set CLAUDE_ENV_TITLE_HOOKS in ~/.p10k.zsh, which is
# sourced after this plugin (and its hook registration) has already run.
_claude_env_precmd() {
  [ "$CLAUDE_ENV_TITLE_HOOKS" = true ] || return
  _claude_env_titles_are_managed && return
  _claude_env_build_title "zsh"
}

_claude_env_preexec() {
  [ "$CLAUDE_ENV_TITLE_HOOKS" = true ] || return
  _claude_env_titles_are_managed && return
  _claude_env_build_title "${1%% *}"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _claude_env_precmd
add-zsh-hook preexec _claude_env_preexec

# ------------------------------------------------------------------------
# Capture the environment active when this plugin loaded, as the implicit
# baseline for CLAUDE_ENV_SHOW_DEFAULT. Must happen before anything below
# switches CLAUDE_CONFIG_DIR (it doesn't), and after _claude_env_name is
# defined (it is).
#
# Wrapped in an anonymous function so `local REPLY` always has a real
# function scope to bind to. This file's top level isn't itself inside a
# function when sourced directly (the standalone install path in the
# README) — only oh-my-zsh's own loader happens to source plugins from
# inside a function. Without this wrapper, a second `source` of this file
# in the same shell (e.g. an ordinary `source ~/.zshrc`) would hit zsh's
# `local`-outside-a-function fallback to plain `typeset`, which prints
# `REPLY=<value>` to the terminal for an already-set variable instead of
# scoping it.
# ------------------------------------------------------------------------
typeset -g _claude_env_baseline_label=""
if [ -n "$CLAUDE_CONFIG_DIR" ]; then
  () {
    local REPLY
    _claude_env_name
    _claude_env_baseline_label="$REPLY"
  }
fi

# ------------------------------------------------------------------------
# Discover environments by globbing $HOME/.claude-* directories. This is
# the whole point of the plugin's extraction from a templated dotfiles
# partial: no config var needs to be set for any of this to work.
# ------------------------------------------------------------------------
typeset -ga _claude_env_names
_claude_env_names=()
local _claude_env_dir
for _claude_env_dir in $HOME/.claude-*(N/); do
  _claude_env_names+=("${${_claude_env_dir:t}#.claude-}")
done

# ------------------------------------------------------------------------
# Per-environment wrapper functions: claude-<name>
# ------------------------------------------------------------------------
# Generated at RUNTIME from the discovered environments. Each claude-<name>
# runs `claude` once with CLAUDE_CONFIG_DIR pinned to that environment,
# inside a subshell `( ... )` so the assignment and any sourced .env file
# below never leak into the interactive shell. The generated body is a
# string containing $_claude_env_n verbatim, so it is only ever safe to
# generate when the name is restricted to a known-safe character set —
# hence the guard below, rather than embedding an arbitrary directory name
# into code. `claude-env <name>` (below) has no such restriction, since it
# only ever uses $1 as quoted variable *data*, never as generated code.
local _claude_env_n
for _claude_env_n in "${_claude_env_names[@]}"; do
  case "$_claude_env_n" in
    (""|*[!A-Za-z0-9_-]*)
      print -u2 "zsh-claude-env: skipping ~/.claude-$_claude_env_n — name must contain only letters, digits, '_', '-' to generate a claude-<name> function; claude-env $_claude_env_n still works."
      continue
      ;;
  esac
  functions[claude-$_claude_env_n]="(
    [ -f \"\$HOME/.config/claude-env/$_claude_env_n.env\" ] && . \"\$HOME/.config/claude-env/$_claude_env_n.env\"
    CLAUDE_CONFIG_DIR=\"\$HOME/.claude-$_claude_env_n\" exec command claude \"\$@\"
  )"
done

unset _claude_env_dir _claude_env_n

# ------------------------------------------------------------------------
# claude-env — switch the active environment for this shell session
# ------------------------------------------------------------------------
# Usage: claude-env [name]   (no args = print current)
# Validates $1 against the discovered environment set at runtime (zsh
# index-search idiom: (Ie) = reverse, exact match; nonzero index = found).
claude-env() {
  local REPLY
  if [ -z "$1" ]; then
    _claude_env_name
    echo "${REPLY:-(none)}"
    return
  fi
  if (( ${_claude_env_names[(Ie)$1]} )); then
    export CLAUDE_CONFIG_DIR="$HOME/.claude-$1"
    command -v p10k >/dev/null 2>&1 && p10k reload
    return
  fi
  echo "Usage: claude-env [${(j:|:)_claude_env_names}]" >&2
  return 1
}

# ------------------------------------------------------------------------
# Powerlevel10k segment (only meaningful if p10k is installed and this
# plugin is registered in POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS as `claude_env`;
# harmless no-op otherwise — p10k tolerates undefined segment functions).
# ------------------------------------------------------------------------
prompt_claude_env() {
  local color REPLY
  _claude_env_name
  [ -n "$REPLY" ] || return
  local label="$REPLY"

  # Hide the segment while on the baseline env, when configured to do so —
  # mirrors POWERLEVEL9K_NVM_SHOW_SYSTEM / the convention most p10k tool
  # segments use of only surfacing state that differs from baseline.
  if [ "$CLAUDE_ENV_SHOW_DEFAULT" != true ] \
    && [ -n "$_claude_env_baseline_label" ] \
    && [ "$label" = "$_claude_env_baseline_label" ]; then
    return
  fi

  color="${CLAUDE_ENV_COLORS[$label]:-244}"
  # nf-md-asterisk (U+F06C4), not the ✳ (U+2733) used in the window title:
  # this renders in the terminal grid font, where U+2733 is missing from
  # many installed faces, whereas PUA icons are guaranteed by nerdfont-v3.
  # Passed via -i so placement follows POWERLEVEL9K_ICON_BEFORE_CONTENT
  # like every other segment.
  # p10k segment text is prompt-expansion-aware (that's how segments embed
  # %F{color}...%f), so a literal % in the directory-derived label must be
  # escaped to %% here — an unescaped % would otherwise be interpreted as
  # a prompt escape sequence instead of literal text.
  p10k segment -f $color -i '󰛄' -t "${label//\%/%%}"
}

instant_prompt_claude_env() {
  prompt_claude_env
}
