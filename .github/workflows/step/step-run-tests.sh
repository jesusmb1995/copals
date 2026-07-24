#!/bin/bash
set -euo pipefail
IMAGE_REF="${IMAGE_REF:?IMAGE_REF required}"
WORKSPACE="${WORKSPACE:?WORKSPACE required}"
podman run --rm --entrypoint sh -v "${WORKSPACE}:/copals" -w /copals "${IMAGE_REF}" \
  -c 'cp -r /usr/lib/copals/vendor/. /copals/vendor/ 2>/dev/null; COPALS_LIB_DIR=/copals sh /copals/test.sh'
