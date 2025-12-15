#!/usr/bin/env bash
set -euo pipefail

PIN_CPUS=${PIN_CPUS:-0-15}
REPS=${REPS:-5}
SECS=${SECS:-2}
EVENTS=${EVENTS:-cycles,LLC-load-misses,LLC-store-misses}

mkdir -p data/raw data/processed

VARIANTS=("coarse" "striped")
WORKLOADS=("lookup" "insert" "mixed")
NKEYS_LIST=(10000 100000 1000000)
THREADS_LIST=(1 2 4 8 16)

for v in "${VARIANTS[@]}"; do
  for w in "${WORKLOADS[@]}"; do
    for n in "${NKEYS_LIST[@]}"; do
      for t in "${THREADS_LIST[@]}"; do
        for r in $(seq 1 "${REPS}"); do
          seed=$r
          echo "RUN+PERF v=$v w=$w n=$n t=$t r=$r"
          bench_out="data/raw/bench_${v}_${w}_n${n}_t${t}_s${SECS}_r${seed}.csv"
          perf_out="data/raw/perf_${v}_${w}_n${n}_t${t}_s${SECS}_r${seed}.csv"
          taskset -c "${PIN_CPUS}" perf stat -x, -o "${perf_out}" -e "${EVENTS}"             ./bin/a4_bench --variant "$v" --workload "$w" --nkeys "$n" --threads "$t" --seconds "$SECS" --seed "$seed"             | tee "${bench_out}" >/dev/null
        done
      done
    done
  done
done

python3 scripts/parse_perf.py --rawdir data/raw --out data/processed/results.csv
echo "Wrote data/processed/results.csv"
