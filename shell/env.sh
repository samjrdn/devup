#!/bin/false
# shellcheck shell=bash

# Local environment variables — API keys, tokens, anything that must not be
# committed. They live outside this repo entirely, in:
#
#   ~/.config/devup/env.d/*.env
#
# Files are loaded in name order, so 50-work.env overrides 00-base.env.
# Each line is KEY=value. A value of the form op://vault/item/field is a
# 1Password reference: it is deliberately NOT exported. Use `withsecrets` to
# run a single command with those resolved, or `secret` to read one.

export DEVUP_ENV_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/devup/env.d"

__devup_load_env() {
  [ -d "$DEVUP_ENV_DIR" ] || return 0

  local file perm line key value

  for file in "$DEVUP_ENV_DIR"/*.env; do
    [ -r "$file" ] || continue

    # A credentials file readable by anyone else is a problem worth saying
    # out loud rather than silently tolerating.
    perm="$(stat -f '%Lp' "$file" 2>/dev/null || stat -c '%a' "$file" 2>/dev/null || echo 600)"
    case "$perm" in
      *[1-7][0-7]|*[0-7][1-7])
        printf 'warning: %s is readable by others (chmod 600 it)\n' "$file" >&2
        ;;
    esac

    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        ''|'#'*|' '*'#'*) continue ;;
      esac

      key="${line%%=*}"
      [ "$key" = "$line" ] && continue          # no "=" on the line
      value="${line#*=}"
      key="${key#export }"

      case "$key" in
        [A-Za-z_][A-Za-z0-9_]*) ;;
        *) printf 'warning: skipping malformed line in %s: %s\n' "$file" "$line" >&2
           continue ;;
      esac

      case "$value" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
      esac

      # 1Password references stay unresolved: putting a live secret in the
      # environment hands it to every process this shell ever starts.
      case "$value" in
        op://*) continue ;;
      esac

      export "$key=$value"
    done < "$file"
  done
}

__devup_load_env
unset -f __devup_load_env

# Run a command with 1Password references resolved, for that process only.
#
#   withsecrets ./deploy.sh
#   withsecrets npm run release
withsecrets() {
  if ! command -v op >/dev/null 2>&1; then
    printf 'withsecrets: the 1Password CLI (op) is not installed\n' >&2
    return 127
  fi
  if [ $# -eq 0 ]; then
    printf 'usage: withsecrets <command> [args...]\n' >&2
    return 64
  fi

  local envfile status
  envfile="$(mktemp)" || return 1
  chmod 600 "$envfile"
  cat "$DEVUP_ENV_DIR"/*.env > "$envfile" 2>/dev/null

  op run --env-file="$envfile" -- "$@"
  status=$?

  rm -f "$envfile"
  return $status
}

# Print one secret. Takes either a 1Password reference or the name of a
# variable defined as a reference in env.d.
#
#   secret op://Private/GitHub/token
#   secret GITHUB_TOKEN
secret() {
  if ! command -v op >/dev/null 2>&1; then
    printf 'secret: the 1Password CLI (op) is not installed\n' >&2
    return 127
  fi

  local ref="$1"
  case "$ref" in
    op://*) ;;
    '') printf 'usage: secret <VAR_NAME|op://reference>\n' >&2; return 64 ;;
    *)
      ref="$(cat "$DEVUP_ENV_DIR"/*.env 2>/dev/null \
             | sed -n "s/^[[:space:]]*\(export[[:space:]]*\)\{0,1\}$1=//p" \
             | tail -n 1)"
      case "$ref" in
        op://*) ;;
        *) printf 'secret: %s is not defined as an op:// reference in %s\n' \
             "$1" "$DEVUP_ENV_DIR" >&2; return 1 ;;
      esac
      ;;
  esac

  op read "$ref"
}
