#include "hash.h"

uint64_t hash64(uint64_t x, uint64_t seed) {
  uint64_t z = x + seed + 0x9e3779b97f4a7c15ULL;
  z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
  z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
  z = z ^ (z >> 31);
  return z;
}

uint32_t hash32(uint64_t x, uint64_t seed) {
  return (uint32_t)(hash64(x, seed) >> 32);
}
