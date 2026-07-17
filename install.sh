#!/bin/sh
set -eu

# TODO install_locally, for dev on current repo, e.g. integrated with git...? or just explain on README.md how to integrate.
# TODO install_with_podman if available...
# TODO version?
# TODO uninstall?
# TODO remove tests on deployed ver...

self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

print_help() {
cat <<'EOF'
Install copals via one of two modes:
  install.sh local  [prefix]      install to <prefix> (default: /usr)
  install.sh podman [args...]     build the copals container image; <args>
                                  are passed through to `podman build`
  install.sh help                 show this help

When the Dockerfile invokes this script it calls `install.sh local /usr`.
./dependencies.sh is skipped whenever ./vendor is already populated.

Local layout produced under <prefix>:
  <prefix>/bin/copals            sh entrypoint
  <prefix>/lib/copals/src/       amber sources (copals.ab, main-generate.ab, ...)
  <prefix>/lib/copals/vendor/    amber, jq, j2, jsonnet, jsonschema, ...
  <prefix>/lib/copals/config.schema.json
EOF
}

# Ensure vendored tools are present; fetch them only if missing.
ensure_vendor() {
    if [ ! -d "$self_dir/vendor" ] || [ -z "$(ls -A "$self_dir/vendor" 2>/dev/null)" ]; then
        echo "install: vendor/ missing, fetching dependencies..." >&2
        sh "$self_dir/dependencies.sh" "$self_dir/vendor"
    fi
}

# Install the source tree + vendored tools + entrypoint under <prefix>.
install_local() {
    prefix="${1:-/usr}"
    ensure_vendor

    lib_dir="$prefix/lib/copals"
    bin_dir="$prefix/bin"
    install -d "$bin_dir" "$lib_dir/src" "$lib_dir/vendor"

    cp -R "$self_dir/src/." "$lib_dir/src/"
    cp -R "$self_dir/vendor/." "$lib_dir/vendor/"
    cp "$self_dir/res/config.schema.json" "$lib_dir/"

    install -m 0755 "$self_dir/copals.sh" "$bin_dir/copals"

    echo "installed copals:"
    echo "  entrypoint : $bin_dir/copals"
    echo "  lib        : $lib_dir"
}

install_podman() {
    if ! command -v podman >/dev/null 2>&1; then
        cat >&2 <<'EOF'
install: 'podman' was not found on your PATH.

Install Homebrew first:
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

then install podman with:
  brew install podman
EOF
        exit 1
    fi

    # TODO extensions, podman within the container? To all copals commands without having to install anything on host...

    COPALS_IMAGE="${COPALS_IMAGE:-copals:dev}"
    # The vendored tools (jsonnet, jq, jsonschema, ...) are x86_64 binaries, so
    # the image must be built linux/amd64. On Apple Silicon run
    # scripts/setup-podman-machine.sh once to enable Rosetta (stable x86_64),
    # otherwise amd64 containers fall back to qemu-user which crashes Go tools.
    COPALS_BUILD_ARCH="${COPALS_BUILD_ARCH:-amd64}"

    # Podman installation inside the image is optional. Pass
    # INSTALL_PODMAN=false to skip the 43 MiB static podman-remote binary when
    # only generation commands are needed (no nested podman builds).
    PODMAN_STAGE="copals-with-podman"
    if [ "${INSTALL_PODMAN:-true}" = "false" ]; then
        PODMAN_STAGE="copals-without-podman"
    fi

    podman build --arch "$COPALS_BUILD_ARCH" \
        --build-arg "PODMAN_STAGE=$PODMAN_STAGE" \
        -t "$COPALS_IMAGE" "$@" "$self_dir"
    echo "built image $COPALS_IMAGE ($COPALS_BUILD_ARCH, podman=${INSTALL_PODMAN:-true})"
}

mode="${1:-help}"
[ $# -gt 0 ] && shift
case "$mode" in
    local)  install_local "${1:-/usr}" ;;
    podman) install_podman "$@" ;;
    help|-h|--help) print_help ;;
    *)
        echo "install: unknown mode '$mode' (expected: local|podman|help)" >&2
        print_help >&2
        exit 1
        ;;
esac
