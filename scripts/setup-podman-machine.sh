#!/bin/sh
# One-time setup for running copals with nested podman on macOS Apple Silicon.
#
# What this does (inside the podman machine VM):
#   1. Enables Rosetta so x86_64 containers run natively-fast and stably.
#      qemu-user emulation (the default without Rosetta) crashes Go binaries
#      such as podman (SIGSEGV in runtime.netpoll). See:
#      https://developer.ibm.com/tutorials/running-x86-64-containers-mac-silicon-m1/
#   2. Installs a systemd unit that forwards the VM's rootless podman socket to
#      TCP 127.0.0.1:$PORT. The copals container runs with --network host, so
#      its nested `podman` client reaches the VM daemon at that address and
#      reuses the host image/container store (nothing is duplicated).
#
# After running this once, rebuild the copals image as x86_64 and use copals:
#   ./install.sh podman          # already does: podman build --arch amd64
#   copals.sh pipeline user config_gpersonal jberlanga-devtools
#
# Re-run safely; it is idempotent.

set -eu

PORT="${COPALS_PODMAN_PORT:-9999}"
UNIT="copals-podman-forward.service"

# Run a command in the podman machine VM over SSH.
vm() { podman machine ssh -- "$@"; }
vm_root() { podman machine ssh -- sudo "$@"; }

echo "==> Checking podman machine is running"
if ! podman machine list --format '{{.Name}} {{.Running}}' 2>/dev/null | grep -q true; then
    echo "error: no running podman machine. Run: podman machine start" >&2
    exit 1
fi

echo "==> Enabling Rosetta for x86_64 containers in the VM"
vm_root mkdir -p /etc/containers
vm_root touch /etc/containers/enable-rosetta
# Activate Rosetta now (register binfmt, drop qemu-x86_64). Safe to re-run:
# the activation script is a no-op once rosetta is already registered.
if ! vm 'head -1 /proc/sys/fs/binfmt_misc/rosetta 2>/dev/null' | grep -q enabled; then
    vm_root /var/usrlocal/bin/rosetta-activation.sh || true
fi
vm 'head -1 /proc/sys/fs/binfmt_misc/rosetta' | grep -q enabled \
    && echo "    Rosetta: enabled" \
    || { echo "error: Rosetta did not activate" >&2; exit 1; }

echo "==> Detecting VM podman socket"
VM_UID=$(vm id -u)
VM_SOCK="/run/user/${VM_UID}/podman/podman.sock"
vm "ls ${VM_SOCK}" >/dev/null 2>&1 \
    || { echo "error: socket not found at ${VM_SOCK}" >&2; exit 1; }
echo "    socket: ${VM_SOCK}"

echo "==> Installing systemd forwarder ${UNIT} (TCP 127.0.0.1:${PORT} -> ${VM_SOCK})"
# Clear any manually-started socat holding the port so the unit can bind.
vm_root pkill -f "socat TCP-LISTEN:${PORT}" 2>/dev/null || true
UNIT_CONTENT="[Unit]
Description=Copals: forward podman socket to TCP for nested podman
After=podman.socket network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP-LISTEN:${PORT},fork,reuseaddr,bind=127.0.0.1 UNIX-CONNECT:${VM_SOCK}
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
"
printf '%s\n' "$UNIT_CONTENT" | vm_root tee "/etc/systemd/system/${UNIT}" >/dev/null
vm_root systemctl daemon-reload
vm_root systemctl enable --now "${UNIT}"

echo "==> Verifying forwarder"
vm "systemctl is-active ${UNIT}" | grep -q active \
    && echo "    ${UNIT}: active" \
    || { echo "error: ${UNIT} not active" >&2; exit 1; }

echo "==> Ensuring seccomp profile is available to the VM podman daemon"
# The nested podman build runs in the VM daemon, which reads the default
# seccomp profile from /etc/containers/seccomp.json. FCOS ships it under
# /usr/share/containers/seccomp.json but does not symlink it, so builds fail
# with "opening seccomp profile failed". Link it into place.
if vm "test -e /usr/share/containers/seccomp.json"; then
    vm_root mkdir -p /etc/containers
    vm_root ln -sf /usr/share/containers/seccomp.json /etc/containers/seccomp.json
    echo "    seccomp profile: linked"
else
    # Fallback: tell the VM podman to run unconfined if no profile exists.
    vm_root mkdir -p /etc/containers
    printf '[containers]\nseccomp_profile = "unconfined"\n' \
        | vm_root tee /etc/containers/containers.conf >/dev/null
    echo "    seccomp profile: set unconfined in containers.conf"
fi

echo
echo "Done. copals nested podman is ready."
echo "  Rosetta : x86_64 containers run via Rosetta"
echo "  Forward : 127.0.0.1:${PORT} -> ${VM_SOCK}"
echo "  seccomp : available to the VM podman daemon"
echo
echo "Build the x86_64 image and run copals:"
echo "  cd copals && bash install.sh podman   # builds linux/amd64"
echo "  copals.sh pipeline user config_gpersonal jberlanga-devtools"
