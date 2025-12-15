#!/usr/bin/env bash
set -euo pipefail
OUTDIR="${OUTDIR:-results}"
mkdir -p "$OUTDIR"
EVENTS="${EVENTS:-cycles,instructions,branches,branch-misses,cache-references,cache-misses,dTLB-load-misses,LLC-load-misses}"
OUT="$OUTDIR/perf.txt"
echo "# perf stat -e $EVENTS $*" | tee "$OUT"
perf stat -e "$EVENTS" --append -o "$OUT" -- "$@"
echo "Wrote $OUT"
