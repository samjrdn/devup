#!/bin/false
# shellcheck shell=bash

# The tracked .gitconfig cannot hold an identity or a signing key, so it
# includes ~/.gitconfig.local instead. Seed that file on first run, carrying
# over whatever identity this machine already had.

seed_git_identity() {
  step "Configuring git identity"

  local target="$HOME/.gitconfig.local"

  # On a bare machine git may not be installed yet. The identity file is still
  # worth writing; we just cannot read an existing identity to carry over.
  if ! have git; then
    warn "git is not installed yet; writing a placeholder identity"
  fi

  if [ -e "$target" ]; then
    ok "~/.gitconfig.local"
    return 0
  fi

  # Read the identity before ~/.gitconfig is replaced by the symlink, so an
  # existing machine keeps working instead of losing its name and key.
  local name= email= key=
  if have git; then
    name="$(git config --global --includes user.name || true)"
    email="$(git config --global --includes user.email || true)"
    key="$(git config --global --includes user.signingkey || true)"
  fi

  if [ "$DRY_RUN" = true ]; then
    printf '    %swould create%s %s\n' "$C_DIM" "$C_RESET" "$target"
    return 0
  fi

  {
    printf '# Git identity for this machine. Not tracked in git.\n'
    printf '# Included by the devup .gitconfig, and applied last so it wins.\n\n'
    printf '[user]\n'
    printf '  name = %s\n'  "${name:-Your Name}"
    printf '  email = %s\n' "${email:-you@example.com}"
    if [ -n "$key" ]; then
      printf '  signingkey = %s\n' "$key"
    else
      printf '  # signingkey = YOURKEYID\n'
    fi
  } > "$target"

  if [ -n "$name" ] && [ -n "$email" ]; then
    changed "~/.gitconfig.local (carried over $name <$email>)"
  else
    changed "~/.gitconfig.local"
    warn "set your name and email in ~/.gitconfig.local"
  fi
}

# Commit signing is on in the tracked config. Say something useful when the
# machine has no key, rather than letting the first commit fail.
check_git_signing() {
  have git || { skipped "commit signing (git not installed yet)"; return 0; }

  # --includes is off by default when a specific file is named (--global
  # counts), so without it we cannot see ~/.gitconfig.local at all.
  local signing
  signing="$(git config --global --includes commit.gpgsign || true)"
  [ "$signing" = "true" ] || return 0

  if ! have gpg; then
    warn "commit.gpgsign is on but no gpg is installed; commits will fail."
    warn "install one with 'brew install gnupg', or GPG Suite from gpgtools.org"
    return 0
  fi

  local key
  key="$(git config --global --includes user.signingkey || true)"
  if [ -z "$key" ]; then
    warn "commit.gpgsign is on but user.signingkey is unset in ~/.gitconfig.local"
  elif ! gpg --list-secret-keys "$key" >/dev/null 2>&1; then
    warn "signing key $key is not in this machine's gpg keyring; import it or commits will fail"
  else
    ok "commit signing (key $key)"
  fi
}
