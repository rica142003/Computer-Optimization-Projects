#include "cuckoo_filter.h"
#include <random>
#include <algorithm>
#include <mutex>

static inline uint32_t rotl32(uint32_t x, int r) { return (x << r) | (x >> (32 - r)); }

CuckooFilter::CuckooFilter(uint64_t n, int fp_bits, double load_factor, uint64_t seed)
  : seed_(seed), fp_bits_(fp_bits) {
  fp_bits_ = std::max(1, std::min(16, fp_bits_));
  fp_mask_ = (fp_bits_ == 16) ? 0xFFFFu : (uint16_t)((1u << fp_bits_) - 1u);

  double buckets_f = double(n) / (double(B) * std::max(0.05, load_factor));
  nb_ = (uint32_t)next_pow2_u64((uint64_t)std::ceil(buckets_f));
  if (nb_ < 2) nb_ = 2;

  tab_.assign((size_t)nb_ * B, 0);
  stash_.reserve(64);
}

uint64_t CuckooFilter::bytes() const {
  return tab_.size() * sizeof(uint16_t) + stash_.size() * sizeof(uint16_t);
}

double CuckooFilter::fail_rate() const {
  return (insert_attempts_ == 0) ? 0.0 : double(insert_fails_) / double(insert_attempts_);
}
double CuckooFilter::avg_kicks() const {
  return (insert_attempts_ == 0) ? 0.0 : double(kicks_total_) / double(insert_attempts_);
}

inline uint16_t CuckooFilter::fp(uint64_t key) const {
  uint16_t f = (uint16_t)(hash64(key, seed_ ^ 0xABCDEF0011223344ULL) & fp_mask_);
  return (f == 0) ? 1 : f;
}

inline uint32_t CuckooFilter::i1(uint64_t key) const {
  return hash32(key, seed_) & (nb_ - 1);
}

inline uint32_t CuckooFilter::i2(uint32_t i, uint16_t fpv) const {
  uint32_t h = hash32(fpv, seed_ ^ 0x9E3779B9U);
  return (i ^ rotl32(h, 7)) & (nb_ - 1);
}

bool CuckooFilter::contains(uint64_t key) const {
  uint16_t f = fp(key);
  uint32_t a = i1(key);
  uint32_t b = i2(a, f);

  std::shared_lock<std::shared_mutex> lk(mu_);
  for (uint32_t j = 0; j < B; j++) if (slot(a,j) == f) return true;
  for (uint32_t j = 0; j < B; j++) if (slot(b,j) == f) return true;
  for (auto sf : stash_) { if (sf == f) { stash_hits_++; return true; } }
  return false;
}

bool CuckooFilter::insert(uint64_t key) {
  std::unique_lock<std::shared_mutex> lk(mu_);
  insert_attempts_++;
  uint16_t f = fp(key);
  uint32_t a = i1(key);
  uint32_t b = i2(a, f);

  for (uint32_t j = 0; j < B; j++) if (slot(a,j) == 0) { slot(a,j)=f; n_items_++; return true; }
  for (uint32_t j = 0; j < B; j++) if (slot(b,j) == 0) { slot(b,j)=f; n_items_++; return true; }

  std::minstd_rand rng((uint32_t)hash32(f, seed_ ^ 0x13579BDFU));
  uint32_t cur = (rng() & 1) ? a : b;
  uint16_t curf = f;

  const uint32_t MAX_KICKS = 500;
  for (uint32_t kick = 0; kick < MAX_KICKS; kick++) {
    kicks_total_++;
    uint32_t j = (uint32_t)(rng() % B);
    std::swap(curf, slot(cur, j));
    cur = i2(cur, curf);
    for (uint32_t t = 0; t < B; t++) {
      if (slot(cur,t) == 0) {
        slot(cur,t) = curf;
        n_items_++;
        return true;
      }
    }
  }

  if (stash_.size() < 64) {
    stash_.push_back(curf);
    n_items_++;
    return true;
  }

  insert_fails_++;
  return false;
}

bool CuckooFilter::erase(uint64_t key) {
  std::unique_lock<std::shared_mutex> lk(mu_);
  uint16_t f = fp(key);
  uint32_t a = i1(key);
  uint32_t b = i2(a, f);

  for (uint32_t j = 0; j < B; j++) if (slot(a,j) == f) { slot(a,j)=0; n_items_--; return true; }
  for (uint32_t j = 0; j < B; j++) if (slot(b,j) == f) { slot(b,j)=0; n_items_--; return true; }

  auto it = std::find(stash_.begin(), stash_.end(), f);
  if (it != stash_.end()) { stash_.erase(it); n_items_--; return true; }

  return false;
}

bool CuckooFilter::build(const std::vector<uint64_t>& keys) {
  for (auto k : keys) {
    if (!insert(k)) return false;
  }
  return true;
}
