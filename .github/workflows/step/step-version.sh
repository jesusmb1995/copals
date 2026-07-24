#!/bin/bash
set -euo pipefail
echo "version=$(cat VERSION)" >> "${OUTPUT_PATH}"
