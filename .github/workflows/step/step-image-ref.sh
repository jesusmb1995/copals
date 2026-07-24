#!/bin/bash
set -euo pipefail
IMAGE="${IMAGE_BASE}:${VERSION}"
if podman pull "${IMAGE}" 2>/dev/null; then
  echo "ref=${IMAGE}" >> "${OUTPUT_PATH}"
else
  echo "No published image found, building from source..."
  podman build --platform linux/amd64 -t "${SOURCE_IMAGE_TAG}" .
  echo "ref=${SOURCE_IMAGE_TAG}" >> "${OUTPUT_PATH}"
fi
