#!/usr/bin/env bash
set -euo pipefail

# Pin the whole process to CPUs 0-15 (matches i7-1260P '0-15' online list).
PIN_CPUS=${PIN_CPUS:-0-15}
REPS=${REPS:-5}
SECS=${SECS:-2}

mkdir -p data/raw data/processed

VARIANTS=("coarse" "striped")
WORKLOADS=("lookup" "insert" "mixed")
NKEYS_LIST=(10000 100000 1000000)
THREADS_LIST=(1 2 4 8 16)

echo "variant,workload,nkeys,threads,seconds,seed,ops,total_finds,total_inserts,total_misses,ops_per_s" > data/processed/results.csv

for v in "${VARIANTS[@]}"; do
  for w in "${WORKLOADS[@]}"; do
    for n in "${NKEYS_LIST[@]}"; do
      for t in "${THREADS_LIST[@]}"; do
        for r in $(seq 1 "${REPS}"); do
          seed=$r
          out="data/raw/run_${v}_${w}_n${n}_t${t}_r${r}.txt"
          echo "RUN v=$v w=$w n=$n t=$t r=$r"
          taskset -c "${PIN_CPUS}" ./bin/a4_bench --variant "$v" --workload "$w" --nkeys "$n" --threads "$t" --seconds "$SECS" --seed "$seed" | tee "$out" >> data/processed/results.csv
        done
      done
    done
  done
done

echo "Wrote data/processed/results.csv"
