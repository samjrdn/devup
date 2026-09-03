#!/bin/false
# shellcheck shell=bash

# Linux-only shell configuration.

alias ls='ls --color=auto'   # GNU ls colours
alias o='xdg-open'

# Debian renames some binaries (fd -> fdfind, bat -> batcat). setup.sh puts
# shims in ~/.local/bin rather than defining aliases here, because an alias is
# only expanded by an interactive shell and would leave scripts broken.

# Give scripts written on macOS somewhere to send output to.
if ! command -v pbcopy >/dev/null 2>&1 && command -v xclip >/dev/null 2>&1; then
  alias pbcopy='xclip -selection clipboard'
  alias pbpaste='xclip -selection clipboard -o'
fi
