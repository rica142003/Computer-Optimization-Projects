#pragma once
#include "csr.hpp"
#include <random>
#include <vector>
#include <algorithm>

static inline CSR gen_csr_uniform(int m, int k, double density, uint64_t seed) {
  std::mt19937_64 rng(seed);
  std::uniform_real_distribution<double> ud(0.0, 1.0);
  std::uniform_real_distribution<double> uv(-1.0, 1.0);

  CSR A;
  A.m = m; A.k = k;
  A.rowptr.resize(m+1);
  std::vector<int> cols;
  cols.reserve(k);

  int nnz_total = 0;
  for (int i = 0; i < m; i++) {
    A.rowptr[i] = nnz_total;
    cols.clear();
    for (int j = 0; j < k; j++) {
      if (ud(rng) < density) cols.push_back(j);
    }
    std::sort(cols.begin(), cols.end());
    for (int c : cols) {
      A.colind.push_back(c);
      A.val.push_back(uv(rng));
      nnz_total++;
    }
  }
  A.rowptr[m] = nnz_total;
  return A;
}

static inline void gen_dense(std::vector<double>& M, int r, int c, uint64_t seed) {
  std::mt19937_64 rng(seed);
  std::uniform_real_distribution<double> uv(-1.0, 1.0);
  M.resize((size_t)r * c);
  for (auto &x : M) x = uv(rng);
}
