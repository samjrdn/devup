#!/bin/sh
#
# Bootstrap devup on a machine that has nothing on it yet — not even git.
#
#   curl -fsSL https://raw.githubusercontent.com/samjrdn/devup/main/bootstrap.sh | sh
#
# Pass options through to setup.sh after "--":
#
#   curl -fsSL .../bootstrap.sh | sh -s -- --full
#
# Everything here is POSIX sh, because a minimal Debian image has dash as
# /bin/sh and no bash. Safe to run more than once: an existing checkout is
# updated rather than replaced.

set -eu

REPO="${DEVUP_REPO:-samjrdn/devup}"
BRANCH="${DEVUP_BRANCH:-main}"

# Remember whether the caller chose a directory, before we apply the default.
if [ -n "${DEVUP_DIR:-}" ]; then DEVUP_DIR_GIVEN=1; else DEVUP_DIR_GIVEN=0; fi
DEVUP_DIR="${DEVUP_DIR:-$HOME/src/github.com/$REPO}"

CLONE_URL="${DEVUP_CLONE_URL:-https://github.com/$REPO.git}"
TARBALL_URL="${DEVUP_TARBALL_URL:-https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH}"

say()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Install git if we can do it without user interaction. On macOS the only
# route is the Xcode command line tools, which opens a GUI dialog, so we do
# not force it here — the tarball path below covers that case instead.
try_install_git() {
  have git && return 0

  if have apt-get; then
    say "Installing git"
    if [ "$(id -u)" -eq 0 ]; then
      apt-get update && apt-get install -y git
    elif have sudo; then
      sudo apt-get update && sudo apt-get install -y git
    else
      warn "no root access to install git"
      return 1
    fi
    return 0
  fi

  return 1
}

# Fall back to a source tarball when git is unavailable. setup.sh installs git
# shortly afterwards, and we upgrade the directory to a real checkout at the
# end so it stays updatable.
download_tarball() {
  say "Downloading $REPO ($BRANCH) without git"

  have curl || have wget || die "need curl or wget to download anything"
  have tar || die "need tar to unpack the download"

  mkdir -p "$DEVUP_DIR"

  if have curl; then
    curl -fsSL "$TARBALL_URL" | tar xz -C "$DEVUP_DIR" --strip-components=1
  else
    wget -qO- "$TARBALL_URL" | tar xz -C "$DEVUP_DIR" --strip-components=1
  fi
}

# If this script is being run from inside a checkout rather than piped from
# curl, that checkout is what the caller means. Without this, running
# ./bootstrap.sh from a clone somewhere else would fetch a second copy into
# the default directory and set the machine up from that instead.
#
# When piped, "$0" is the shell itself, so no file matches and we fall through
# to the normal download.
local_checkout() {
  d=""
  [ -f "$0" ] || return 1
  d=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || return 1
  [ -x "$d/setup.sh" ] && [ -f "$d/bootstrap.sh" ] || return 1
  printf '%s' "$d"
}

fetch_repo() {
  if [ "$DEVUP_DIR_GIVEN" -eq 0 ] && here=$(local_checkout); then
    DEVUP_DIR="$here"
    say "Using the checkout this script was run from: $DEVUP_DIR"
    # Deliberately no pull: run what the caller has, not what is on origin.
    return 0
  fi

  if [ -d "$DEVUP_DIR/.git" ]; then
    say "Updating existing checkout at $DEVUP_DIR"
    git -C "$DEVUP_DIR" pull --ff-only || warn "could not fast-forward; leaving as is"
    return 0
  fi

  if [ -e "$DEVUP_DIR" ] && [ -n "$(ls -A "$DEVUP_DIR" 2>/dev/null)" ]; then
    say "Reusing existing directory $DEVUP_DIR"
    return 0
  fi

  if have git; then
    say "Cloning $REPO into $DEVUP_DIR"
    git clone --branch "$BRANCH" "$CLONE_URL" "$DEVUP_DIR"
  else
    download_tarball
  fi
}

# Turn a tarball download into a proper git checkout, now that setup.sh has
# installed git. Without this the directory could never be updated.
upgrade_to_checkout() {
  [ -d "$DEVUP_DIR/.git" ] && return 0
  have git || return 0

  say "Converting $DEVUP_DIR into a git checkout"
  git -C "$DEVUP_DIR" init -q
  git -C "$DEVUP_DIR" remote add origin "$CLONE_URL"
  git -C "$DEVUP_DIR" fetch -q --depth 1 origin "$BRANCH"
  git -C "$DEVUP_DIR" reset -q --hard "origin/$BRANCH"
  git -C "$DEVUP_DIR" branch -q -u "origin/$BRANCH" "$BRANCH" 2>/dev/null ||
    git -C "$DEVUP_DIR" checkout -q -b "$BRANCH" --track "origin/$BRANCH"
}

main() {
  try_install_git || true
  fetch_repo

  [ -x "$DEVUP_DIR/setup.sh" ] || die "setup.sh not found in $DEVUP_DIR"

  "$DEVUP_DIR/setup.sh" "$@"

  upgrade_to_checkout || warn "could not convert to a git checkout; re-clone to update later"

  say "devup is at $DEVUP_DIR"
}

main "$@"
