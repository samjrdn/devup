#!/bin/false
# shellcheck shell=bash

# Give a machine access to private git repositories.
#
# Run with: ./setup.sh --ssh
#
# Opt-in rather than part of every run, because it creates a key and touches
# your GitHub account. Idempotent: an existing key is reused, never replaced.
#
# The rule this follows: a private key is generated on the machine that will
# use it and never leaves that machine. Copying your laptop's key to a server
# is not supported here, on purpose — it turns one compromised box into a
# compromise of every machine and repo that key can reach. For a server you
# only use interactively, agent forwarding (see the readme) is better still,
# because nothing lands on the server at all.

SSH_DIR="$HOME/.ssh"
SSH_KEY="$SSH_DIR/id_ed25519"

# Lock down ~/.ssh; ssh refuses to use it otherwise.
ensure_ssh_dir() {
  if [ ! -d "$SSH_DIR" ]; then
    run mkdir -p "$SSH_DIR"
    changed "$SSH_DIR"
  fi
  run chmod 700 "$SSH_DIR"
}

generate_ssh_key() {
  if [ -f "$SSH_KEY" ]; then
    ok "$SSH_KEY (existing key reused)"
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    printf '    %swould generate%s an ed25519 key at %s\n' "$C_DIM" "$C_RESET" "$SSH_KEY"
    return 0
  fi

  local host
  host="$(hostname -s 2>/dev/null || hostname)"

  printf '    %sGenerating an ed25519 key for %s.%s\n' "$C_DIM" "$host" "$C_RESET"

  if [ -t 0 ]; then
    printf '    %sChoose a passphrase. On a shared or remote machine this is the%s\n' \
      "$C_DIM" "$C_RESET"
    printf '    %sonly thing protecting the key if the disk is read.%s\n' "$C_DIM" "$C_RESET"
    ssh-keygen -t ed25519 -f "$SSH_KEY" -C "$(whoami)@$host"
  else
    # There is no terminal to prompt on — this is how `curl ... | sh` runs,
    # because stdin is the script itself. ssh-keygen would read EOF and make
    # an unencrypted key anyway; do it deliberately and say so, rather than
    # printing "choose a passphrase" and quietly not asking.
    ssh-keygen -q -t ed25519 -f "$SSH_KEY" -N '' -C "$(whoami)@$host"
    warn "no terminal to ask for a passphrase, so this key is UNENCRYPTED."
    warn "add one with: ssh-keygen -p -f $SSH_KEY"
  fi

  chmod 600 "$SSH_KEY"
  chmod 644 "$SSH_KEY.pub"
  changed "$SSH_KEY"
}

# Point github.com at this key explicitly, so a machine with several keys does
# not offer the wrong one and get rate-limited into a failure.
configure_ssh_host() {
  local config="$SSH_DIR/config"
  local marker="# managed by devup: github.com"

  if [ -f "$config" ] && grep -qF "$marker" "$config"; then
    ok "$(tilde "$config")"
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    printf '    %swould add%s a github.com block to %s\n' "$C_DIM" "$C_RESET" "$config"
    return 0
  fi

  {
    printf '\n%s\n' "$marker"
    printf 'Host github.com\n'
    printf '  User git\n'
    printf '  IdentityFile %s\n' "$SSH_KEY"
    printf '  IdentitiesOnly yes\n'
  } >> "$config"
  chmod 600 "$config"
  changed "$(tilde "$config")"
}

# Register the public key with GitHub. This changes the account, so it always
# asks first, even under --yes for the rest of the run.
register_ssh_key() {
  local pub="$SSH_KEY.pub"
  [ -f "$pub" ] || return 0

  local title
  title="$(whoami)@$(hostname -s 2>/dev/null || hostname)"

  if have gh && gh auth status >/dev/null 2>&1; then
    # Already registered? Compare the key body, ignoring the comment.
    local body
    body="$(cut -d' ' -f1,2 < "$pub")"
    if gh ssh-key list 2>/dev/null | grep -qF "${body#* }"; then
      ok "public key already on your GitHub account"
      return 0
    fi

    printf '\n    %sReady to add this key to your GitHub account as "%s":%s\n' \
      "$C_DIM" "$title" "$C_RESET"
    printf '    %s\n' "$(cat "$pub")"
    if confirm "Add it to GitHub now?"; then
      if run gh ssh-key add "$pub" --title "$title"; then
        changed "added public key to GitHub"
      else
        warn "could not add the key; add it at https://github.com/settings/ssh/new"
      fi

      # GitHub tracks authentication and signing keys separately. A key
      # registered for auth will NOT mark commits verified; it must be added
      # again as a signing key, which needs an extra gh scope.
      if confirm "Also register it as a signing key, so commits show verified?"; then
        if run gh ssh-key add "$pub" --title "$title (signing)" --type signing; then
          changed "registered public key for signing"
        else
          warn "gh lacks the admin:ssh_signing_key scope. Grant it with:"
          warn "  gh auth refresh -h github.com -s admin:ssh_signing_key"
          warn "or add it as type Signing Key at https://github.com/settings/ssh/new"
        fi
      fi
    else
      skipped "not added to GitHub"
    fi
    return 0
  fi

  printf '\n    %sAdd this public key at https://github.com/settings/ssh/new%s\n' \
    "$C_DIM" "$C_RESET"
  printf '    %s\n\n' "$(cat "$pub")"
}

verify_github_access() {
  [ "$DRY_RUN" = true ] && return 0

  # GitHub always exits 1 on this, even on success; the message is the signal.
  local out reason
  out="$(ssh -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 || true)"
  case "$out" in
    *"successfully authenticated"*)
      ok "github.com authenticates this machine"
      ;;
    *)
      # Drop ssh's own notices so the reported reason is the actual failure.
      reason="$(printf '%s\n' "$out" | grep -v '^Warning: Permanently added' | head -1)"
      warn "could not authenticate to github.com yet: $reason"
      ;;
  esac
}

setup_ssh_access() {
  step "Setting up access to private repositories"
  ensure_ssh_dir
  generate_ssh_key
  configure_ssh_host
  register_ssh_key
  verify_github_access
}
