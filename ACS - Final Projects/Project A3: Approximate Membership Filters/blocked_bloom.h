#pragma once
#include "filters.h"
#include "hash.h"
#include <vector>
#include <cstdint>

class BlockedBloom : public IFilter {
 public:
  BlockedBloom(uint64_t n, double target_fpr, uint64_t seed);

  const char* name() const override { return "bloom"; }
  bool build(const std::vector<uint64_t>& keys) override;
  bool contains(uint64_t key) const override;
  bool insert(uint64_t key) override;
  bool erase(uint64_t) override { return false; }

  uint64_t bytes() const override { return bits_.size() * sizeof(uint64_t); }
  uint64_t size() const override { return n_items_; }

 private:
  uint64_t n_target_;
  uint64_t n_items_ = 0;
  uint64_t seed_;
  uint32_t k_ = 7;
  uint64_t num_blocks_ = 1;
  std::vector<uint64_t> bits_; // 512-bit blocks => 8 u64 per block

  inline uint64_t block_index(uint64_t h) const { return (h >> 1) & (num_blocks_ - 1); }
  inline void set_bit(uint64_t block, uint32_t bit);
  inline bool get_bit(uint64_t block, uint32_t bit) const;
};
