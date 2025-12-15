#!/usr/bin/env bash
set -euo pipefail
VARIANT=${1:-coarse}
WORKLOAD=${2:-mixed}
NKEYS=${3:-100000}
THREADS=${4:-1}
SECS=${5:-2}
SEED=${6:-1}
PIN_CPUS=${PIN_CPUS:-0-15}

mkdir -p data/raw

# perf events requested by the assignment
EVENTS=${EVENTS:-cycles,LLC-load-misses,LLC-store-misses}

bench_out="data/raw/bench_${VARIANT}_${WORKLOAD}_n${NKEYS}_t${THREADS}_s${SECS}_r${SEED}.csv"
perf_out="data/raw/perf_${VARIANT}_${WORKLOAD}_n${NKEYS}_t${THREADS}_s${SECS}_r${SEED}.csv"

# Run benchmark and counters together. We write:
# - bench output: one CSV line with throughput
# - perf output: perf stat CSV (also one-line-per-event)
taskset -c "${PIN_CPUS}" perf stat -x, -o "${perf_out}" -e "${EVENTS}"   ./bin/a4_bench --variant "${VARIANT}" --workload "${WORKLOAD}" --nkeys "${NKEYS}" --threads "${THREADS}" --seconds "${SECS}" --seed "${SEED}"   | tee "${bench_out}"

echo "bench: ${bench_out}"
echo "perf : ${perf_out}"
