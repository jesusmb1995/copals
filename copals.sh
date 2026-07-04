#!/bin/sh
# Sourcable entrypoint for copals.
#
# Defines reusable functions for running amber scripts. No dispatch here —
# source this file and call run_amber / run_local / run_container directly.
#
# Run order when dispatching:
#   1. container : if podman is installed and the copals image exists, run
#                  inside it (the current dir is bind-mounted at the same path
#                  so generate operates on the host repo).
#   2. local     : run the amber source directly via the vendored amber binary.
#
# Force the local path with COPALS_RUN=local.
#
# Layouts supported (local path):
#   local dev : this script sits in <repo>/generation/, next to src/ and vendor/
#   global    : this script installed as /usr/bin/copals, with the source tree
#               (src/ + vendor/) installed under /usr/lib/copals/

COPALS_IMAGE="${COPALS_IMAGE:-copals:dev}"
COPALS_RUN="${COPALS_RUN:-auto}"

# Resolve the directory this script lives in (POSIX, no CDPATH leakage).
self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# Run inside the copals container.
run_container() {
    exec podman run --rm \
        -v "$PWD":"$PWD" -w "$PWD" \
        -v copals-cache:/root/.cache \
        "$COPALS_IMAGE" "$@"
}

# Resolve the copals source tree directory.
get_lib_dir() {
    for candidate in "$self_dir" "/usr/lib/copals"; do
        if [ -f "$candidate/src/copals.ab" ] && [ -d "$candidate/vendor" ]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

# Run an amber script from the copals source tree.
#
# Compiles the .ab source to .sh first, then runs the compiled script directly.
# This avoids E2BIG (Argument list too long) on `amber run` — the amber binary
# passes the entire compiled bash as a single `bash -c` argument, which can
# exceed ARG_MAX when the environment is large.
#
# TODO is dir/path safe for normal user? or will require wrt perm?
# Usage: run_amber <relative_script_path> [args...]
run_amber() {
    script="$1"; shift
    lib_dir=$(get_lib_dir) || {
        printf 'copals: could not locate source tree (src/copals.ab) and vendor/ dir\n' >&2
        printf 'searched: %s %s\n' "$self_dir" "/usr/lib/copals" >&2
        printf 'hint: build image `install.sh podman` or ensure `dependencies.sh` locally \n' >&2
        exit 1
    }
    PATH="$lib_dir/vendor:$PATH"; export PATH
    output="$lib_dir/${script%.ab}.sh"
    amber build "$lib_dir/$script" "$output" || {
        printf 'copals: amber build failed for %s\n' "$script" >&2
        exit 1
    }
    # vars.ab expects PROJECT_ROOT = pwd() to be the repo root (parent of copals/) # TODO fix
    cd "$lib_dir/.." || {
        printf 'copals: could not cd to project root (parent of %s)\n' "$lib_dir" >&2
        exit 1
    }
    exec bash "$output" "$@"
}

# Run the main copals entrypoint script.
run_local() {
    run_amber "src/copals.ab" "$@"
}

# Dispatch when executed directly (not sourced).
case "${0##*/}" in
    copals.sh|copals)
        run_local "$@"
        ;;
esac
