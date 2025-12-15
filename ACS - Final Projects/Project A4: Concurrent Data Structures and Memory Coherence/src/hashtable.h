#pragma once
#include <vector>
#include <list>
#include <mutex>
#include <cstdint>
#include <optional>
#include <algorithm>

// Two sync variants:
// - COARSE: one global mutex
// - STRIPED: lock striping over buckets (one stripe lock per group of buckets)
//
// This is intentionally simple and readable for a class project.

enum class Variant { COARSE, STRIPED };

struct alignas(64) StripeLock {
  std::mutex m;
};

class HashTable {
public:
  HashTable(size_t nbuckets, Variant v, size_t nstripes = 256)
    : buckets_(nbuckets),
      variant_(v),
      stripes_(std::max<size_t>(1, nstripes)) {}

  // insert or update
  void insert(uint64_t key, uint64_t value) {
    auto idx = bucket_index(key);
    lock_bucket(idx);
    auto &lst = buckets_[idx];
    for (auto &kv : lst) {
      if (kv.first == key) { kv.second = value; unlock_bucket(idx); return; }
    }
    lst.emplace_back(key, value);
    unlock_bucket(idx);
  }

  bool find(uint64_t key, uint64_t &out) {
    auto idx = bucket_index(key);
    lock_bucket(idx);
    auto &lst = buckets_[idx];
    for (auto &kv : lst) {
      if (kv.first == key) { out = kv.second; unlock_bucket(idx); return true; }
    }
    unlock_bucket(idx);
    return false;
  }

  bool erase(uint64_t key) {
    auto idx = bucket_index(key);
    lock_bucket(idx);
    auto &lst = buckets_[idx];
    for (auto it = lst.begin(); it != lst.end(); ++it) {
      if (it->first == key) {
        lst.erase(it);
        unlock_bucket(idx);
        return true;
      }
    }
    unlock_bucket(idx);
    return false;
  }

  size_t bucket_count() const { return buckets_.size(); }

private:
  size_t bucket_index(uint64_t key) const {
    // 64-bit mix (splitmix64-like) then mod bucket count
    uint64_t x = key + 0x9e3779b97f4a7c15ull;
    x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ull;
    x = (x ^ (x >> 27)) * 0x94d049bb133111ebull;
    x = x ^ (x >> 31);
    return static_cast<size_t>(x % buckets_.size());
  }

  void lock_bucket(size_t bucket_idx) {
    if (variant_ == Variant::COARSE) {
      global_.lock();
    } else {
      stripes_[bucket_idx % stripes_.size()].m.lock();
    }
  }

  void unlock_bucket(size_t bucket_idx) {
    if (variant_ == Variant::COARSE) {
      global_.unlock();
    } else {
      stripes_[bucket_idx % stripes_.size()].m.unlock();
    }
  }

  std::vector<std::list<std::pair<uint64_t,uint64_t>>> buckets_;
  Variant variant_;
  std::mutex global_;
  std::vector<StripeLock> stripes_;
};
