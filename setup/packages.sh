#!/bin/false
# shellcheck shell=bash

# Install packages from the manifests in packages/.
#
# macOS  reads packages/Brewfile via `brew bundle`
# Debian reads packages/apt.txt
#
# Both paths only touch what is missing, so adding a line to a manifest and
# re-running installs just that one package.

PACKAGE_FAILURES=0

BREW_INSTALL_URL='https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh'
MISE_INSTALL_URL='https://mise.run'

# Print a manifest with comments, blank lines and trailing spaces removed.
read_package_list() {
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$1"
}

# Echo the manifests to install, in order:
#
#   Brewfile            always
#   Brewfile.<arch>     matching this CPU only
#   Brewfile.full       only with --full
#
# Missing files are skipped, so a platform can omit any of them. The arch
# split exists because Homebrew stopped supporting macOS on Intel in
# September 2026: there are no bottles for x86_64 any more, so anything not
# already on the system gets compiled from source. Packages worth having only
# where they are cheap belong in Brewfile.arm64.
manifests() {
  local base="$DEVUP/packages/$1" full="$DEVUP/packages/$2"
  local arch="$DEVUP/packages/$1.$ARCH"

  if [ "$DO_PACKAGES_CLI" = true ]; then
    [ -f "$base" ] && printf '%s\n' "$base"
    [ -f "$arch" ] && printf '%s\n' "$arch"
  fi
  if [ "$DO_PACKAGES_GUI" = true ] && [ -f "$full" ]; then
    printf '%s\n' "$full"
  fi
  return 0
}

## macOS

# Put brew on PATH if it is installed anywhere we recognise.
load_homebrew() {
  local candidate
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$candidate" ]; then
      eval "$("$candidate" shellenv)"
      return 0
    fi
  done
  return 1
}

install_homebrew() {
  if load_homebrew; then
    ok "homebrew ($(command -v brew))"
    return 0
  fi

  warn "Homebrew is not installed."
  printf '    %sThe official installer will be fetched from:%s\n' "$C_DIM" "$C_RESET"
  printf '    %s%s%s\n' "$C_DIM" "$BREW_INSTALL_URL" "$C_RESET"
  if ! confirm "Download and run it now?"; then
    warn "skipping Homebrew; no macOS packages will be installed"
    return 1
  fi

  if [ "$DRY_RUN" = true ]; then
    printf '    %swould run%s the Homebrew installer\n' "$C_DIM" "$C_RESET"
    return 1
  fi

  /bin/bash -c "$(curl -fsSL "$BREW_INSTALL_URL")"
  load_homebrew || die "Homebrew installed but brew is still not on PATH"
  changed "homebrew"
}

install_brew_packages() {
  install_homebrew || return 0

  if [ "$OS" = macos ] && [ "$ARCH" = x86_64 ]; then
    warn "Homebrew dropped macOS Intel support in September 2026; packages"
    warn "without a bottle are built from source, which is slow"
  fi

  # `brew bundle` is idempotent on its own: it installs what is missing and
  # leaves the rest alone. --no-upgrade keeps re-runs from churning through
  # version bumps we did not ask for.
  local brewfile
  for brewfile in $(manifests Brewfile Brewfile.full); do
    step "Installing packages from packages/$(basename "$brewfile")"
    # A single broken formula should not stop the rest of the setup, so this
    # is reported rather than fatal. Everything else still gets configured.
    if ! run brew bundle install --no-upgrade --file "$brewfile"; then
      warn "some packages in $(basename "$brewfile") failed; continuing"
      PACKAGE_FAILURES=$((PACKAGE_FAILURES + 1))
    fi
  done
}

## Debian

# True when the apt package lists have not been refreshed for a day.
apt_lists_stale() {
  local stamp=/var/lib/apt/lists
  if [ -e /var/lib/apt/periodic/update-success-stamp ]; then
    stamp=/var/lib/apt/periodic/update-success-stamp
  fi
  [ -e "$stamp" ] || return 0
  [ -n "$(find "$stamp" -maxdepth 0 -mmin +1440 2>/dev/null)" ]
}

# apt has no mise package, so use the official installer. Homebrew covers this
# on macOS.
install_mise() {
  if have mise || [ -x "$HOME/.local/bin/mise" ]; then
    ok "mise"
    return 0
  fi

  step "Installing mise"

  if [ "$DRY_RUN" = true ]; then
    printf '    %swould run%s the mise installer from %s\n' \
      "$C_DIM" "$C_RESET" "$MISE_INSTALL_URL"
    return 0
  fi

  printf '    %smise is not packaged for apt. The official installer will be%s\n' \
    "$C_DIM" "$C_RESET"
  printf '    %sfetched from %s%s\n' "$C_DIM" "$MISE_INSTALL_URL" "$C_RESET"
  if ! confirm "Download and run it now?"; then
    warn "skipping mise; ruby, python and node versions will not be managed"
    return 0
  fi

  curl -fsSL "$MISE_INSTALL_URL" | sh
  changed "mise"
}

install_apt_packages() {
  local list
  for list in $(manifests apt.txt apt.full.txt); do
    install_apt_list "$list"
  done
  install_mise
}

install_apt_list() {
  local list="$1"

  step "Installing packages from packages/$(basename "$list")"

  local pkg missing=
  while IFS= read -r pkg; do
    if dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null | grep -q '^installed$'; then
      ok "$pkg"
    else
      missing="$missing $pkg"
    fi
  done < <(read_package_list "$list")

  if [ -z "$missing" ]; then
    ok "all packages already installed"
    return 0
  fi

  if apt_lists_stale; then
    run as_root apt-get update
  else
    skipped "apt-get update (lists are current)"
  fi

  # Word splitting is what we want here: $missing is a list of package names.
  # shellcheck disable=SC2086
  if run as_root apt-get install -y $missing; then
    changed "installed:$missing"
  else
    warn "some packages in $(basename "$list") failed; continuing"
    PACKAGE_FAILURES=$((PACKAGE_FAILURES + 1))
  fi
}

# Install whatever versions the machine's own mise config names. Idempotent:
# mise skips any version already present. The first run on a new machine is
# slow, because it is building ruby and python.
install_mise_tools() {
  # Tool versions come from the machine's own mise config, not from this repo.
  [ -f "$HOME/.config/mise/config.toml" ] || [ -f "$HOME/.mise.toml" ] || return 0
  have mise || [ -x "$HOME/.local/bin/mise" ] || return 0

  step "Installing tool versions from your mise config"
  run "${MISE:-$(command -v mise || echo "$HOME/.local/bin/mise")}" install
}

install_packages() {
  case "$OS" in
    macos)  install_brew_packages ;;
    debian) install_apt_packages ;;
    *)      warn "no package manifest for this platform ($OS); skipping packages" ;;
  esac
  install_mise_tools
}
