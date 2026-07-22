#!/usr/bin/env bash
set -eu

self_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$self_dir/../.." && pwd)"
scripts_dir="$self_dir/repos"

sub="${1:-}"
path="${2:-}"

if [ -z "$sub" ]; then
  echo "Missing command: $@"
fi

if [ -z "$path" ]; then
  echo "Missing path: $@"
fi

case "$sub" in
    status|push|pull)
        if [ -z "$path" ]; then
            echo "repos: missing <path> for $sub" >&2
            exit 1
        fi
        script="$scripts_dir/$sub.sh"
        [ -f "$script" ] || { echo "repos: internal error: $script not found" >&2; exit 1; }
        exec bash "$script" "$project_root/$path"
        ;;
    -h|--help|help|"")
        echo "Usage: copals repos <status|push|pull> <path>"
        echo ""
        echo "  status <path>    Git status of each repo under <path>/repos/"
        echo "  push   <path>    Commit and push changes in each repo under <path>/repos/"
        echo "  pull   <path>    Pull latest for each repo under <path>/repos/"
        exit 0
        ;;
    *)
        echo "repos: unknown subcommand: $sub" >&2
        exit 1
        ;;
esac
