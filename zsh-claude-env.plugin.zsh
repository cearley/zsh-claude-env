# zsh-claude-env — multi-environment wrapper functions, a session switcher,
# and terminal-title integration for Claude Code (https://claude.ai/code).
# Modeled on oh-my-zsh's built-in `aws` plugin (`asp`/`asr`):
# https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/aws
#
# Environments are discovered by globbing $HOME/.claude-* directories at
# load time, filtered to those containing a .claude.json file (written by
# Claude Code on first invocation against a CLAUDE_CONFIG_DIR) — a directory
# that merely matches the naming convention is otherwise ignored. There is
# nothing to configure to make wrapper functions or the switcher appear.
#
# The active environment's name (_claude_env_name) and the environment
# captured at load time (_claude_env_baseline_label) are exposed as plain
# globals for use in a prompt or elsewhere. Two optional hook functions, if
# defined elsewhere, are called at the relevant point: claude_env_after_switch
# (after `claude-env <name>` switches) and claude_env_git_context_hook (in
# place of the plain git fork used for the terminal title). See README for a
# Powerlevel10k example defining both.
#
# ------------------------------------------------------------------------
# Config variables (all optional; set anywhere, read lazily at hook-invocation
# time — safe to set in ~/.p10k.zsh even though it's sourced after this
# plugin loads)
# ------------------------------------------------------------------------
#   CLAUDE_ENV_TITLE_HOOKS   true|false, default true. Toggles the OSC-0
#                            terminal-title feature (precmd/preexec hooks
#                            below), independent of everything else.
#
# The claude config dir path convention ($HOME/.claude-<name>) and the
# per-env local override file ($HOME/.config/claude-env/<name>.env) are
# intentionally not configurable.
#
# Limitation: a brand-new environment has no claude-<name>() function until
# its $HOME/.claude-<name> directory exists on disk *and* contains a
# .claude.json (i.e. `claude` has been invoked against it at least once)
# *and* a new shell session re-globs. Bootstrap one with
# `CLAUDE_CONFIG_DIR=$HOME/.claude-<name> claude` once, then open a new shell.

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
# If a claude_env_git_context_hook function is defined, it's tried first —
# it should set REPLY and return 0 on success, non-zero to fall through to
# the plain git fork below (e.g. a p10k user can define this to reuse
# gitstatus data instead of forking git — see README).
_claude_env_git_context() {
  local repo branch
  REPLY=""
  if (( $+functions[claude_env_git_context_hook] )) && claude_env_git_context_hook; then
    return
  fi
  repo=$(git rev-parse --show-toplevel 2>/dev/null) || return
  repo="${repo##*/}"
  branch=$(git branch --show-current 2>/dev/null)
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
# Capture the environment active when this plugin loaded into
# _claude_env_baseline_label, for consumers that want to compare the active
# environment against this baseline (e.g. a p10k segment). Must run after
# _claude_env_name is defined.
#
# Wrapped in an anonymous function so `local REPLY` always has a real
# function scope to bind to — this file's top level isn't itself inside a
# function when sourced directly (the standalone install path in the
# README). Without this wrapper, a second `source` of this file in the same
# shell (e.g. an ordinary `source ~/.zshrc`) would hit zsh's
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
# Discover environments by globbing $HOME/.claude-* directories.
# ------------------------------------------------------------------------
typeset -ga _claude_env_names
_claude_env_names=()
local _claude_env_dir
for _claude_env_dir in $HOME/.claude-*(N/); do
  # Gate on .claude.json rather than the directory alone, to reject
  # unrelated directories that merely match the naming convention (e.g. a
  # ~/.claude-notes/ folder with no relation to Claude Code).
  [ -f "$_claude_env_dir/.claude.json" ] || continue
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
    # claude_env_after_switch, if defined, is called here — e.g. a p10k user
    # can define it to call `p10k reload` so a prompt segment updates
    # immediately (see README).
    (( $+functions[claude_env_after_switch] )) && claude_env_after_switch
    return
  fi
  echo "Usage: claude-env [${(j:|:)_claude_env_names}]" >&2
  return 1
}
