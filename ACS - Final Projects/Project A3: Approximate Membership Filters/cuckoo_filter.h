#pragma once
#include "filters.h"
#include "hash.h"
#include <vector>
#include <cstdint>
#include <shared_mutex>

class CuckooFilter : public IFilter {
 public:
  CuckooFilter(uint64_t n, int fp_bits, double load_factor, uint64_t seed);

  const char* name() const override { return "cuckoo"; }
  bool build(const std::vector<uint64_t>& keys) override;
  bool contains(uint64_t key) const override;
  bool insert(uint64_t key) override;
  bool erase(uint64_t key) override;

  uint64_t bytes() const override;
  uint64_t size() const override { return n_items_; }

  double fail_rate() const;
  double avg_kicks() const;
  uint64_t stash_hits() const { return stash_hits_; }

 private:
  static constexpr uint32_t B = 4;
  uint64_t seed_;
  int fp_bits_;
  uint16_t fp_mask_;

  uint32_t nb_;
  std::vector<uint16_t> tab_;
  mutable std::shared_mutex mu_;

  std::vector<uint16_t> stash_;

  uint64_t n_items_ = 0;
  uint64_t insert_attempts_ = 0;
  uint64_t insert_fails_ = 0;
  uint64_t kicks_total_ = 0;
  mutable uint64_t stash_hits_ = 0;

  inline uint16_t fp(uint64_t key) const;
  inline uint32_t i1(uint64_t key) const;
  inline uint32_t i2(uint32_t i, uint16_t fpv) const;
  inline uint16_t& slot(uint32_t bucket, uint32_t j) { return tab_[bucket*B + j]; }
  inline uint16_t  slot(uint32_t bucket, uint32_t j) const { return tab_[bucket*B + j]; }
};
