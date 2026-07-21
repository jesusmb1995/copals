#!/usr/bin/env bash
set -euo pipefail

self_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$self_dir/../.." && pwd)"
scripts_dir="$self_dir/repos"

sub="${1:-}"
path="${2:-}"

if [ -z "$sub" ] || [ -z "$path" ]; then
    echo "Usage: copals repos <status|push|pull> <path>"
    echo ""
    echo "Operate on all git repos under <path>/repos/"
    echo "  status <path>    Show git status of each repo"
    echo "  push   <path>    Commit and push changes to each repo"
    echo "  pull   <path>    Pull latest updates for each repo"
    exit 1
fi

case "$sub" in
    status|push|pull)
        script="$scripts_dir/$sub.sh"
        [ -f "$script" ] || { echo "repos: internal error: $script not found" >&2; exit 1; }
        exec bash "$script" "$project_root/$path"
        ;;
    *)
        echo "repos: unknown subcommand: $sub" >&2
        exit 1
        ;;
esac
