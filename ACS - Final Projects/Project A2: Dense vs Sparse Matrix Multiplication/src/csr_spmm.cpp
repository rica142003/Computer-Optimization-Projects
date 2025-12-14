#include "csr.hpp"
#include <algorithm>
#include <omp.h>

void csr_spmm(const CSR& A, const double* B, double* C, int n, int nthr, int col_chunk) {
  // A: m x k, B: k x n, C: m x n
  std::fill(C, C + (size_t)A.m*n, 0.0);
  omp_set_num_threads(nthr);

  #pragma omp parallel for schedule(static)
  for (int i = 0; i < A.m; i++) {
    double* c_row = &C[(size_t)i*n];
    int start = A.rowptr[i];
    int end   = A.rowptr[i+1];

    for (int jj = 0; jj < n; jj += col_chunk) {
      int jmax = std::min(jj + col_chunk, n);

      // accumulate chunk
      for (int idx = start; idx < end; idx++) {
        int kcol = A.colind[idx];
        double aval = A.val[idx];
        const double* b_row = &B[(size_t)kcol*n + jj];

        // vectorizable loop
        for (int j = jj; j < jmax; j++) {
          c_row[j] += aval * b_row[j - jj];
        }
      }
    }
  }
}
