#!/bin/bash
set -euo pipefail
REPO="${REPO:?REPO required}"
PR_NUMBER="${PR_NUMBER:?PR_NUMBER required}"
API_TOKEN="${API_TOKEN:?API_TOKEN required}"
EVENT_PATH="${EVENT_PATH:?EVENT_PATH required}"
LABEL_PREFIX="${LABEL_PREFIX:-test-image:}"

labels=$(jq -r '.pull_request.labels[].name' "${EVENT_PATH}" | grep "^${LABEL_PREFIX}" || true)

if [ -z "$labels" ]; then
  echo "no stale test-image labels to remove"
  exit 0
fi

for label in $labels; do
  echo "removing stale label: $label"
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X DELETE \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO}/issues/${PR_NUMBER}/labels/${label}")
  echo "  -> HTTP $http_code"
done
