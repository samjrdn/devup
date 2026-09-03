#!/bin/false
# shellcheck shell=bash

# The set of things setup.sh can turn on or off: as a whole with --full, one
# at a time with --interactive, or individually via --shell/--ssh. Each entry
# is "id|label|variable|server default|full default".
#
# --full is nothing but this table's full-column defaults applied without
# showing the checklist — not a separate code path. A feature can default to
# off even under --full (ssh does, deliberately: it touches your GitHub
# account) and still be turned on by hand in --interactive; that is how a
# feature can be interactive-only without any special-casing.
#
# What is NOT here: linking config files, seeding a git identity, installing
# mise's tool versions, creating the env directory. Those always run — they
# are the reason to run this script, not one more thing to remember to
# enable.
#
# The other half of the contract: turning a feature off only means its
# function is not called this run. Nothing here ever uninstalls, reverts, or
# undoes state from an earlier run — there is no "off" action, only the
# absence of an "on" one.
FEATURE_TABLE=(
  "packages|Install command-line packages|DO_PACKAGES_CLI|true|true"
  "gui|Install GUI applications|DO_PACKAGES_GUI|false|true"
  "shell|Make zsh the default shell|DO_SHELL_SWITCH|false|true"
  "ssh|Generate an SSH key for private repositories|DO_SSH|false|false"
  "signing|Configure commit signing with an SSH key|DO_SIGNING|false|true"
)

# Fill in a default for every feature whose variable a flag did not already
# set. Must run after argument parsing, so an explicit flag always outranks
# the profile default.
resolve_features() {
  local entry id label varname server_default full_default
  for entry in "${FEATURE_TABLE[@]}"; do
    IFS='|' read -r id label varname server_default full_default <<< "$entry"
    if [ -z "${!varname:-}" ]; then
      if [ "$FULL" = true ]; then
        printf -v "$varname" '%s' "$full_default"
      else
        printf -v "$varname" '%s' "$server_default"
      fi
    fi
  done
}

# Show every feature with its current on/off state, let the user toggle any
# of them by number, and continue once they press enter on an empty line.
interactive_checklist() {
  [ -t 0 ] || die "--interactive needs a terminal; use flags instead (--full, --ssh, --shell)"

  step "What to set up"
  printf '    %sToggling something off only skips it; it will not undo anything%s\n' "$C_DIM" "$C_RESET"
  printf '    %sa previous run already set up.%s\n' "$C_DIM" "$C_RESET"

  local n=${#FEATURE_TABLE[@]}
  local i entry id label varname server_default full_default mark reply

  while true; do
    printf '\n'
    for ((i = 0; i < n; i++)); do
      IFS='|' read -r id label varname server_default full_default <<< "${FEATURE_TABLE[$i]}"
      if [ "${!varname}" = true ]; then mark='x'; else mark=' '; fi
      printf '  %d) [%s] %s\n' "$((i + 1))" "$mark" "$label"
    done
    printf '\n  Type a number to toggle it, or press enter to continue: '
    read -r reply

    case "$reply" in
      '') break ;;
      *[!0-9]*) printf '  not a number\n' ;;
      *)
        if [ "$reply" -ge 1 ] && [ "$reply" -le "$n" ]; then
          # shellcheck disable=SC2034  # id/label/defaults unused here; only varname matters
          IFS='|' read -r id label varname server_default full_default <<< "${FEATURE_TABLE[$((reply - 1))]}"
          if [ "${!varname}" = true ]; then
            printf -v "$varname" '%s' false
          else
            printf -v "$varname" '%s' true
          fi
        else
          printf '  no item %s\n' "$reply"
        fi
        ;;
    esac
  done
}
