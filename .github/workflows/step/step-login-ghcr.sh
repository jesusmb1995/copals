#!/bin/bash
set -euo pipefail
echo "${REGISTRY_TOKEN}" | podman login "${REGISTRY}" -u "${REGISTRY_USER}" --password-stdin
