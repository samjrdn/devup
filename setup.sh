#!/usr/bin/env bash

# Set up this machine from the devup repo.
#
# Safe to run repeatedly: every step checks the current state first and only
# changes what is not already correct.

set -euo pipefail

DEVUP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DEVUP

DRY_RUN=false
# Used by confirm() in setup/lib.sh.
# shellcheck disable=SC2034
ASSUME_YES=false
DO_LINKS=true
DO_PACKAGES=true
DO_INTERACTIVE=false
FULL=false

# Left unset (not false) so setup/features.sh's resolve_features can tell
# "no flag touched this" apart from "a flag explicitly turned it off", and
# fill in the right profile default only in the first case.
DO_PACKAGES_CLI=""
DO_PACKAGES_GUI=""
DO_SHELL_SWITCH=""
DO_SSH=""
DO_SIGNING=""

usage() {
  cat <<'USAGE'
Usage: ./setup.sh [options]

  --interactive, -i  Review and toggle what gets set up before running it
  --full          Also install GUI applications, switch to zsh, and sign
                  commits (see below)
  --shell         Make zsh the default shell
  --no-shell      Do not change the default shell
  --ssh           Set up an SSH key for cloning private repositories
  --no-packages   Only link config files; skip brew/apt
  --only-packages Only install packages; leave config files alone
  --dry-run       Print what would change without changing anything
  --yes, -y       Answer yes to prompts (for unattended runs)
  --help, -h      Show this message

By default only command line tools and preferences are installed, which is
what a remote server wants. --full turns on everything that makes sense for
a desktop development machine. --interactive shows the same choices as a
checklist you can toggle before anything runs — it needs a terminal, so it
only works from a cloned checkout, not the piped bootstrap one-liner.
Unchecking something only skips it; it never undoes what an earlier run
already set up.

--ssh generates an SSH key on this machine and offers to add it to GitHub, so
the machine can clone private repositories. The key never leaves the machine.

Run it as often as you like. Adding a package to a manifest in packages/ and
re-running installs just that package.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    -i|--interactive) DO_INTERACTIVE=true ;;
    --full)          FULL=true ;;
    --shell)         DO_SHELL_SWITCH=true ;;
    --no-shell)      DO_SHELL_SWITCH=false ;;
    --ssh)           DO_SSH=true ;;
    --no-packages)   DO_PACKAGES=false ;;
    --only-packages) DO_LINKS=false ;;
    --dry-run)       DRY_RUN=true ;;
    -y|--yes)        ASSUME_YES=true ;;
    -h|--help)       usage; exit 0 ;;
    *)               printf 'Unknown option: %s\n\n' "$1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done

# shellcheck source=setup/lib.sh
source "$DEVUP/setup/lib.sh"
source "$DEVUP/setup/features.sh"
source "$DEVUP/setup/symlinks.sh"
source "$DEVUP/setup/packages.sh"
source "$DEVUP/setup/secrets.sh"
source "$DEVUP/setup/git.sh"
source "$DEVUP/setup/ssh.sh"
source "$DEVUP/setup/shell.sh"

OS="$(detect_os)"
ARCH="$(detect_arch)"
resolve_features

main() {
  step "devup"
  ok "repo      $DEVUP"
  ok "platform  $OS ($ARCH)"

  if [ "$DO_INTERACTIVE" = true ]; then
    interactive_checklist
  fi

  if [ "$DO_PACKAGES_GUI" = true ]; then
    ok "packages  command line + GUI applications"
  else
    ok "packages  command line only"
  fi
  if [ "$DRY_RUN" = true ]; then warn "dry run: nothing will be changed"; fi

  case "$OS" in
    macos|debian) ;;
    *) warn "unrecognised platform; config files will be linked but no packages installed" ;;
  esac

  if [ "$DO_PACKAGES" = true ]; then
    install_packages
  else
    step "Packages"
    skipped "--no-packages"
  fi

  # SSH access comes before signing: --ssh creates the key that signing then
  # configures. The other way round, a brand new machine finishes with signing
  # unconfigured and needs a second run.
  if [ "$DO_SSH" = true ]; then
    setup_ssh_access
  fi

  if [ "$DO_LINKS" = true ]; then
    seed_git_identity
    seed_local_shellrc
    link_config
    prune_stale_links
    link_renamed_binaries
    seed_env_dir

    if [ "$DO_SHELL_SWITCH" = true ]; then
      switch_default_shell
    fi

    setup_commit_signing

    step "Checks"
    check_git_signing
  else
    step "Config files"
    skipped "--only-packages"
  fi

  step "Done"
  print_summary

  if [ "$FULL" != true ] && [ "$DO_INTERACTIVE" != true ]; then
    printf '\n'
    printf '    %sThis set up command-line tools and preferences only.%s\n' "$C_DIM" "$C_RESET"
    printf '    For GUI applications, zsh, and commit signing:\n'
    printf '      %s%s/setup.sh --full%s\n' "$C_DIM" "$(tilde "$DEVUP")" "$C_RESET"
    printf '    To choose exactly what gets set up:\n'
    printf '      %s%s/setup.sh --interactive%s\n' "$C_DIM" "$(tilde "$DEVUP")" "$C_RESET"
  fi

  printf '\n    Open a new shell, or run: %ssource ~/.zprofile%s\n' "$C_DIM" "$C_RESET"
}

main
