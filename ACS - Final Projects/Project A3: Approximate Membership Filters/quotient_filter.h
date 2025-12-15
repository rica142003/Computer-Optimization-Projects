#pragma once
#include "filters.h"
#include "hash.h"
#include <vector>
#include <cstdint>
#include <shared_mutex>

class QuotientFilter : public IFilter {
 public:
  QuotientFilter(uint64_t n, double load_factor, double target_fpr, uint64_t seed);

  const char* name() const override { return "quotient"; }
  bool build(const std::vector<uint64_t>& keys) override;
  bool contains(uint64_t key) const override;
  bool insert(uint64_t key) override;
  bool erase(uint64_t key) override;

  uint64_t bytes() const override;
  uint64_t size() const override { return n_items_; }

  double avg_probe() const { return probe_count_ ? (double)probe_total_ / (double)probe_count_ : 0.0; }
  double cluster_mean() const { return cluster_mean_; }
  double cluster_p99() const { return cluster_p99_; }

 private:
  static constexpr uint8_t CONT = 1;
  static constexpr uint8_t SHIFT = 2;

  uint64_t seed_;
  uint32_t qbits_ = 0;
  uint32_t rbits_ = 0;
  uint64_t cap_ = 0;
  uint64_t mask_ = 0;

  std::vector<uint16_t> rem_;
  std::vector<uint8_t> meta_;
  std::vector<uint64_t> occ_;
  mutable std::shared_mutex mu_;

  uint64_t n_items_ = 0;

  // stats
  mutable uint64_t probe_total_ = 0;
  mutable uint64_t probe_count_ = 0;
  double cluster_mean_ = 0.0;
  double cluster_p99_ = 0.0;

  inline bool occ(uint64_t i) const;
  inline void set_occ(uint64_t i, bool v);
  inline bool is_cont(uint64_t i) const { return (meta_[i] & CONT) != 0; }
  inline bool is_shift(uint64_t i) const { return (meta_[i] & SHIFT) != 0; }
  inline bool is_empty(uint64_t i) const { return !occ(i) && meta_[i] == 0; }

  inline uint64_t next(uint64_t i) const { return (i + 1) & mask_; }
  inline uint64_t prev(uint64_t i) const { return (i - 1) & mask_; }

  inline void qr(uint64_t key, uint64_t &q, uint16_t &r) const;

  uint64_t find_cluster_start(uint64_t q) const;
  uint64_t find_run_start(uint64_t q) const;
  bool run_contains(uint64_t q, uint16_t r) const;

  void shift_right(uint64_t pos);
  void shift_left(uint64_t pos);
  void fix_shifted_bits(uint64_t cluster_start);
  bool insert_impl(uint64_t q, uint16_t r);
  bool erase_impl(uint64_t q, uint16_t r);

  void recompute_cluster_stats();
};
