#!/bin/sh
# Thin proxy: source copals.sh for run_amber, then pass everything straight
# through to the amber test.ab. No shell dispatch logic here.

self_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$self_dir/copals.sh"

run_amber "test/test.ab" "$@"
