#!/usr/bin/env bash
set -euo pipefail

target="${1:-}"
if [ -z "$target" ] || [ ! -d "$target" ]; then
  echo "Usage: $0 <dir>" >&2
  exit 1
fi

report_repo() {
  local dir="$1" name="$2"
  local dirty=0 ahead=0 behind=0
  dirty=$(git -C "$dir" status --short 2>/dev/null | wc -l | tr -d ' ') || dirty=0
  ahead=$(git -C "$dir" rev-list '@{u}..HEAD' 2>/dev/null | wc -l | tr -d ' ') || ahead=0
  behind=$(git -C "$dir" rev-list 'HEAD..@{u}' 2>/dev/null | wc -l | tr -d ' ') || behind=0

  if [ "$dirty" -gt 0 ]; then
    printf "[%s] %s (%d dirty)\n" "modified" "$name" "$dirty"
  elif [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
    printf "[%s] %s (+%d -%d)\n" "diverged" "$name" "$ahead" "$behind"
  elif [ "$ahead" -gt 0 ]; then
    printf "[%s] %s (+%d)\n" "ahead" "$name" "$ahead"
  elif [ "$behind" -gt 0 ]; then
    printf "[%s] %s (-%d)\n" "old" "$name" "$behind"
  else
    printf "[%s] %s\n" "up-to-date" "$name"
  fi
}

repos_dir="$target/repos"
if [ ! -d "$repos_dir" ]; then
  echo "no repos dir at $repos_dir" >&2
  exit 1
fi

for item in "$repos_dir"/*/; do
  [ -d "$item/.git" ] || continue
  name="$(basename "$item")"
  report_repo "$item" "$name"
done
