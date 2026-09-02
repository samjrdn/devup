#!/bin/false
# shellcheck shell=bash

# Environment variables that cannot live in a public repo — API keys and the
# like — are read from ~/.config/devup/env.d/*.env at shell startup.
# Create that directory, locked down, with a template to start from.

seed_env_dir() {
  step "Setting up local environment variables"

  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/devup/env.d"
  local template="$dir/00-example.env"

  if [ "$DRY_RUN" = true ]; then
    printf '    %swould create%s %s\n' "$C_DIM" "$C_RESET" "$dir"
    return 0
  fi

  if [ -d "$dir" ]; then
    ok "$dir"
  else
    mkdir -p "$dir"
    changed "$dir"
  fi

  # These files hold credentials: owner-only, always, even on re-runs.
  chmod 700 "$dir"
  chmod 700 "$(dirname "$dir")"

  if [ ! -e "$template" ]; then
    cat > "$template" <<'TEMPLATE'
# Environment variables for this machine only. Never committed.
#
# One KEY=value per line. Quotes are optional; everything after the first "="
# is the value. Files in this directory are loaded in name order, so a later
# file can override an earlier one.
#
#   SOME_API_KEY=sk-abc123
#
# For anything valuable, prefer a 1Password reference over a literal:
#
#   SOME_API_KEY=op://Private/Some Service/credential
#
# A value starting with op:// is NOT exported into your shell. Run the command
# that needs it through `withsecrets`, which resolves references for that one
# process and nothing else:
#
#   withsecrets ./deploy.sh
TEMPLATE
    chmod 600 "$template"
    changed "$template"
  else
    ok "$template"
  fi

  # Anything already in there predates this run; make sure it is not readable
  # by anyone else.
  local f
  for f in "$dir"/*.env; do
    [ -e "$f" ] || continue
    chmod 600 "$f"
  done
}
