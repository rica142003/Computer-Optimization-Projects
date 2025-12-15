#include "dataset.h"
#include "hash.h"

std::vector<uint64_t> make_keys(uint64_t n, const std::string& dist, uint64_t seed) {
  std::vector<uint64_t> keys;
  keys.reserve(n);
  if (dist == "sequential") {
    for (uint64_t i = 0; i < n; i++) keys.push_back(i);
  } else {
    for (uint64_t i = 0; i < n; i++) keys.push_back(hash64(i, seed));
  }
  return keys;
}

std::vector<uint64_t> make_negative_keys(uint64_t n, const std::string& dist, uint64_t seed, uint64_t offset) {
  std::vector<uint64_t> keys;
  keys.reserve(n);
  if (dist == "sequential") {
    uint64_t base = 0x100000000ULL + offset;
    for (uint64_t i = 0; i < n; i++) keys.push_back(base + i);
  } else {
    uint64_t s2 = seed ^ 0xDEADBEEFCAFEBABEULL;
    for (uint64_t i = 0; i < n; i++) keys.push_back(hash64(i + offset, s2));
  }
  return keys;
}
