#!/bin/sh
# Claude Code status line — mirrors robbyrussell Oh My Zsh theme
# Receives JSON on stdin from Claude Code

input=$(cat)

# Current directory (basename, like %c in robbyrussell)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
dir=$(basename "$cwd")

# Git branch (skip optional lock flags for speed)
branch=""
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cwd" -c gc.auto=0 symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$cwd" -c gc.auto=0 rev-parse --short HEAD 2>/dev/null)
fi

# Model display name
model=$(echo "$input" | jq -r '.model.display_name // ""')

# Context remaining percentage (only shown after first API call)
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Build the line
# ➜  <dir>  git:(<branch>)  [model]  ctx:XX%
printf '\033[1;32m➜\033[0m  \033[0;36m%s\033[0m' "$dir"

if [ -n "$branch" ]; then
  printf '  \033[1;34mgit:(\033[0;31m%s\033[1;34m)\033[0m' "$branch"
fi

if [ -n "$model" ]; then
  printf '  \033[0;35m%s\033[0m' "$model"
fi

if [ -n "$remaining" ]; then
  printf '  \033[0;33mctx:%s%%\033[0m' "$(printf '%.0f' "$remaining")"
fi

printf '\n'
