#pragma once
#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>
#include <atomic>
#include <thread>
#include <chrono>
#include <random>
#include <iostream>
#include <sstream>
#include <iomanip>
#include <cmath>
#include <memory>
#include <algorithm>

static inline uint64_t rdtscp_u64() {
#if defined(__x86_64__) || defined(_M_X64)
  unsigned int aux;
  unsigned int lo, hi;
  asm volatile ("rdtscp" : "=a"(lo), "=d"(hi), "=c"(aux) ::);
  return ((uint64_t)hi << 32) | lo;
#else
  return 0;
#endif
}

struct BenchConfig {
  std::string filter = "xor";
  std::string workload = "read_only";  // read_only, read_mostly, balanced
  std::string dist = "uniform";        // uniform, sequential
  uint64_t seed = 123;
  int run = 0;

  uint64_t n = 1000000;
  double target_fpr = 0.01;
  double neg_share = 0.5;
  double load_factor = 0.95;

  int threads = 1;
  int fp_bits = 12;         // for cuckoo/xor (8/12/16)
  uint64_t ops = 1500000;   // timed operations
  uint64_t warmup_ops = 150000;
  int check = 0;
};

struct BenchResult {
  double achieved_fpr = 0.0;
  double bpe = 0.0;
  double ops_per_s = 0.0;
  double p50_ns = 0.0, p95_ns = 0.0, p99_ns = 0.0;

  // extras
  double fail_rate = 0.0;      // cuckoo
  double avg_kicks = 0.0;      // cuckoo
  double stash_hits = 0.0;     // cuckoo
  double avg_probe = 0.0;      // quotient
  double cluster_mean = 0.0;   // quotient
  double cluster_p99 = 0.0;    // quotient
};
