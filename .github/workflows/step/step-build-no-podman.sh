#!/bin/bash
set -euo pipefail
podman build --platform linux/amd64 --target copals-without-podman -t "${IMAGE_TAG}" .
podman run --rm -v "${WORKSPACE}:/copals" -w /copals "${IMAGE_TAG}" \
  sh -c 'cp -r /usr/lib/copals/vendor/. /copals/vendor/ 2>/dev/null; COPALS_LIB_DIR=/copals sh /copals/test.sh'
