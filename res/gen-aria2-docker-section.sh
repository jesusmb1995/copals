#!/bin/bash
# TODO port to ab, remove python deps...
# Regenerate the aria2 + transitive deps section of copals_apt_fast_base.Dockerfile
# for a given snapshot.debian.org timestamp.
#
# Usage:  ./gen-aria2-docker-section.sh [snapshot_timestamp]
#
# Default timestamp is the current date at 12:00:00Z (today's snapshot).
# Example: ./gen-aria2-docker-section.sh 20260703T120000Z

SNAPSHOT_TS="${1:-$(date -u +%Y%m%dT120000Z)}"
SNAPSHOT_BASE="http://snapshot.debian.org/archive/debian/${SNAPSHOT_TS}"

die() { echo "$*" >&2; exit 1; }

# Ensure TEMPDIR is set for the testing lookup
cleanup_lookup() { [ -n "${TESTING_LOOKUP-}" ] && rm -f "$TESTING_LOOKUP"; }
trap cleanup_lookup EXIT
TESTING_LOOKUP=$(mktemp) || die "mktemp failed"

# Download the testing dist's Packages metadata and build a lookup
# of "pkgname version" pairs so we only resolve versions in the testing suite.
curl -sL "${SNAPSHOT_BASE}/dists/testing/main/binary-amd64/Packages.gz" \
  | gunzip \
  | python3 -c "
import sys, re
pkg = None
for line in sys.stdin:
    m = re.match(r'^Package: (.+)', line)
    if m:
        pkg = m.group(1).strip()
    m = re.match(r'^Version: (.+)', line)
    if m and pkg:
        print(f'{pkg} {m.group(1).strip()}')
        pkg = None
" > "$TESTING_LOOKUP" \
  || die "failed to build testing version lookup"

# -- Resolve the latest amd64 deb for a package at this snapshot -------------
# Iterates versions (newest first) and returns the first with an amd64 build
# that also exists in the testing suite.
# Output: "name hash path"
resolve_deb() {
    local pkg="$1"
    curl -s "http://snapshot.debian.org/mr/binary/${pkg}/" \
      | python3 -c "
import json, sys, urllib.request

ts = '${SNAPSHOT_TS}'
pkg = '${pkg}'
lookup = '${TESTING_LOOKUP}'

# Load testing version set
testing = set()
with open(lookup) as f:
    for line in f:
        parts = line.strip().split(None, 1)
        if len(parts) == 2:
            testing.add(f'{parts[0]} {parts[1]}')

versions = json.load(sys.stdin)['result']
for v in versions:
    ver = v['binary_version']
    key = f'{pkg} {ver}'
    if key not in testing:
        continue
    ver_enc = urllib.parse.quote(ver, safe='')
    url = f'http://snapshot.debian.org/mr/binary/{pkg}/{ver_enc}/binfiles?fileinfo=1'
    with urllib.request.urlopen(url) as resp:
        data = json.load(resp)
    amd64_hash = None
    for r in data.get('result', []):
        if r['architecture'] == 'amd64':
            amd64_hash = r['hash']
            break
    if not amd64_hash:
        continue
    for hh, entries in data.get('fileinfo', {}).items():
        if hh != amd64_hash:
            continue
        for e in entries:
            if e.get('archive_name') == 'debian':
                print(e['name'], hh, e['path'])
                sys.exit(0)
" 2>/dev/null
}

# -- Get sha256 of a remote deb -----------------------------------------------
sha256_of() {
    local url="$1"
    curl -sL "$url" | sha256sum | cut -d' ' -f1
}

# Packages to resolve (libgmp10, libnettle8t64 etc are already in base image)
DEPS=(
    "aria2"
    "libaria2-0"
    "libcares2"
    "libgnutls30t64"
    "libssh2-1t64"
    "libsqlite3-0"
    "libxml2-16"
    "libidn2-0"
    "libp11-kit0"
    "libtasn1-6"
    "libunistring5"
    "libffi8"
)

echo "# ---BEGIN auto-generated aria2 deps for snapshot ${SNAPSHOT_TS}---"
echo "# Pin sources to the same snapshot as the aria2 debs"
echo "RUN echo \"deb ${SNAPSHOT_BASE} testing main\" > /etc/apt/sources.list"
echo

declare -a ADD_LINES
declare -a CHECK_LINES

for pkg in "${DEPS[@]}"; do
    info=$(resolve_deb "$pkg")
    [ -z "$info" ] && die "no amd64 deb for ${pkg} at snapshot ${SNAPSHOT_TS}"
    read -r name hash path <<<"$info"

    url="${SNAPSHOT_BASE}${path}/${name}"
    sha=$(sha256_of "$url")
    [ -z "$sha" ] && die "failed to fetch ${url}"

    tmpname="/tmp/${name}"
    ADD_LINES+=("ADD ${url} ${tmpname}")
    CHECK_LINES+=("     && echo \"${sha}  ${tmpname}\" | sha256sum --check \\")
done

for line in "${ADD_LINES[@]}"; do
    echo "$line"
done
# First check line has no leading && (it's the first command after mounts)
echo "RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \\"
echo "    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \\"
first_content="${CHECK_LINES[0]#*&& }"
echo "    ${first_content}"
for line in "${CHECK_LINES[@]:1}"; do
    echo "$line"
done
echo "     && dpkg -i /tmp/*.deb || apt-get install -f -y"
echo "# ---END auto-generated aria2 deps---"
