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
    ok "$(tilde "$target")"
    return 0
  fi

  # Read the identity before ~/.gitconfig is replaced by the symlink, so an
  # existing machine keeps working instead of losing its name and key.
  local name='' email='' key=''
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
    changed "$(tilde "$target") (carried over $name <$email>)"
  else
    changed "$(tilde "$target")"
    warn "set your name and email in ~/.gitconfig.local"
  fi
}

# Commits are signed with an SSH key. Which key, and whether 1Password does
# the signing, differ per machine, so both are written to ~/.gitconfig.local.

# 1Password ships a signer binary. Its location differs by platform, and the
# doc only names the macOS one, so check both.
find_op_ssh_sign() {
  local candidate
  for candidate in \
    "/Applications/1Password.app/Contents/MacOS/op-ssh-sign" \
    "/opt/1Password/op-ssh-sign"
  do
    if [ -x "$candidate" ]; then printf '%s' "$candidate"; return 0; fi
  done
  return 1
}

# True when 1Password's SSH agent is actually running. Pointing git at
# op-ssh-sign without it would break signing rather than improve it, because
# the key would not be reachable.
op_agent_running() {
  local sock="${SSH_AUTH_SOCK:-}"
  case "$sock" in
    *1password*|*1Password*) return 0 ;;
  esac
  [ -S "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock" ] ||
  [ -S "$HOME/.1password/agent.sock" ]
}

# Pick what to sign with. Two forms are possible and they are not
# interchangeable:
#
#   a path to a private key  — ssh-keygen signs straight from the file
#   a literal public key     — the private half must be in an ssh agent
#
# So prefer a local key file when there is one, and fall back to the literal
# public key only for agent-held keys such as 1Password's. Getting this wrong
# gives "Couldn't find key in agent?" on every commit.
#
# Prints the signingkey value, then a tab, then the public key text.
detect_signing_key() {
  local existing file

  for file in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ecdsa" "$HOME/.ssh/id_rsa"; do
    if [ -f "$file" ] && [ -f "$file.pub" ]; then
      printf '%s\t%s' "$file" "$(cut -d' ' -f1,2 < "$file.pub")"
      return 0
    fi
  done

  existing="$(git config --global --includes user.signingkey 2>/dev/null || true)"
  case "$existing" in
    ssh-*|sk-ssh-*) printf '%s\t%s' "$existing" "$existing"; return 0 ;;
  esac

  local agent_key
  agent_key="$(ssh-add -L 2>/dev/null | grep -m1 '^ssh-' | cut -d' ' -f1,2 || true)"
  [ -n "$agent_key" ] && printf '%s\t%s' "$agent_key" "$agent_key"
  return 0
}

# git verifies signatures against this file; without it every commit shows as
# from an unknown signer, even your own.
write_allowed_signers() {
  local email="$1" key="$2"
  local file="$HOME/.config/git/allowed_signers"

  [ -n "$email" ] && [ -n "$key" ] || return 0

  if [ -f "$file" ] && grep -qF "$key" "$file"; then
    ok "$(tilde "$file")"
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    printf '    %swould add%s %s to %s\n' "$C_DIM" "$C_RESET" "$email" "$file"
    return 0
  fi

  mkdir -p "$(dirname "$file")"
  printf '%s %s\n' "$email" "$key" >> "$file"
  changed "$(tilde "$file")"
}

setup_commit_signing() {
  step "Configuring commit signing"

  # A remote server has no business holding a signing key by default. Without
  # this, commit.gpgsign is never switched on, and commits there simply go
  # unsigned rather than failing.
  if [ "$DO_SIGNING" != true ]; then
    skipped "commit signing (enable with --full or --interactive)"
    return 0
  fi

  have git || { skipped "git not installed yet"; return 0; }

  local detected key pubkey email signer
  detected="$(detect_signing_key)"
  key="${detected%%	*}"
  pubkey="${detected#*	}"
  email="$(git config --global --includes user.email 2>/dev/null || true)"

  if [ -z "$key" ]; then
    warn "no SSH key found to sign with; run ./setup.sh --ssh to make one"
    return 0
  fi

  # An old GPG key id is a hex string, not an ssh- prefixed key. Say so rather
  # than leaving a config that silently cannot sign.
  local current
  current="$(git config --global --includes user.signingkey 2>/dev/null || true)"
  case "$current" in
    ssh-*|sk-ssh-*|/*) ;;  # already an SSH key: a literal key, or a path to one
    "") ;;
    *) warn "replacing the old GPG signing key $current with an SSH key" ;;
  esac

  if [ "$DRY_RUN" = true ]; then
    printf '    %swould set%s user.signingkey to %s...\n' \
      "$C_DIM" "$C_RESET" "$(printf '%s' "$key" | cut -c1-30)"
  else
    git config --file "$HOME/.gitconfig.local" user.signingkey "$key"
    case "$key" in
      /*) ok "signing key $key" ;;
      *)  ok "signing key ${pubkey%% *} (from the ssh agent)" ;;
    esac
  fi

  # Delegate to 1Password only when its agent is actually there.
  if signer="$(find_op_ssh_sign)" && op_agent_running; then
    if [ "$DRY_RUN" = false ]; then
      git config --file "$HOME/.gitconfig.local" gpg.ssh.program "$signer"
    fi
    ok "signing via 1Password ($signer)"
  else
    if [ "$DRY_RUN" = false ]; then
      git config --file "$HOME/.gitconfig.local" --unset gpg.ssh.program 2>/dev/null || true
    fi
    if find_op_ssh_sign >/dev/null 2>&1; then
      ok "signing with ssh-keygen (enable 1Password's SSH agent to use it instead)"
    else
      ok "signing with ssh-keygen"
    fi
  fi

  if [ "$DRY_RUN" = false ]; then
    git config --file "$HOME/.gitconfig.local" commit.gpgsign true
    git config --file "$HOME/.gitconfig.local" tag.gpgsign true
  fi

  write_allowed_signers "$email" "$pubkey"
}

# Prove the configuration actually signs, rather than assuming it does. Uses a
# throwaway repo so nothing here touches real history.
check_git_signing() {
  have git || { skipped "commit signing (git not installed yet)"; return 0; }
  [ "$DRY_RUN" = true ] && return 0
  [ "$(git config --global --includes commit.gpgsign 2>/dev/null || true)" = "true" ] || return 0

  local tmp out status
  tmp="$(mktemp -d)" || return 0

  git init -q "$tmp" 2>/dev/null
  # stdin is closed so a key needing a passphrase fails fast instead of
  # hanging the whole setup waiting for input.
  status=0
  out="$(git -C "$tmp" commit --allow-empty -m signing-probe 2>&1 < /dev/null)" || status=$?

  if [ $status -eq 0 ] && git -C "$tmp" verify-commit HEAD >/dev/null 2>&1 < /dev/null; then
    ok "commit signing works and verifies"
  elif [ $status -eq 0 ]; then
    ok "commits are signed (add your key to ~/.config/git/allowed_signers to verify locally)"
  else
    warn "commit signing is not working: ${out%%$'\n'*}"
  fi

  rm -rf "$tmp"
}
