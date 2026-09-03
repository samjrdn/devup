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
  C_RESET='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE=''
fi

# Tallied for the summary printed at the end of the run, so a warning does not
# depend on being spotted while scrolling past everything that went fine.
SUMMARY_OK=0
SUMMARY_CHANGED=0
SUMMARY_SKIPPED=0
SUMMARY_WARNINGS=()

step()    { printf '\n%s==>%s %s\n' "$C_BLUE"   "$C_RESET" "$*"; }
ok()      { SUMMARY_OK=$((SUMMARY_OK + 1));           printf '    %sok%s       %s\n' "$C_GREEN"  "$C_RESET" "$*"; }
changed() { SUMMARY_CHANGED=$((SUMMARY_CHANGED + 1));  printf '    %schanged%s  %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
skipped() { SUMMARY_SKIPPED=$((SUMMARY_SKIPPED + 1));  printf '    %sskip%s     %s\n' "$C_DIM"    "$C_RESET" "$*"; }
warn()    { SUMMARY_WARNINGS+=("$*"); printf '    %swarn%s     %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()     { printf '    %serror%s    %s\n' "$C_RED"    "$C_RESET" "$*" >&2; exit 1; }

# Final tally: counts of everything that happened, and every warning restated
# together so none of them depend on being noticed the first time.
print_summary() {
  local counts="$SUMMARY_OK ok, $SUMMARY_CHANGED changed"
  [ "$SUMMARY_SKIPPED" -gt 0 ] && counts="$counts, $SUMMARY_SKIPPED skipped"

  local n=${#SUMMARY_WARNINGS[@]}
  if [ "$n" -eq 0 ]; then
    printf '    %s%s%s\n' "$C_GREEN" "$counts" "$C_RESET"
    return 0
  fi

  local plural=""; [ "$n" -ne 1 ] && plural="s"
  printf '    %s, %s%d warning%s%s\n' "$counts" "$C_YELLOW" "$n" "$plural" "$C_RESET"

  local w
  for w in "${SUMMARY_WARNINGS[@]}"; do
    printf '      %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$w"
  done
}

## environment

have() { command -v "$1" >/dev/null 2>&1; }

# Render a path for display with $HOME shown as "~", so the message and the
# path it describes can never drift apart.
tilde() {
  case "$1" in
    "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *)         printf '%s' "$1" ;;
  esac
}

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

# Print the CPU architecture, normalised: arm64 or x86_64.
detect_arch() {
  case "$(uname -m)" in
    arm64|aarch64) printf 'arm64' ;;
    x86_64|amd64)  printf 'x86_64' ;;
    *)             uname -m ;;
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
