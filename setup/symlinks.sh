#!/bin/false
# shellcheck shell=bash

# Symlink every file named *.sym* into $HOME, with the ".sym" removed.
# For example shell/zsh/.zprofile.sym becomes ~/.zprofile.
#
# Anything already in the way is moved into a timestamped backup directory
# first, so re-running is safe: a link that is already correct is left alone
# and produces no backup.

BACKUP_DIR="$HOME/.devup-backup/$(date +%Y%m%d-%H%M%S)"
BACKUP_MADE=false

# Move an existing path out of the way, into the backup directory.
back_up() {
  local path="$1"
  run mkdir -p "$BACKUP_DIR"
  run mv "$path" "$BACKUP_DIR/"
  BACKUP_MADE=true
}

# A shell rc file we are about to replace holds this machine's own setup —
# version managers, work paths. Carry it into ~/.shellrc.local so the machine
# keeps working, instead of leaving it stranded in the backup directory.
migrate_shell_rc() {
  local path="$1" name body local_rc="$HOME/.shellrc.local"
  name="$(basename "$path")"

  case "$name" in
    .zshrc|.zprofile|.bashrc|.bash_profile) ;;
    *) return 0 ;;
  esac

  # Drop lines that source the very files we are installing, which would
  # otherwise loop: .zprofile -> common.sh -> .shellrc.local -> .zprofile.
  body="$(grep -v -E \
    '^[[:space:]]*(source|\.)[[:space:]]+.*(\.zprofile|\.bash_profile|\.zshrc|\.bashrc|shell/common\.sh)' \
    "$path" 2>/dev/null | sed -e 's/[[:space:]]*$//')"

  # Nothing but blank lines and comments is not worth carrying over.
  if [ -z "$(printf '%s\n' "$body" | grep -v -E '^[[:space:]]*(#.*)?$' || true)" ]; then
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    printf '    %swould migrate%s %s into ~/.shellrc.local\n' "$C_DIM" "$C_RESET" "$name"
    return 0
  fi

  # Idempotent: a second run finds its own marker and does nothing.
  if [ -e "$local_rc" ] && grep -qF "# --- migrated from $name ---" "$local_rc"; then
    skipped "$name already migrated to ~/.shellrc.local"
    return 0
  fi

  {
    printf '\n# --- migrated from %s ---\n' "$name"
    printf '%s\n' "$body"
    printf '# --- end %s ---\n' "$name"
  } >> "$local_rc"

  changed "migrated $name into ~/.shellrc.local"
}

link_config() {
  step "Linking config files into $HOME"

  local src name dest current linked=0
  while IFS= read -r src; do
    name="$(basename "$src")"
    dest="$HOME/${name/.sym/}"

    if [ -L "$dest" ]; then
      current="$(readlink "$dest")"
      if [ "$current" = "$src" ]; then
        ok "~/${dest##*/}"
        continue
      fi
      if [ ! -e "$dest" ]; then
        # Dangling: usually this repo moved. There is nothing to preserve,
        # so replace it rather than filling the backup directory with
        # broken links.
        run rm -f "$dest"
      else
        # A live link we do not own, or one left over from an older layout.
        back_up "$dest"
      fi
    elif [ -e "$dest" ]; then
      migrate_shell_rc "$dest"
      back_up "$dest"
    fi

    run ln -s "$src" "$dest"
    changed "~/${dest##*/}"
  done < <(find "$DEVUP" -name '*.sym*' -not -path '*/.git/*' | sort)

  # Linking nothing means the search failed, not that there was nothing to do.
  # Report it rather than exiting 0 on a run that quietly did nothing.
  linked="$(find "$DEVUP" -name '*.sym*' -not -path '*/.git/*' 2>/dev/null | wc -l | tr -d '[:space:]')"
  if [ "${linked:-0}" -eq 0 ]; then
    die "found no *.sym* files under $DEVUP — is the checkout complete?"
  fi

  if [ "$BACKUP_MADE" = true ]; then
    printf '\n    %sReplaced files were moved to %s%s\n' "$C_YELLOW" "$BACKUP_DIR" "$C_RESET"
    printf '    %sShell rc files found there were carried into ~/.shellrc.local%s\n' \
      "$C_DIM" "$C_RESET"
  fi
}

# Remove links in $HOME that point into this repo at a file that no longer
# exists — for example after a config file is retired here. Only links whose
# target is inside the repo are touched, so nothing else in $HOME is at risk.
prune_stale_links() {
  local dest target

  for dest in "$HOME"/.*; do
    [ -L "$dest" ] || continue
    [ -e "$dest" ] && continue

    target="$(readlink "$dest")"
    case "$target" in
      "$DEVUP"/*) ;;
      *) continue ;;
    esac

    run rm -f "$dest"
    changed "removed stale ~/${dest##*/} (no longer in the repo)"
  done
}

# Create ~/.shellrc.local, sourced last by the shell config, for anything that
# is specific to this machine and should never be committed.
seed_local_shellrc() {
  local target="$HOME/.shellrc.local"

  if [ -e "$target" ]; then
    ok "~/.shellrc.local"
    return
  fi

  if [ "$DRY_RUN" = true ]; then
    printf '    %swould create%s %s\n' "$C_DIM" "$C_RESET" "$target"
    return
  fi

  cat > "$target" <<'TEMPLATE'
#!/bin/false
# shellcheck shell=bash

# Machine-specific shell configuration. Sourced last, so it wins over the
# devup repo. Not tracked in git — put anything that only applies to this
# one machine here, such as version-manager hooks or work paths.

# eval "$(mise activate zsh)"
TEMPLATE
  changed "~/.shellrc.local"
}
