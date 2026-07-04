#!/bin/bash
set -eu

# Regenerate the auto-generated aria2 deps section of copals_apt_fast_base.Dockerfile
# in-place, preserving the rest of the file.
#
# Usage:  ./gen-aria2-docker-section-update.sh [snapshot_timestamp]

SNAPSHOT_TS="${1:-$(date -u +%Y%m%dT120000Z)}"
DOCKERFILE="$(dirname "$0")/copals_apt_fast_base.Dockerfile"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

"$(dirname "$0")/gen-aria2-docker-section.sh" "$SNAPSHOT_TS" > "$tmp"

sed -i -e '/^# ---BEGIN auto-generated aria2 deps/,/^# ---END auto-generated aria2 deps/{
  r '"$tmp"'
  d
}' "$DOCKERFILE"

echo "Updated $DOCKERFILE for snapshot $SNAPSHOT_TS"
