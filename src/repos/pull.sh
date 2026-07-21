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
  echo "[$name] pulling..."
  git -C "$item" pull
done
