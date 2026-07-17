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
#
# Nested podman (container build/test steps run podman from inside the copals
# image, reusing the HOST podman daemon):
#   - The container runs with --network host so it shares the podman machine
#     VM's network namespace. The VM exposes its podman socket over TCP via a
#     socat forwarder; the nested `podman` client reaches it at
#     CONTAINER_HOST=tcp://127.0.0.1:<COPALS_PODMAN_PORT> and reuses the host
#     image/store — nothing is duplicated.
#   - On Apple Silicon the VM must run x86_64 containers via Rosetta (not
#     qemu-user, which crashes Go binaries like podman). See
#     scripts/setup-podman-machine.sh to enable Rosetta + the forwarder.
#   - The nested podman runs over the VM's overlayfs, so its storage driver is
#     forced to "vfs" (overlay-on-overlay is unsupported); see COPALS_STORAGE_DRIVER.
#   - On native Linux you can instead mount the host socket and set
#     CONTAINER_HOST=unix:///run/podman/podman.sock with COPALS_NETWORK="".

COPALS_IMAGE="${COPALS_IMAGE:-copals:dev}"
COPALS_RUN="${COPALS_RUN:-auto}"
# Network mode for the copals container. "host" is required for nested podman on
# macOS (the VM's loopback forwarder is only reachable that way). Set to "" for
# bridge networking (e.g. native Linux with a mounted socket).
COPALS_NETWORK="${COPALS_NETWORK:-host}"
# TCP port the VM's socat forwarder listens on (see scripts/setup-podman-machine.sh).
COPALS_PODMAN_PORT="${COPALS_PODMAN_PORT:-9999}"

# Resolve the directory this script lives in (POSIX, no CDPATH leakage).
self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# In-container setup: when launched from inside the copals image (not native),
# make sure nested `podman` calls reuse the host daemon instead of failing to
# start an in-container one.
setup_in_container() {
    if [ "${COPALS_IN_CONTAINER:-0}" != "1" ]; then
        return 0
    fi

    # Where the nested podman client should talk to. With --network host the
    # container shares the VM's loopback, so the forwarder is at 127.0.0.1.
    if [ -z "${CONTAINER_HOST:-}" ]; then
        export CONTAINER_HOST="tcp://127.0.0.1:${COPALS_PODMAN_PORT}"
    fi
    export DOCKER_HOST="$CONTAINER_HOST"

    if ! command -v podman >/dev/null 2>&1; then
        printf 'copals: nested podman requested but no podman client found in image.\n' >&2
        printf '       Rebuild the image (install.sh podman) and run\n' >&2
        printf '       scripts/setup-podman-machine.sh once on the host.\n' >&2
        exit 1
    fi
}

# Run inside the copals container.
#
# --network host makes the container share the podman machine VM's network
# namespace, so the nested podman client can reach the VM's socat socket
# forwarder at 127.0.0.1:$COPALS_PODMAN_PORT. On native Linux, set
# COPALS_NETWORK="" and mount the host socket instead.
run_container() {
    network_args=""
    if [ -n "$COPALS_NETWORK" ]; then
        network_args="--network=$COPALS_NETWORK"
    fi

    # CONTAINER_HOST for the *container* only. run_container passes the host's
    # CONTAINER_HOST through via -e, but on macOS the host's value is the podman
    # machine connection (ssh://...), which is useless — and worse, would make
    # the host podman client (launching this container) try to use the nested
    # daemon. So compute the in-container address here and pass it explicitly,
    # then UNSET it for the host podman process so it keeps its own connection.
    container_host="${COPALS_CONTAINER_HOST:-tcp://127.0.0.1:${COPALS_PODMAN_PORT}}"
    unset CONTAINER_HOST DOCKER_HOST

    exec podman run --rm \
        $network_args \
        -v "$PWD":"$PWD" -w "$PWD" \
        -v copals-cache:/root/.cache \
        -e COPALS_IN_CONTAINER=1 \
        -e COPALS_PODMAN_PORT="$COPALS_PODMAN_PORT" \
        -e CONTAINER_HOST="$container_host" \
        -e DOCKER_HOST="$container_host" \
        -e STORAGE_DRIVER="${COPALS_STORAGE_DRIVER:-vfs}" \
        -e CONTAINERS_SECCOMP_PROFILE="${COPALS_SECCOMP_PROFILE:-unconfined}" \
        "$COPALS_IMAGE" "$@"
}

# Resolve the copals source tree directory.
#
# Prefer the installed location (/usr/lib/copals). This matters when copals.sh
# runs INSIDE the copals container: the host repo is bind-mounted at the same
# absolute path, so $self_dir also looks valid but its vendor/ tools are not
# populated (they live only in the image at /usr/lib/copals/vendor). The
# installed tree is always self-contained, so it wins when present.
get_lib_dir() {
    if [ -f /usr/lib/copals/src/copals.ab ] && [ -d /usr/lib/copals/vendor ]; then
        printf '%s' /usr/lib/copals
        return 0
    fi
    for candidate in "$self_dir"; do
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
    # Preserve the caller's working directory. vars.ab derives PROJECT_ROOT from
    # pwd() and expects it to be the user's repo root (the dir holding copals/
    # and user/), NOT the install prefix parent (e.g. /usr/lib). Running from
    # the original PWD keeps relative args like 'user' and jsonnet's cwd-relative
    # 'lib/' imports resolving correctly.
    orig_pwd="$PWD"
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
    cd "$orig_pwd" || {
        printf 'copals: could not cd to %s\n' "$orig_pwd" >&2
        exit 1
    }
    exec bash "$output" "$@"
}

# Run the main copals entrypoint script.
run_local() {
    run_amber "src/copals.ab" "$@"
}

# Whether the copals container image is available.
image_exists() {
    command -v podman >/dev/null 2>&1 && podman image exists "$COPALS_IMAGE" 2>/dev/null
}

# Clone user repos on the HOST (not inside the container) so git credentials
# are available. Uses the copals container only to render the jsonnet config.
run_fetch_repos() {
    for candidate in "/usr/lib/copals" "$self_dir"; do
        fetch_script="$candidate/src/fetch_user_repos.sh"
        if [ -f "$fetch_script" ]; then
            exec sh "$fetch_script" "$@"
        fi
    done
    printf 'copals: could not find src/fetch_user_repos.sh\n' >&2
    exit 1
}

# Dispatch when executed directly (not sourced).
case "${0##*/}" in
    copals.sh|copals)
        setup_in_container
        if [ "${COPALS_IN_CONTAINER:-0}" = "1" ]; then
            # Already inside the copals container: run natively. Never call
            # run_container here — that would re-launch copals:dev (recursive
            # container-in-container) and the nested podman calls below reuse
            # the host daemon via CONTAINER_HOST instead.
            run_local "$@"
        else
            # user-clone runs on the host directly (needs git credentials).
            if [ "${1:-}" = "user-clone" ]; then
                shift
                run_fetch_repos "$@"
            fi
            case "$COPALS_RUN" in
                local) run_local "$@" ;;
                container) run_container "$@" ;;
                auto)
                    if image_exists; then
                        run_container "$@"
                    else
                        run_local "$@"
                    fi
                    ;;
            esac
        fi
        ;;
esac
