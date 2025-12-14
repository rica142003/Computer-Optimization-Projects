#!/usr/bin/env bash
set -euo pipefail
mkdir -p data

M=1024; K=1024; N=1024
D=0.01
REPS=5
COLCHUNK=32
TI=64; TJ=64; TK=64
SEED=1

export OMP_PROC_BIND=true
export OMP_PLACES=cores

for T in 1 2 4 8 16; do
  # Dense
  ./benchmark_nosimd dense_tiled $M $K $N 1.0 $T $REPS $COLCHUNK $TI $TJ $TK $SEED >> data/speedup_dense.csv
  ./benchmark_simd  dense_tiled $M $K $N 1.0 $T $REPS $COLCHUNK $TI $TJ $TK $SEED >> data/speedup_dense.csv

  # Sparse
  ./benchmark_nosimd spmm $M $K $N $D $T $REPS $COLCHUNK $TI $TJ $TK $SEED >> data/speedup_spmm.csv
  ./benchmark_simd  spmm $M $K $N $D $T $REPS $COLCHUNK $TI $TJ $TK $SEED >> data/speedup_spmm.csv
done
