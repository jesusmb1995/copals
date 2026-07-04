#!/bin/bash
set -e
VERSION=$(grep '^LATEST_BASHUNIT_VERSION=' install_bashunit.sh | cut -d'"' -f2)
url="https://github.com/TypedDevs/bashunit/releases/download/${VERSION}/checksum"
CHECKSUM=$(curl -fsSL "${url}" | awk '{print $1}')
echo "Checksum ${url}: ${CHECKSUM}"
sed -i -E "s|^    expected=.*|    expected=\"${CHECKSUM}\"|" install_bashunit.sh
