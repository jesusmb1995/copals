#!/usr/bin/env bash
set -euo pipefail

target="${1:-}"
if [ -z "$target" ] || [ ! -d "$target" ]; then
  echo "Usage: $0 <dir>" >&2
  exit 1
fi

repos_dir="$target/repos"
if [ ! -d "$repos_dir" ]; then
  echo "no repos dir at $repos_dir" >&2
  exit 1
fi

versions_file="$repos_dir/version.sh"

# ponytail: source version.sh to get pinned commits as shell vars
[ -f "$versions_file" ] && source "$versions_file"

report_repo() {
  local dir="$1" name="$2"
  local dirty=0 ahead=0 behind=0 pinned="" head=""
  dirty=$(git -C "$dir" status --short 2>/dev/null | wc -l | tr -d ' ') || dirty=0
  ahead=$(git -C "$dir" rev-list '@{u}..HEAD' 2>/dev/null | wc -l | tr -d ' ') || ahead=0
  behind=$(git -C "$dir" rev-list 'HEAD..@{u}' 2>/dev/null | wc -l | tr -d ' ') || behind=0
  head=$(git -C "$dir" rev-parse HEAD 2>/dev/null) || head=""

  pinned="${!name:-}"

  if [ -n "$pinned" ] && [ "$head" = "$pinned" ]; then
    if [ "$behind" -gt 0 ]; then
      printf "[%s] %s (-%d)\n" "upgradable" "$name" "$behind"
    else
      printf "[%s] %s\n" "pinned" "$name"
    fi
  elif [ -n "$pinned" ]; then
    printf "[%s] %s (pinned to %.10s..)\n" "upgradable" "$name" "$pinned"
  elif [ "$dirty" -gt 0 ]; then
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

for item in "$repos_dir"/*/; do
  [ -d "$item/.git" ] || continue
  name="$(basename "$item")"
  report_repo "$item" "$name"
done
