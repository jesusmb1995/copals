#!/bin/bash
set -euo pipefail
LABELS=$(jq -r '.pull_request.labels[].name' "${EVENT_PATH}")
IMAGE_LABEL=$(echo "${LABELS}" | grep "^${LABEL_PREFIX}" || true)
if [[ -n "${IMAGE_LABEL}" ]]; then
  echo "version=${IMAGE_LABEL#${LABEL_PREFIX}}" >> "${OUTPUT_PATH}"
else
  echo "version=${DEFAULT_VERSION}" >> "${OUTPUT_PATH}"
fi
