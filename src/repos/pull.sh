#!/usr/bin/env bash
set -euo pipefail

target="${1:-}"
if [ -z "$target" ] || [ ! -d "$target" ]; then
  echo "Usage: $0 <dir>" >&2
  exit 1
fi

repos_dir="$target/repos"
[ -d "$repos_dir" ] || { echo "no repos dir at $repos_dir" >&2; exit 1; }

versions_file="$repos_dir/version.sh"
[ -f "$versions_file" ] && source "$versions_file"

for item in "$repos_dir"/*/; do
  [ -d "$item/.git" ] || continue
  name="$(basename "$item")"
  pinned="${!name:-}"

  if [ -n "$pinned" ]; then
    echo "[$name] fetching pinned commit..."
    git -C "$item" fetch origin
    git -C "$item" checkout "$pinned"
  else
    echo "[$name] pulling latest..."
    git -C "$item" pull
    echo "${name}=\"$(git -C "$item" rev-parse HEAD)\"" >> "$versions_file"
  fi
done
