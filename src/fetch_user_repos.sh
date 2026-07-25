#!/bin/sh
set -eu

self_dir="$(cd "$(dirname "$0")" && pwd)"
copals_root="$(cd "$self_dir/.." && pwd)"
project_root="$(cd "$copals_root/.." && pwd)"

user_dir="${1:-}"
config_name="${2:-}"

if [ -z "$user_dir" ] || [ -z "$config_name" ]; then
  echo "Usage: copals user-clone <user_dir> <config_name>" >&2
  exit 1
fi

# Resolve jsonnet binary (project vendor > copals vendor > PATH)
if [ -x "$project_root/vendor/jsonnet" ]; then
  jsonnet="$project_root/vendor/jsonnet"
elif [ -x "$copals_root/vendor/jsonnet" ]; then
  jsonnet="$copals_root/vendor/jsonnet"
elif command -v jsonnet >/dev/null 2>&1; then
  jsonnet="jsonnet"
else
  echo "copals: jsonnet not found — run copals/dependencies.sh first" >&2
  exit 1
fi

# Resolve jq binary (project vendor > copals vendor > PATH)
if [ -x "$project_root/vendor/jq" ]; then
  jq="$project_root/vendor/jq"
elif [ -x "$copals_root/vendor/jq" ]; then
  jq="$copals_root/vendor/jq"
elif command -v jq >/dev/null 2>&1; then
  jq="jq"
else
  echo "copals: jq not found" >&2
  exit 1
fi

jsonnet_lib_dir="$copals_root/src"

config_path="$user_dir/config-presets/$config_name.jsonnet"
if [ ! -f "$config_path" ]; then
  config_path="$user_dir/config-presets/$config_name.json"
fi
if [ ! -f "$config_path" ]; then
  echo "copals: config preset not found: '$config_name' in $user_dir/config-presets/" >&2
  exit 1
fi

rendered="$("$jsonnet" -J "$jsonnet_lib_dir" "$config_path" 2>/dev/null)" || {
  echo "copals: jsonnet render failed for $config_path" >&2
  exit 1
}

repo_list="$(echo "$rendered" | "$jq" -r '.repositories[] | select(.enabled == true and .clone == true) | "\(.id)\t\(.url)"' 2>/dev/null)" || {
  echo "copals: no clone-enabled repos found in config" >&2
  exit 0
}

repos_dir="$user_dir/repos"

echo "$repo_list" | while IFS='	' read -r repo_id repo_url; do
  [ -z "$repo_id" ] && continue
  target_dir="$repos_dir/$repo_id"

  if [ -d "$target_dir/.git" ]; then
    echo "copals: updating $repo_id ($repo_url) in $target_dir"
    git -C "$target_dir" pull --ff-only 2>&1 | sed 's/^/  /'
  else
    mkdir -p "$(dirname "$target_dir")"
    echo "copals: cloning $repo_id from $repo_url into $target_dir"
    git clone "$repo_url" "$target_dir" 2>&1 | sed 's/^/  /'
  fi
done
