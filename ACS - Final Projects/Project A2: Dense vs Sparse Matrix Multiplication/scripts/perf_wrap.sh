#!/usr/bin/env bash
set -euo pipefail
OUT=$1; shift
mkdir -p data

perf stat -x, -o "$OUT" -e \
cycles,instructions,cache-misses,LLC-load-misses,branch-misses \
"$@"
