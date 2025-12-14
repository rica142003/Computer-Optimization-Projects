#!/usr/bin/env bash
set -euo pipefail
mkdir -p data

REPS=5
T=8
D=0.01
COLCHUNK=32
TI=64; TJ=64; TK=64
SEED=1

export OMP_PROC_BIND=true
export OMP_PLACES=cores

for N in 128 256 384 512 768 1024 1536 2048; do
  ./benchmark_simd dense_tiled $N $N $N 1.0 $T $REPS $COLCHUNK $TI $TJ $TK $SEED \
    >> data/size_dense.csv
  ./benchmark_simd spmm $N $N $N $D  $T $REPS $COLCHUNK $TI $TJ $TK $SEED \
    >> data/size_spmm.csv
done
