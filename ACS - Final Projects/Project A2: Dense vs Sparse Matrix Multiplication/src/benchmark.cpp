#include "timers.hpp"
#include "gen.hpp"
#include "csr.hpp"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <cmath>
#include <algorithm>

void gemm_naive(const double*, const double*, double*, int,int,int,int);
void gemm_tiled(const double*, const double*, double*, int,int,int,int,int,int,int);
void csr_spmm(const CSR&, const double*, double*, int, int, int);

static double rel_err(const std::vector<double>& X, const std::vector<double>& Y) {
  double num=0, den=0;
  for (size_t i=0;i<X.size();i++){
    double d=X[i]-Y[i];
    num += d*d;
    den += X[i]*X[i];
  }
  return std::sqrt(num/(den + 1e-30));
}

int main(int argc, char** argv) {
  // args:
  // mode: dense_naive | dense_tiled | spmm
  // m k n density threads reps colchunk Ti Tj Tk seed
  if (argc < 7) {
    fprintf(stderr,
      "Usage: %s mode m k n density threads [reps=3] [colchunk=32] [Ti=64 Tj=64 Tk=64] [seed=1]\n", argv[0]);
    return 1;
  }

  const char* mode = argv[1];
  int m = atoi(argv[2]);
  int k = atoi(argv[3]);
  int n = atoi(argv[4]);
  double density = atof(argv[5]);
  int nthr = atoi(argv[6]);
  int reps = (argc>7)? atoi(argv[7]) : 3;
  int colchunk = (argc>8)? atoi(argv[8]) : 32;
  int Ti = (argc>9)? atoi(argv[9]) : 64;
  int Tj = (argc>10)? atoi(argv[10]) : 64;
  int Tk = (argc>11)? atoi(argv[11]) : 64;
  uint64_t seed = (argc>12)? (uint64_t)atoll(argv[12]) : 1;

  // Generate inputs
  std::vector<double> A_dense, B, C, C_ref;
  CSR A_csr;

  // Dense A for GEMM
  gen_dense(A_dense, m, k, seed+11);
  gen_dense(B, k, n, seed+22);
  C.resize((size_t)m*n);
  C_ref.resize((size_t)m*n);

  // CSR A for SpMM
  if (strcmp(mode, "spmm")==0) {
    A_csr = gen_csr_uniform(m, k, density, seed+33);
  }

  for (int r = 0; r < reps; r++) {
    uint64_t t0 = nsec_now();

    if (strcmp(mode, "dense_naive")==0) {
      gemm_naive(A_dense.data(), B.data(), C.data(), m,k,n,nthr);
    } else if (strcmp(mode, "dense_tiled")==0) {
      gemm_tiled(A_dense.data(), B.data(), C.data(), m,k,n,nthr,Ti,Tj,Tk);
    } else if (strcmp(mode, "spmm")==0) {
      csr_spmm(A_csr, B.data(), C.data(), n, nthr, colchunk);
    } else {
      fprintf(stderr, "Unknown mode\n");
      return 2;
    }

    uint64_t t1 = nsec_now();
    double ms = (t1 - t0) / 1e6;

    // Metrics
    double gflops = 0.0;
    double cpnz = 0.0;
    if (strcmp(mode, "dense_naive")==0 || strcmp(mode, "dense_tiled")==0) {
      // 2*m*k*n flops
      double flops = 2.0 * (double)m * (double)k * (double)n;
      gflops = flops / ((t1 - t0) / 1e9) / 1e9;
    } else {
      // SpMM flops: 2*nnz*n (each nonzero does n FMAs)
      double flops = 2.0 * (double)A_csr.nnz() * (double)n;
      gflops = flops / ((t1 - t0) / 1e9) / 1e9;
      // cycles per nonzero: compute later via perf, but still output placeholder
      cpnz = 0.0;
    }

    // CSV line
    // columns: mode,m,k,n,density,threads,reps_i,ms,gflops,nnz,colchunk,Ti,Tj,Tk,seed
    int nnz = (strcmp(mode,"spmm")==0)? A_csr.nnz() : -1;
    printf("%s,%d,%d,%d,%.6f,%d,%d,%.3f,%.3f,%d,%d,%d,%d,%d,%llu\n",
      mode,m,k,n,density,nthr,r,ms,gflops,nnz,colchunk,Ti,Tj,Tk,(unsigned long long)seed);
  }

  // Correctness check hook (for your correctness section)
  // Example: compare dense_tiled against dense_naive for same inputs
  if (strcmp(mode, "dense_tiled")==0) {
    gemm_naive(A_dense.data(), B.data(), C_ref.data(), m,k,n,1);
    double e = rel_err(C, C_ref);
    fprintf(stderr, "REL_ERR_vs_naive=%.3e\n", e);
  }
  if (strcmp(mode, "spmm")==0) {
    // build dense A from CSR to validate (slow, but for correctness only)
    std::vector<double> A2((size_t)m*k, 0.0);
    for (int i=0;i<m;i++){
      for (int idx=A_csr.rowptr[i]; idx<A_csr.rowptr[i+1]; idx++){
        A2[(size_t)i*k + A_csr.colind[idx]] = A_csr.val[idx];
      }
    }
    gemm_naive(A2.data(), B.data(), C_ref.data(), m,k,n,1);
    double e = rel_err(C, C_ref);
    fprintf(stderr, "REL_ERR_vs_dense=%.3e\n", e);
  }

  return 0;
}
