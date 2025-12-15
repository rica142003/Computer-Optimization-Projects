#include "xor_filter.h"
#include <queue>
#include <cmath>

XorFilter::XorFilter(uint64_t n, int fp_bits, uint64_t seed)
  : seed_(seed), seed_fp_(seed ^ 0x123456789abcdef0ULL), fp_bits_(fp_bits) {
  fp_bits_ = std::max(1, std::min(16, fp_bits_));
  fp_mask_ = (fp_bits_ == 16) ? 0xFFFFu : (uint16_t)((1u << fp_bits_) - 1u);

  m_ = next_pow2_u64((uint64_t)std::ceil(n * 1.23) + 64);
  fp_.assign(m_, 0);
}

inline uint16_t XorFilter::fingerprint(uint64_t key) const {
  uint16_t f = (uint16_t)(hash64(key, seed_fp_) & fp_mask_);
  return (f == 0) ? 1 : f;
}

inline void XorFilter::positions(uint64_t key, uint32_t& a, uint32_t& b, uint32_t& c) const {
  uint64_t h = hash64(key, seed_);
  uint64_t mask = m_ - 1;
  a = (uint32_t)(h & mask);
  b = (uint32_t)((h >> 21) & mask);
  c = (uint32_t)((h >> 42) & mask);
  if (b == a) b = (b + 1) & mask;
  if (c == a || c == b) c = (c + 2) & mask;
}

bool XorFilter::build(const std::vector<uint64_t>& keys) {
  n_items_ = keys.size();

  for (int attempt = 0; attempt < 10; attempt++) {
    std::fill(fp_.begin(), fp_.end(), 0);

    std::vector<uint32_t> deg(m_, 0);
    std::vector<uint32_t> x(m_, 0);

    for (uint32_t i = 0; i < keys.size(); i++) {
      uint32_t a,b,c;
      positions(keys[i], a,b,c);
      deg[a]++; deg[b]++; deg[c]++;
      x[a] ^= i; x[b] ^= i; x[c] ^= i;
    }

    std::queue<uint32_t> q;
    for (uint32_t i = 0; i < m_; i++) if (deg[i] == 1) q.push(i);

    struct Item { uint32_t idx; uint32_t key_i; };
    std::vector<Item> st;
    st.reserve(keys.size());

    while (!q.empty()) {
      uint32_t idx = q.front(); q.pop();
      if (deg[idx] != 1) continue;
      uint32_t key_i = x[idx];
      st.push_back({idx, key_i});

      uint32_t a,b,c;
      positions(keys[key_i], a,b,c);

      auto dec = [&](uint32_t v) {
        if (deg[v] == 0) return;
        deg[v]--;
        x[v] ^= key_i;
        if (deg[v] == 1) q.push(v);
      };
      dec(a); dec(b); dec(c);
      deg[idx] = 0;
    }

    if (st.size() != keys.size()) {
      seed_ ^= 0x9e3779b97f4a7c15ULL + (uint64_t)attempt * 0x100000001b3ULL;
      continue;
    }

    for (int i = (int)st.size() - 1; i >= 0; i--) {
      uint32_t idx = st[i].idx;
      uint32_t key_i = st[i].key_i;
      uint32_t a,b,c;
      positions(keys[key_i], a,b,c);
      uint16_t f = fingerprint(keys[key_i]);
      uint16_t cur = (uint16_t)(fp_[a] ^ fp_[b] ^ fp_[c]);
      fp_[idx] = (uint16_t)(cur ^ f);
    }

    bool ok = true;
    for (auto k : keys) { if (!contains(k)) { ok = false; break; } }
    if (ok) return true;
    seed_ ^= 0xD1B54A32D192ED03ULL;
  }

  return false;
}

bool XorFilter::contains(uint64_t key) const {
  uint32_t a,b,c;
  positions(key, a,b,c);
  uint16_t f = fingerprint(key);
  uint16_t got = (uint16_t)(fp_[a] ^ fp_[b] ^ fp_[c]);
  return got == f;
}
