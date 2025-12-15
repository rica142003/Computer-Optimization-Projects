#include "blocked_bloom.h"
#include <cmath>

static double bloom_fpr(double bpe, int k) {
  double x = std::exp(-double(k) / bpe);
  return std::pow(1.0 - x, k);
}

static double choose_bpe(double target, int k) {
  double lo = 1.0, hi = 64.0;
  for (int it = 0; it < 60; it++) {
    double mid = 0.5 * (lo + hi);
    double f = bloom_fpr(mid, k);
    if (f <= target) hi = mid;
    else lo = mid;
  }
  return hi;
}

BlockedBloom::BlockedBloom(uint64_t n, double target_fpr, uint64_t seed)
  : n_target_(n), seed_(seed) {
  int k_guess = 6;
  double bpe = choose_bpe(target_fpr, k_guess);
  int k = std::max(1, (int)std::round(bpe * std::log(2.0)));
  k_ = (uint32_t)std::min(16, std::max(1, k));
  bpe = choose_bpe(target_fpr, (int)k_);

  uint64_t total_bits = (uint64_t)std::ceil(double(n_target_) * bpe);
  num_blocks_ = (total_bits + 511) / 512;
  num_blocks_ = next_pow2_u64(std::max<uint64_t>(1, num_blocks_));
  bits_.assign(num_blocks_ * 8, 0ULL);
}

inline void BlockedBloom::set_bit(uint64_t block, uint32_t bit) {
  uint64_t idx = block * 8 + (bit >> 6);
  bits_[idx] |= (1ULL << (bit & 63));
}

inline bool BlockedBloom::get_bit(uint64_t block, uint32_t bit) const {
  uint64_t idx = block * 8 + (bit >> 6);
  return (bits_[idx] >> (bit & 63)) & 1ULL;
}

bool BlockedBloom::build(const std::vector<uint64_t>& keys) {
  for (auto k : keys) insert(k);
  return true;
}

bool BlockedBloom::insert(uint64_t key) {
  uint64_t h1 = hash64(key, seed_);
  uint64_t b = block_index(h1);
  uint64_t h2 = hash64(key, seed_ ^ 0x9e3779b97f4a7c15ULL);
  for (uint32_t i = 0; i < k_; i++) {
    uint32_t bit = (uint32_t)((h1 + i * h2) & 511ULL);
    set_bit(b, bit);
  }
  n_items_++;
  return true;
}

bool BlockedBloom::contains(uint64_t key) const {
  uint64_t h1 = hash64(key, seed_);
  uint64_t b = block_index(h1);
  uint64_t h2 = hash64(key, seed_ ^ 0x9e3779b97f4a7c15ULL);
  for (uint32_t i = 0; i < k_; i++) {
    uint32_t bit = (uint32_t)((h1 + i * h2) & 511ULL);
    if (!get_bit(b, bit)) return false;
  }
  return true;
}
