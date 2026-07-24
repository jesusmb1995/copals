#!/bin/bash
set -euo pipefail
podman tag "${IMAGE_TAG}" "${IMAGE_BASE}:${VERSION}"
podman push "${IMAGE_BASE}:${VERSION}"

podman tag "${NO_PODMAN_IMAGE_TAG}" "${IMAGE_BASE}:${VERSION}-no-podman"
podman push "${IMAGE_BASE}:${VERSION}-no-podman"

if [[ "${VERSION}" != *"-"* ]]; then
  podman tag "${IMAGE_BASE}:${VERSION}" "${IMAGE_BASE}:latest"
  podman push "${IMAGE_BASE}:latest"
fi
