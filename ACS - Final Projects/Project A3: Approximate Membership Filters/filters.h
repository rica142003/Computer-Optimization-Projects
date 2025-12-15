#pragma once
#include <cstdint>
#include <vector>

struct IFilter {
  virtual ~IFilter() = default;
  virtual const char* name() const = 0;

  virtual bool build(const std::vector<uint64_t>& keys) = 0;
  virtual bool contains(uint64_t key) const = 0;

  virtual bool insert(uint64_t key) = 0;
  virtual bool erase(uint64_t key) = 0;

  virtual uint64_t bytes() const = 0;
  virtual uint64_t size() const = 0;
};
