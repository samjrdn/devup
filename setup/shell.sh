#!/bin/false
# shellcheck shell=bash

# Make zsh the account's default login shell. Every *.sym* file this repo
# links assumes zsh (or bash, still supported) is what actually runs at
# login; on Debian and a fresh Raspberry Pi OS image the default is bash, so
# the zsh config this repo installs sits unused until this runs.

# Print the account's current login shell. Queries by username rather than
# $HOME, so it still reports the real account when $HOME is overridden (as it
# is for testing) rather than failing to find a record.
current_shell() {
  if have dscl; then
    dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | awk '{print $2}'
  else
    getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7
  fi
}

# Both macOS and Linux refuse chsh to a shell that is not listed here.
ensure_listed_shell() {
  local shell_path="$1"
  grep -qxF "$shell_path" /etc/shells 2>/dev/null && return 0

  if [ "$DRY_RUN" = true ]; then
    printf '    %swould add%s %s to /etc/shells\n' "$C_DIM" "$C_RESET" "$shell_path"
    return 0
  fi

  printf '%s\n' "$shell_path" | as_root tee -a /etc/shells >/dev/null
  changed "added $shell_path to /etc/shells"
}

switch_default_shell() {
  step "Setting zsh as the default shell"

  local zsh_path
  zsh_path="$(command -v zsh || true)"

  if [ -z "$zsh_path" ] && [ "$OS" = debian ]; then
    run as_root apt-get install -y zsh
    zsh_path="$(command -v zsh || true)"
    [ -n "$zsh_path" ] && changed "installed zsh"
  fi

  if [ -z "$zsh_path" ]; then
    warn "zsh is not installed; install it, then re-run to switch the default shell"
    return 0
  fi

  if [ "$(current_shell)" = "$zsh_path" ]; then
    ok "default shell is already zsh"
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    printf '    %swould set%s the default shell to %s\n' "$C_DIM" "$C_RESET" "$zsh_path"
    return 0
  fi

  # chsh authenticates via PAM, which needs a real terminal. Piping this
  # script (curl ... | sh) leaves no terminal to prompt on, and the wrong
  # move is to let it hang waiting for a password that will never come.
  if [ ! -t 0 ]; then
    warn "no terminal to authenticate the shell change; run: chsh -s $zsh_path"
    return 0
  fi

  ensure_listed_shell "$zsh_path"

  if chsh -s "$zsh_path" "$(id -un)"; then
    changed "default shell is now zsh (takes effect on your next login)"
  else
    warn "chsh failed; switch it yourself with: chsh -s $zsh_path"
  fi
}
