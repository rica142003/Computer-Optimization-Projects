#include <algorithm>
#include <omp.h>

void gemm_naive(const double* A, const double* B, double* C,
                int m, int k, int n, int nthr) {
  std::fill(C, C + (size_t)m * (size_t)n, 0.0);

  omp_set_num_threads(nthr);
  #pragma omp parallel for schedule(static)
  for (int i = 0; i < m; i++) {
    for (int kk = 0; kk < k; kk++) {
      double a = A[(size_t)i * (size_t)k + (size_t)kk];
      const double* b = &B[(size_t)kk * (size_t)n];
      double* c = &C[(size_t)i * (size_t)n];
      for (int j = 0; j < n; j++) {
        c[j] += a * b[j];
      }
    }
  }
}

void gemm_tiled(const double* A, const double* B, double* C,
                int m, int k, int n,
                int nthr, int Ti, int Tj, int Tk) {
  std::fill(C, C + (size_t)m * (size_t)n, 0.0);

  omp_set_num_threads(nthr);
  #pragma omp parallel for collapse(2) schedule(static)
  for (int ii = 0; ii < m; ii += Ti) {
    for (int jj = 0; jj < n; jj += Tj) {
      for (int kk = 0; kk < k; kk += Tk) {
        int iimax = std::min(ii + Ti, m);
        int jjmax = std::min(jj + Tj, n);
        int kkmax = std::min(kk + Tk, k);

        for (int i = ii; i < iimax; i++) {
          for (int kk2 = kk; kk2 < kkmax; kk2++) {
            double a = A[(size_t)i * (size_t)k + (size_t)kk2];
            const double* b = &B[(size_t)kk2 * (size_t)n];
            double* c = &C[(size_t)i * (size_t)n];
            // inner loop should auto-vectorize
            for (int j = jj; j < jjmax; j++) {
              c[j] += a * b[j];
            }
          }
        }
      }
    }
  }
}
