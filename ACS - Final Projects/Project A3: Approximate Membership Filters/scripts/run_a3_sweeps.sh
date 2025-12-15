#!/usr/bin/env bash
set -euo pipefail

BIN="${BIN:-./build/a3_bench}"
OUTDIR="${OUTDIR:-results}"
REPS="${REPS:-3}"
FAST="${FAST:-0}"

mkdir -p "$OUTDIR"
RAW="$OUTDIR/raw.log"
CSV="$OUTDIR/results.csv"
: > "$RAW"

if [[ "$FAST" == "1" ]]; then
  OPS=300000
  WARM=30000
else
  OPS=1500000
  WARM=150000
fi

# Required knobs / sweeps
FPRS=(0.05 0.01 0.001)
NS=(1000000 5000000 10000000)
NEGS=(0.0 0.5 0.9)
LOADS=(0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95)
THREADS=(1 2 4 8 12)    # i7-1260P has 12 physical cores
DISTS=(uniform sequential)

FILTERS_ALL=(bloom xor cuckoo quotient)
FILTERS_DYNAMIC=(cuckoo quotient)

run_one () {
  local filter="$1" n="$2" tfpr="$3" neg="$4" wl="$5" th="$6" lf="$7" dist="$8" fpbits="$9" rep="${10}"
  local cpus
  if [[ "$th" -le 1 ]]; then cpus="0"; else cpus="0-$((th-1))"; fi

  echo "CONFIG filter=$filter dist=$dist n=$n target_fpr=$tfpr neg_share=$neg workload=$wl threads=$th load_factor=$lf fp_bits=$fpbits ops=$OPS warmup_ops=$WARM rep=$rep" | tee -a "$RAW"
  taskset -c "$cpus" "$BIN" \
    --filter "$filter" \
    --n "$n" \
    --target_fpr "$tfpr" \
    --neg_share "$neg" \
    --workload "$wl" \
    --threads "$th" \
    --load_factor "$lf" \
    --dist "$dist" \
    --fp_bits "$fpbits" \
    --ops "$OPS" \
    --warmup_ops "$WARM" \
    --seed 123 \
    --run "$rep" \
    | tee -a "$RAW"
}

echo "# BIN=$BIN REPS=$REPS OPS=$OPS WARM=$WARM FAST=$FAST" | tee -a "$RAW"

# 1) Space vs accuracy: BPE vs achieved FPR (sizes x target fprs x distributions)
for dist in "${DISTS[@]}"; do
  for n in "${NS[@]}"; do
    for tfpr in "${FPRS[@]}"; do
      for filter in "${FILTERS_ALL[@]}"; do
        for fpbits in 8 12 16; do
          # only xor/cuckoo vary fp_bits; keep others at fpbits=12
          if [[ "$filter" != "xor" && "$filter" != "cuckoo" && "$fpbits" != "12" ]]; then
            continue
          fi
          for rep in $(seq 0 $((REPS-1))); do
            run_one "$filter" "$n" "$tfpr" 0.5 read_only 1 0.95 "$dist" "$fpbits" "$rep"
          done
        done
      done
    done
  done
done

# 2) Lookup throughput & tails vs negative share (n=1M, target 1%)
for dist in "${DISTS[@]}"; do
  for neg in "${NEGS[@]}"; do
    for filter in "${FILTERS_ALL[@]}"; do
      for fpbits in 8 12 16; do
        if [[ "$filter" != "xor" && "$filter" != "cuckoo" && "$fpbits" != "12" ]]; then
          continue
        fi
        for rep in $(seq 0 $((REPS-1))); do
          run_one "$filter" 1000000 0.01 "$neg" read_only 1 0.95 "$dist" "$fpbits" "$rep"
        done
      done
    done
  done
done

# 3) Insert/delete throughput vs load factor (dynamic only)
for dist in "${DISTS[@]}"; do
  for lf in "${LOADS[@]}"; do
    for filter in "${FILTERS_DYNAMIC[@]}"; do
      for rep in $(seq 0 $((REPS-1))); do
        run_one "$filter" 1000000 0.01 0.5 balanced 1 "$lf" "$dist" 12 "$rep"
      done
    done
  done
done

# 4) Thread scaling for read-mostly and balanced mixes (n=1M, target 1%)
for dist in "${DISTS[@]}"; do
  for wl in read_mostly balanced; do
    for th in "${THREADS[@]}"; do
      for filter in "${FILTERS_ALL[@]}"; do
        for fpbits in 8 12 16; do
          if [[ "$filter" != "xor" && "$filter" != "cuckoo" && "$fpbits" != "12" ]]; then
            continue
          fi
          for rep in $(seq 0 $((REPS-1))); do
            run_one "$filter" 1000000 0.01 0.5 "$wl" "$th" 0.80 "$dist" "$fpbits" "$rep"
          done
        done
      done
    done
  done
done

python3 tools/parse_a3_log.py "$RAW" "$CSV"
echo "Wrote $CSV"
