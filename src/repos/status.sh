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

# dir_hash12 <path>: short content hash via find+sha256sum (find excludes .git
# via hash_dir's own logic, but at this layer we just want a stable, cheap
# fingerprint). Implementation mirrors hash_dir from shlib/hash.ab.
dir_hash12() {
  local p="$1"
  find "$p" -type f -print0 2>/dev/null \
    | LC_ALL=C sort -z \
    | xargs -0 -r sha256sum 2>/dev/null \
    | sha256sum \
    | cut -c1-12
}

report_git_repo() {
  local dir="$1" name="$2"
  local dirty ahead behind pinned="" head=""
  dirty=$(git -C "$dir" status --short 2>/dev/null | wc -l | tr -d ' ') || dirty=0
  ahead=$(git -C "$dir" rev-list '@{u}..HEAD' 2>/dev/null | wc -l | tr -d ' ') || ahead=0
  behind=$(git -C "$dir" rev-list 'HEAD..@{u}' 2>/dev/null | wc -l | tr -d ' ') || behind=0
  head=$(git -C "$dir" rev-parse HEAD 2>/dev/null) || head=""

  pinned="${!name:-}"

  if [ -n "$pinned" ] && [ "$head" = "$pinned" ]; then
    if [ "$behind" -gt 0 ]; then
      printf "[upgradable] %s (-%d)\n" "$name" "$behind"
    else
      printf "[pinned] %s\n" "$name"
    fi
  elif [ -n "$pinned" ]; then
    printf "[upgradable] %s (pinned to %.10s..)\n" "$name" "$pinned"
  elif [ "$dirty" -gt 0 ]; then
    printf "[modified] %s (%d dirty)\n" "$name" "$dirty"
  elif [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
    printf "[diverged] %s (+%d -%d)\n" "$name" "$ahead" "$behind"
  elif [ "$ahead" -gt 0 ]; then
    printf "[ahead] %s (+%d)\n" "$name" "$ahead"
  elif [ "$behind" -gt 0 ]; then
    printf "[old] %s (-%d)\n" "$name" "$behind"
  else
    printf "[up-to-date] %s\n" "$name"
  fi
}

report_dir_repo() {
  local dir="$1" name="$2"
  local h
  h=$(dir_hash12 "$dir")
  if [ -z "$h" ]; then
    printf "[dir-empty] %s\n" "$name"
  else
    printf "[dir-hash]  %s %s\n" "$name" "$h"
  fi
}

# ponytail: walk walks every repo entry, branching on .git presence. No-global-
# flag switch needed — non-git may be mixed with git in one repos/ tree.
for item in "$repos_dir"/*/; do
  [ -d "$item" ] || continue
  name="$(basename "$item")"
  if [ -d "$item/.git" ]; then
    report_git_repo "$item" "$name"
  else
    report_dir_repo "$item" "$name"
  fi
done
