#!/bin/bash
set -euo pipefail
podman build --platform linux/amd64 -t "${IMAGE_TAG}" .
podman run --rm --entrypoint sh -v "${WORKSPACE}:/copals" -w /copals "${IMAGE_TAG}" \
  -c 'cp -r /usr/lib/copals/vendor/. /copals/vendor/ 2>/dev/null; COPALS_LIB_DIR=/copals sh /copals/test.sh'
