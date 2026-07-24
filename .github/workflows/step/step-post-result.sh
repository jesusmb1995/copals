#!/bin/bash
set -euo pipefail
if [ "${JOB_STATUS}" = "success" ]; then
  STATUS="✅ PASS"
else
  STATUS="❌ FAIL"
fi

BODY=$(cat <<EOB
### copals image test: ${STATUS}
Image: \`${IMAGE_BASE}:${VERSION}\`
Commit: \`${SHA}\`
EOB
)

JSON=$(jq -n \
  --arg owner "${REPO_OWNER}" \
  --arg repo "${REPO_NAME}" \
  --argjson issue_number "${ISSUE_NUMBER}" \
  --arg body "${BODY}" \
  '{owner: $owner, repo: $repo, issue_number: $issue_number, body: $body}')

curl -X POST \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "Content-Type: application/json" \
  -d "$JSON" \
  "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/issues/${ISSUE_NUMBER}/comments"
