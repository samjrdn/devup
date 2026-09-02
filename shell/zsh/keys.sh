#!/usr/bin/env zsh

bindkey '\e[H' beginning-of-line
bindkey '\e[F' end-of-line
bindkey '\e[1;9H' beginning-of-line
bindkey '\e[1;9F' end-of-line
bindkey '\e\e[D' backward-word
bindkey '\e\e[C' forward-word
