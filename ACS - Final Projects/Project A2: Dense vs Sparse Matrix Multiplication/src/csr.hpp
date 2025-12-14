#pragma once
#include <vector>
#include <cstdint>

struct CSR {
  int m, k;
  std::vector<int> rowptr;   // size m+1
  std::vector<int> colind;   // size nnz
  std::vector<double> val;   // size nnz
  int nnz() const { return (int)val.size(); }
};
