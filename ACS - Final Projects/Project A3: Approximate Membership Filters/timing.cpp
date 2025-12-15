#include "timing.h"
#include "common.h"
#include <chrono>
#include <thread>

double now_sec() {
  using clock = std::chrono::steady_clock;
  static const auto t0 = clock::now();
  auto t = clock::now();
  std::chrono::duration<double> d = t - t0;
  return d.count();
}

double calibrate_cycles_per_ns(int ms) {
  uint64_t c0 = rdtscp_u64();
  auto t0 = std::chrono::steady_clock::now();
  std::this_thread::sleep_for(std::chrono::milliseconds(ms));
  uint64_t c1 = rdtscp_u64();
  auto t1 = std::chrono::steady_clock::now();
  auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count();
  if (ns <= 0) return 1.0;
  return double(c1 - c0) / double(ns);
}

double percentile(std::vector<double>& xs, double p) {
  if (xs.empty()) return 0.0;
  std::sort(xs.begin(), xs.end());
  double idx = p * (xs.size() - 1);
  size_t lo = (size_t)std::floor(idx);
  size_t hi = (size_t)std::ceil(idx);
  if (hi >= xs.size()) hi = xs.size() - 1;
  double frac = idx - lo;
  return xs[lo] * (1.0 - frac) + xs[hi] * frac;
}
