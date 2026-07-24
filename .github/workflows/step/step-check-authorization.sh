#!/bin/bash
set -euo pipefail
ACTOR="${ACTOR:?ACTOR required}"
REPO="${REPO:?REPO required}"
API_TOKEN="${API_TOKEN:?API_TOKEN required}"

REPO_OWNER=$(echo "$REPO" | cut -d/ -f1)
if [ "$ACTOR" = "$REPO_OWNER" ]; then
  echo "authorized: $ACTOR is repo owner"
  exit 0
fi

response=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO}/collaborators/${ACTOR}")

if [ "$response" = "204" ]; then
  echo "authorized: $ACTOR is a collaborator"
  exit 0
else
  echo "::error::Unauthorized: ${ACTOR} is not a collaborator on ${REPO}"
  exit 1
fi
