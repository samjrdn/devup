#!/bin/false
# shellcheck shell=bash

# Shared helpers for the setup scripts. Sourced by setup.sh, never executed.

## output

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
else
  C_RESET= C_DIM= C_RED= C_GREEN= C_YELLOW= C_BLUE=
fi

step()    { printf '\n%s==>%s %s\n' "$C_BLUE"   "$C_RESET" "$*"; }
ok()      { printf '    %sok%s       %s\n' "$C_GREEN"  "$C_RESET" "$*"; }
changed() { printf '    %schanged%s  %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
skipped() { printf '    %sskip%s     %s\n' "$C_DIM"    "$C_RESET" "$*"; }
warn()    { printf '    %swarn%s     %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()     { printf '    %serror%s    %s\n' "$C_RED"    "$C_RESET" "$*" >&2; exit 1; }

## environment

have() { command -v "$1" >/dev/null 2>&1; }

# Print the platform we are setting up: macos, debian, linux or unknown.
detect_os() {
  case "$(uname -s)" in
    Darwin) printf 'macos' ;;
    Linux)
      # Runs in a subshell, so sourcing os-release cannot leak into the caller.
      if [ -r /etc/os-release ]; then
        . /etc/os-release
        case " ${ID:-} ${ID_LIKE:-} " in
          *' debian '*|*' ubuntu '*) printf 'debian'; return ;;
        esac
      fi
      if have apt-get; then printf 'debian'; else printf 'linux'; fi
      ;;
    *) printf 'unknown' ;;
  esac
}

# Run a command as root, via sudo when we are not already root.
as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif have sudo; then
    sudo "$@"
  else
    die "this step needs root and sudo is not installed: $*"
  fi
}

# Run a command, or describe it when --dry-run is in effect.
run() {
  if [ "$DRY_RUN" = true ]; then
    printf '    %swould run%s %s\n' "$C_DIM" "$C_RESET" "$*"
  else
    "$@"
  fi
}

# Ask a yes/no question. Always yes under --yes, always no without a terminal.
confirm() {
  [ "$ASSUME_YES" = true ] && return 0
  [ -t 0 ] || return 1
  local reply
  printf '    %s [y/N] ' "$1"
  read -r reply
  case "$reply" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}
