#!/bin/bash
set -euo pipefail
podman run --rm -v "${WORKSPACE}:/copals" "${IMAGE_REF}" sh /copals/test.sh
