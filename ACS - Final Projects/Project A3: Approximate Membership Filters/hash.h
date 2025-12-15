#pragma once
#include <cstdint>

uint64_t hash64(uint64_t x, uint64_t seed);
uint32_t hash32(uint64_t x, uint64_t seed);

static inline uint64_t next_pow2_u64(uint64_t x) {
  if (x <= 1) return 1;
  x--;
  x |= x >> 1;
  x |= x >> 2;
  x |= x >> 4;
  x |= x >> 8;
  x |= x >> 16;
  x |= x >> 32;
  return x + 1;
}
