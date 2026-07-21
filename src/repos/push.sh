#!/usr/bin/env bash
set -euo pipefail

target="${1:-}"
if [ -z "$target" ] || [ ! -d "$target" ]; then
  echo "Usage: $0 <dir>" >&2
  exit 1
fi

repos_dir="$target/repos"
[ -d "$repos_dir" ] || { echo "no repos dir at $repos_dir" >&2; exit 1; }

for item in "$repos_dir"/*/; do
  [ -d "$item/.git" ] || continue
  name="$(basename "$item")"
  dirty=$(git -C "$item" status --short 2>/dev/null | wc -l | tr -d ' ') || dirty=0
  unpushed=$(git -C "$item" rev-list '@{u}..HEAD' 2>/dev/null | wc -l | tr -d ' ') || unpushed=0

  if [ "$dirty" -gt 0 ]; then
    echo "[$name] dirty ($dirty files) — committing + pushing..."
    git -C "$item" add -A
    git -C "$item" commit -m "quick update" || true
    git -C "$item" push
    echo "[$name] pushed"
  elif [ "$unpushed" -gt 0 ]; then
    echo "[$name] $unpushed unpushed commit(s) — pushing..."
    git -C "$item" push
    echo "[$name] pushed"
  else
    echo "[$name] clean, skipped"
  fi
done
