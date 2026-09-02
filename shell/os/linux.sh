#!/bin/false
# shellcheck shell=bash

# Linux-only shell configuration.

alias ls='ls --color=auto'   # GNU ls colours
alias o='xdg-open'

# Give scripts written on macOS somewhere to send output to.
if ! command -v pbcopy >/dev/null 2>&1 && command -v xclip >/dev/null 2>&1; then
  alias pbcopy='xclip -selection clipboard'
  alias pbpaste='xclip -selection clipboard -o'
fi
