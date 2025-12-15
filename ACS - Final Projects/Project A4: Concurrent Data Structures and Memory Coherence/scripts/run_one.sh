#!/usr/bin/env bash
set -euo pipefail
VARIANT=${1:-coarse}
WORKLOAD=${2:-mixed}
NKEYS=${3:-100000}
THREADS=${4:-1}
SECS=${5:-2}
SEED=${6:-1}

mkdir -p data/raw
./bin/a4_bench --variant "$VARIANT" --workload "$WORKLOAD" --nkeys "$NKEYS" --threads "$THREADS" --seconds "$SECS" --seed "$SEED"
