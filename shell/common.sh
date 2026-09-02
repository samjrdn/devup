#!/bin/false
# shellcheck shell=bash

# Shared shell configuration, sourced by both .zprofile and .bash_profile.
# $DEVUP is set by whichever of those sourced us.

source "$DEVUP/shell/functions.sh"
source "$DEVUP/shell/aliases.sh"
source "$DEVUP/shell/env.sh"

## platform

case "$(uname -s)" in
  Darwin) sourceif "$DEVUP/shell/os/macos.sh" ;;
  Linux)  sourceif "$DEVUP/shell/os/linux.sh" ;;
esac

## homebrew
#
# Apple Silicon, Intel and Linuxbrew all put it somewhere different.

for __candidate in \
  /opt/homebrew/bin/brew \
  /usr/local/bin/brew \
  /home/linuxbrew/.linuxbrew/bin/brew \
  "$HOME/.linuxbrew/bin/brew"
do
  if [ -x "$__candidate" ]; then
    eval "$("$__candidate" shellenv)"
    break
  fi
done
unset __candidate

## mise
#
# Manages ruby, python and node versions. Global defaults live in ~/.mise.toml,
# which this repo links; per-project versions come from the project's own
# .mise.toml or .tool-versions.

for __candidate in \
  "$HOME/.local/bin/mise" \
  "${HOMEBREW_PREFIX:-}/bin/mise" \
  /usr/local/bin/mise \
  /usr/bin/mise
do
  if [ -x "$__candidate" ]; then
    case "${ZSH_VERSION:+zsh}${BASH_VERSION:+bash}" in
      zsh)  eval "$("$__candidate" activate zsh)" ;;
      bash) eval "$("$__candidate" activate bash)" ;;
    esac
    break
  fi
done
unset __candidate

## work and machine-specific config, neither of which is committed

sourceif "$DEVUP/shell/shopify.sh"
sourceif "$HOME/.shellrc.local"
