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
export COPALS_IMAGE
COPALS_SECURITY_IMAGE="${COPALS_SECURITY_IMAGE:-copals:security}"
export COPALS_SECURITY_IMAGE
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
    # Run without exec so callers (e.g. the generate --audit/--push pipeline)
    # can continue after generation finishes.
    bash "$output" "$@"
}

# Run the main copals entrypoint script.
run_local() {
    run_amber "src/copals.ab" "$@"
}

# Run `container launch-window` on the HOST while compiling inside the container.
#
# launch-window is special: at runtime it must run on the host (it detects the
# host OS via `uname` to pick the display transport — Linux->Xephyr,
# macOS->VNC/TigerVNC — and opens the host's VNC viewer). But the amber compiler
# is only available (and only runnable) inside the copals container: the
# vendored `amber` binary is Linux x86-64 and cannot execute on macOS.
#
# So: compile launch_window.ab -> .sh INSIDE copals:dev (amber runs on Linux
# there), writing into the bind-mounted repo, then execute that self-contained
# compiled bash script directly on the host. amber build inlines all imported
# modules, so the single .sh needs no amber/vendor tools at runtime — only
# podman + nc + pgrep + a VNC viewer, all present on the host.
run_launch_window_host() {
    src_rel="src/container/launch_window.ab"
    out_rel="src/container/launch_window.sh"

    # Locate the host repo's copals source tree (never /usr/lib/copals, which
    # only exists inside the image). self_dir is <repo>/copals.
    host_src="$self_dir/$src_rel"
    host_out="$self_dir/$out_rel"
    if [ ! -f "$host_src" ]; then
        printf 'copals: launch-window source not found at %s\n' "$host_src" >&2
        exit 1
    fi

    # Compile inside the container. The repo is bind-mounted at the same path,
    # so the compiled .sh lands in the host tree at $host_out. The container's
    # own installed tree (/usr/lib/copals) has a working Linux amber on PATH via
    # its vendor dir.
    printf 'copals: compiling launch-window inside %s ...\n' "$COPALS_IMAGE" >&2
    podman run --rm \
        -v "$PWD":"$PWD" -w "$PWD" \
        --entrypoint /bin/sh \
        "$COPALS_IMAGE" -c \
        'PATH=/usr/lib/copals/vendor:$PATH amber build "'"$host_src"'" "'"$host_out"'"' \
        || { printf 'copals: in-container amber build failed for launch-window\n' >&2; exit 1; }

    if [ ! -f "$host_out" ]; then
        printf 'copals: expected compiled launcher not found at %s\n' "$host_out" >&2
        exit 1
    fi

    # Run the compiled launcher on the host. Drop the leading "container" and
    # "launch-window" tokens; pass the rest (image + flags) as the launcher's
    # own args (main() -> main_launch_window).
    shift 2 2>/dev/null || true
    exec bash "$host_out" "$@"
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

# Run inside the copals container but RETURN (do not exec) so the caller can
# run more steps afterward (audit, publish). Mirrors run_container minus exec.
run_container_noreplace() {
    network_args=""
    if [ -n "$COPALS_NETWORK" ]; then
        network_args="--network=$COPALS_NETWORK"
    fi
    container_host="${COPALS_CONTAINER_HOST:-tcp://127.0.0.1:${COPALS_PODMAN_PORT}}"
    unset CONTAINER_HOST DOCKER_HOST
    podman run --rm \
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

# --- generate/pipeline --audit / --push post-processing --------------------
#
# `copals <generate|pipeline> ... [--audit] [--push]` runs the subcommand
# first (non-exec), then hands off to postprocess.ab, compiled in-container and
# run on the HOST (like launch-window/publish). postprocess.ab owns the audit
# (copals:security container) and publish (git wrap + push) logic — amber, not
# raw shell, handles the flags and ordering.
#
# The SAME original args (still including --audit/--push) are passed verbatim
# to both the subcommand and `postprocess.sh`; each consumes the flags it
# cares about via amber `has_flag`. No shell-side arg stripping/parsing needed.
#
# $1 = subcommand to run first (generate|pipeline); remaining "$@" = its args
#      (e.g. user config dest --audit), also forwarded to postprocess.
run_and_postprocess() {
    subcmd="$1"; shift
    # Run the subcommand first (non-exec), with the flags still present.
    if [ "$COPALS_RUN" = "local" ] || { [ "$COPALS_RUN" = "auto" ] && ! image_exists; }; then
        run_local "$subcmd" "$@"; step_rc=$?
    else
        run_container_noreplace "$subcmd" "$@"; step_rc=$?
    fi
    [ "$step_rc" -ne 0 ] && { printf 'copals: %s failed (rc=%d)\n' "$subcmd" "$step_rc" >&2; exit "$step_rc"; }

    # Compile postprocess.ab -> .sh, then run the self-contained .sh on the
    # HOST with the SAME args. Mirrors the generate-step dispatch above: local
    # compile with the vendored amber when COPALS_RUN=local or (auto + no
    # image); in-container compile (writing into the bind-mounted repo)
    # otherwise. Lets bare-metal users run `generate --audit` without building
    # copals:dev, as long as `copals/dependencies.sh` populated vendor/.
    post_src="$self_dir/src/gen/postprocess.ab"
    post_out="$self_dir/src/gen/postprocess.sh"
    if [ ! -f "$post_src" ]; then
        printf 'copals: postprocess source not found at %s\n' "$post_src" >&2
        exit 1
    fi
    if [ "$COPALS_RUN" = "local" ] || { [ "$COPALS_RUN" = "auto" ] && ! image_exists; }; then
        lib_dir=$(get_lib_dir) || {
            printf 'copals: could not locate source tree (src/copals.ab + vendor/) for local compile\n' >&2
            printf 'hint: run `copals/dependencies.sh` to populate copals/vendor/\n' >&2
            exit 1
        }
        printf 'copals: compiling postprocess locally ...\n' >&2
        PATH="$lib_dir/vendor:$PATH" amber build "$post_src" "$post_out" || {
            printf 'copals: local amber build failed for postprocess\n' >&2
            exit 1
        }
    else
        printf 'copals: compiling postprocess inside %s ...\n' "$COPALS_IMAGE" >&2
        podman run --rm \
            -v "$PWD":"$PWD" -w "$PWD" \
            --entrypoint /bin/sh \
            "$COPALS_IMAGE" -c \
            'PATH=/usr/lib/copals/vendor:$PATH amber build "'"$post_src"'" "'"$post_out"'"' \
            || { printf 'copals: in-container amber build failed for postprocess\n' >&2; exit 1; }
    fi
    if [ ! -f "$post_out" ]; then
        printf 'copals: expected compiled postprocess not found at %s\n' "$post_out" >&2
        exit 1
    fi

    bash "$post_out" "$@"
    exit $?
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
            # generate --audit / --push: run generate (the flags are harmless
            # to it), then hand off to postprocess.ab (compiled in-container,
            # run on host) with the SAME args. Plain `generate` keeps the
            # normal fast path.
            if ( [ "${1:-}" = "generate" ] || [ "${1:-}" = "pipeline" ] ) \
               && ( echo "$*" | grep -q -- '--audit' || echo "$*" | grep -q -- '--push' ); then
                subcmd="$1"; shift
                run_and_postprocess "$subcmd" "$@"
            fi
            # user-clone runs on the host directly (needs git credentials).
            if [ "${1:-}" = "user-clone" ]; then
                shift
                run_fetch_repos "$@"
            fi
            # launch-window must run on the host (see run_launch_window_host).
            # Only special-case it when we would otherwise run in the container
            # (image exists); with no image, local mode already runs on host.
            if [ "${1:-}" = "container" ] && [ "${2:-}" = "launch-window" ] \
               && [ "$COPALS_RUN" != "local" ] && image_exists; then
                run_launch_window_host "$@"
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
