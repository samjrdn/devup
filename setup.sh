#!/usr/bin/env bash

# Set up this machine from the devup repo.
#
# Safe to run repeatedly: every step checks the current state first and only
# changes what is not already correct.

set -euo pipefail

DEVUP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DEVUP

DRY_RUN=false
ASSUME_YES=false
DO_LINKS=true
DO_PACKAGES=true
FULL=false
DO_SSH=false

usage() {
  cat <<'USAGE'
Usage: ./setup.sh [options]

  --full          Also install GUI applications (see below)
  --ssh           Set up an SSH key for cloning private repositories
  --no-packages   Only link config files; skip brew/apt
  --only-packages Only install packages; leave config files alone
  --dry-run       Print what would change without changing anything
  --yes, -y       Answer yes to prompts (for unattended runs)
  --help, -h      Show this message

By default only command line tools and preferences are installed, which is
what a remote server wants. --full adds everything in packages/*.full.*, for
a desktop development machine.

--ssh generates an SSH key on this machine and offers to add it to GitHub, so
the machine can clone private repositories. The key never leaves the machine.

Run it as often as you like. Adding a package to a manifest in packages/ and
re-running installs just that package.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --full)          FULL=true ;;
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
source "$DEVUP/setup/symlinks.sh"
source "$DEVUP/setup/packages.sh"
source "$DEVUP/setup/secrets.sh"
source "$DEVUP/setup/git.sh"
source "$DEVUP/setup/ssh.sh"

OS="$(detect_os)"

main() {
  step "devup"
  ok "repo      $DEVUP"
  ok "platform  $OS"
  if [ "$FULL" = true ]; then
    ok "packages  command line + GUI applications (--full)"
  else
    ok "packages  command line only (--full adds GUI applications)"
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

  if [ "$DO_LINKS" = true ]; then
    seed_git_identity
    seed_local_shellrc
    link_config
    prune_stale_links
    seed_env_dir
    step "Checks"
    check_git_signing
  else
    step "Config files"
    skipped "--only-packages"
  fi

  if [ "$DO_SSH" = true ]; then
    setup_ssh_access
  fi

  step "Done"
  printf '    Open a new shell, or run: %ssource ~/.zprofile%s\n' "$C_DIM" "$C_RESET"
}

main
