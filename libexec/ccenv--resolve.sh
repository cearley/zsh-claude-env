# Shared resolver for ccenv's shell > local > global precedence.
#
# Sourced (not executed) by ccenv-profile, ccenv-global, ccenv-local, and
# ccenv-sh-shell, so each of those scripts shares one implementation of
# "where does the active profile come from" instead of three or four
# near-duplicates slowly drifting apart. This file is deliberately not
# named `ccenv-<command>` — the dispatcher in libexec/ccenv only ever
# looks up names of that exact shape, so this can never be accidentally
# invoked as a subcommand.
#
# Profile storage contract (shared with ccenv-add/-remove/-list, decided
# once for the whole CLI): a registered profile is a symlink at
# $CCENV_ROOT/profiles/<name>. No other file is assumed to exist.

: "${CCENV_ROOT:=$HOME/.ccenv}"
export CCENV_ROOT

# Tests whether $1 is safe to use as a path component under
# $CCENV_ROOT/profiles: non-empty, contains no "/", and isn't "." or
# "..". A profile name is used to build a filesystem path in several
# places (this file, ccenv-add, ccenv-remove, ccenv-global, ccenv-local,
# ccenv-sh-shell, ccenv-shell, ccenv-with, and ccenv-init's
# _ccenv_resolved_real_dir); without this check, a value walking in from
# a file (.claude-profile, $CCENV_ROOT/profile) or a command-line
# argument could traverse outside $CCENV_ROOT/profiles entirely.
_ccenv_valid_name() {
  case "$1" in
  '' | . | .. | */*) return 1 ;;
  esac
  return 0
}

# Tests whether $1 is a registered profile. An invalid name (see
# _ccenv_valid_name) is never registered, by definition -- checked here
# too, not just by callers, since this is also called directly from
# ccenv--resolve.sh's own resolution path.
_ccenv_is_registered() {
  _ccenv_valid_name "$1" || return 1
  [ -L "$CCENV_ROOT/profiles/$1" ]
}

# Trims leading/trailing whitespace (including a trailing newline from
# `cat`-ing a one-line file) from $1, printing the result.
_ccenv_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Local tier: walks from $PWD up through each ancestor directory (stopping
# at /), using the trimmed content of the first .claude-profile file
# found. Sets REPLY and returns 0 if a file was found anywhere in the
# walk AND its content is a valid profile name; sets REPLY="" and returns
# 1 if none exists up to and including /, OR the first file found has
# invalid content (e.g. a path-traversal attempt) -- a malicious or
# corrupted .claude-profile in some directory you `cd` into must never
# crash resolution or escape $CCENV_ROOT/profiles; it's treated exactly
# as if the tier yielded nothing, falling through to the next tier.
_ccenv_local_lookup() {
  local dir="$PWD"
  while :; do
    if [ -f "$dir/.claude-profile" ]; then
      REPLY="$(_ccenv_trim "$(cat "$dir/.claude-profile")")"
      if _ccenv_valid_name "$REPLY"; then
        return 0
      fi
      REPLY=""
      return 1
    fi
    [ "$dir" = "/" ] && break
    dir="$(dirname "$dir")"
  done
  REPLY=""
  return 1
}

# Global tier: the trimmed content of $CCENV_ROOT/profile, if it exists
# AND is a valid profile name. Sets REPLY and returns 0 on a valid value;
# sets REPLY="" and returns 1 if the file doesn't exist OR its content is
# invalid (treated as unset, same reasoning as the local tier above).
_ccenv_global_lookup() {
  if [ -f "$CCENV_ROOT/profile" ]; then
    REPLY="$(_ccenv_trim "$(cat "$CCENV_ROOT/profile")")"
    if _ccenv_valid_name "$REPLY"; then
      return 0
    fi
    REPLY=""
    return 1
  fi
  REPLY=""
  return 1
}

# Resolves $1 (a profile name, possibly empty) to the real directory
# behind its $CCENV_ROOT/profiles/<name> symlink. Echoes nothing (and
# returns non-zero) if $1 is empty, not a valid path component (see
# _ccenv_valid_name), or its symlink is missing/dangling. Shared by every
# caller that needs the real directory a name points at, not just the
# name itself: ccenv-sh-shell (to emit the right CLAUDE_CONFIG_DIR
# export) and ccenv-sh-resolve (the automatic, hook-driven path that
# keeps CLAUDE_CONFIG_DIR in sync with directory changes and with a
# plain `local`/`global` file write -- see ccenv-sh-resolve).
_ccenv_real_dir_for() {
  local name="$1" link rl
  _ccenv_valid_name "$name" || return 1
  link="$CCENV_ROOT/profiles/$name"
  [ -L "$link" ] || return 1
  rl="$(command -v greadlink 2>/dev/null || command -v readlink)"
  "$rl" "$link"
}

# Resolves the active profile for the current directory using
# shell(CCENV_PROFILE) > local(.claude-profile) > global(CCENV_ROOT/profile)
# precedence. The first tier that yields a non-empty value wins. Sets
# CCENV_RESOLVED_PROFILE and CCENV_RESOLVED_TIER ("shell", "local", or
# "global") and returns 0 if a profile was resolved; sets both to "" and
# returns 1 if no tier yielded a value.
_ccenv_resolve() {
  local REPLY

  if [ -n "$CCENV_PROFILE" ] && _ccenv_valid_name "$CCENV_PROFILE"; then
    CCENV_RESOLVED_PROFILE="$CCENV_PROFILE"
    CCENV_RESOLVED_TIER="shell"
    return 0
  fi

  if _ccenv_local_lookup && [ -n "$REPLY" ]; then
    CCENV_RESOLVED_PROFILE="$REPLY"
    CCENV_RESOLVED_TIER="local"
    return 0
  fi

  if _ccenv_global_lookup && [ -n "$REPLY" ]; then
    CCENV_RESOLVED_PROFILE="$REPLY"
    CCENV_RESOLVED_TIER="global"
    return 0
  fi

  CCENV_RESOLVED_PROFILE=""
  CCENV_RESOLVED_TIER=""
  return 1
}
