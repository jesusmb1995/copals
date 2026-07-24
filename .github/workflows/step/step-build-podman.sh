#!/bin/bash
set -euo pipefail
podman build --platform linux/amd64 -t "${IMAGE_TAG}" .
podman run --rm --entrypoint sh -v "${WORKSPACE}:/copals" -w /copals "${IMAGE_TAG}" /copals/test.sh
