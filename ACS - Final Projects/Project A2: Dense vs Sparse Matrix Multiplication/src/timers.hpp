#pragma once
#include <stdint.h>
#include <time.h>

static inline uint64_t nsec_now() {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (uint64_t)t.tv_sec*1000000000ull + (uint64_t)t.tv_nsec;
}
