#pragma once
#include <cstdint>
#include <vector>
#include <string>

std::vector<uint64_t> make_keys(uint64_t n, const std::string& dist, uint64_t seed);
std::vector<uint64_t> make_negative_keys(uint64_t n, const std::string& dist, uint64_t seed, uint64_t offset);
