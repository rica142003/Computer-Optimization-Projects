#pragma once
#include "filters.h"
#include "hash.h"
#include <vector>
#include <cstdint>

class XorFilter : public IFilter {
 public:
  XorFilter(uint64_t n, int fp_bits, uint64_t seed);

  const char* name() const override { return "xor"; }
  bool build(const std::vector<uint64_t>& keys) override;
  bool contains(uint64_t key) const override;

  bool insert(uint64_t) override { return false; }
  bool erase(uint64_t) override { return false; }

  uint64_t bytes() const override { return fp_.size() * sizeof(uint16_t); }
  uint64_t size() const override { return n_items_; }

 private:
  uint64_t seed_;
  uint64_t seed_fp_;
  int fp_bits_;
  uint16_t fp_mask_;
  uint64_t m_;
  uint64_t n_items_ = 0;
  std::vector<uint16_t> fp_;

  inline uint16_t fingerprint(uint64_t key) const;
  inline void positions(uint64_t key, uint32_t& a, uint32_t& b, uint32_t& c) const;
};
