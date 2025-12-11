#!/usr/bin/env bash
set -euo pipefail

FIO_JF=${1:-qd_sweep_rand4k.fio}
TRIALS=${2:-5}                     # number of repeats for error bars
OUTDIR=${3:-qd_logs}
SECTIONS=(qd1 qd2 qd4 qd8 qd16 qd32 qd64 qd128)

mkdir -p "$OUTDIR"

for sec in "${SECTIONS[@]}"; do
  for t in $(seq 1 "$TRIALS"); do
    echo "==> $sec trial $t"
    sudo fio --section="$sec" "$FIO_JF" | tee "$OUTDIR/${sec}_t${t}.txt"
  done
done

echo "Done. Logs in $OUTDIR/"
