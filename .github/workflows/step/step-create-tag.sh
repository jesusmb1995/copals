#!/bin/bash
set -euo pipefail
if git rev-parse -q --verify "refs/tags/${VERSION}" >/dev/null; then
  echo "tag ${VERSION} already exists, skipping"
  exit 0
fi
git config user.name "${GIT_USER_NAME}"
git config user.email "${GIT_USER_EMAIL}"
git tag "${VERSION}"
git push origin "${VERSION}"
