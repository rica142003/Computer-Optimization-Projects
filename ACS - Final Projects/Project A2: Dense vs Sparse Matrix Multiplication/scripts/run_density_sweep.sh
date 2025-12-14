#!/usr/bin/env bash
set -euo pipefail
mkdir -p data

M=1024; K=1024; N=1024
REPS=5
T=8
COLCHUNK=32
TI=64; TJ=64; TK=64
SEED=1

export OMP_PROC_BIND=true
export OMP_PLACES=cores

# Dense reference at full density (always same input size)
./benchmark_simd dense_tiled $M $K $N 1.0 $T $REPS $COLCHUNK $TI $TJ $TK $SEED \
  > data/density_dense_ref.csv

for D in 0.001 0.002 0.005 0.01 0.02 0.05 0.10 0.20 0.50; do
  ./benchmark_simd spmm $M $K $N $D $T $REPS $COLCHUNK $TI $TJ $TK $SEED \
    >> data/density_spmm.csv
done
