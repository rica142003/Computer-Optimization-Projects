#include "quotient_filter.h"
#include <cmath>
#include <algorithm>
#include <mutex>

static uint32_t choose_rbits(double target_fpr) {
  double inv = 1.0 / std::max(1e-12, target_fpr);
  uint32_t r = (uint32_t)std::ceil(std::log2(inv));
  r = r + 1;
  return std::min<uint32_t>(16, std::max<uint32_t>(4, r));
}

QuotientFilter::QuotientFilter(uint64_t n, double load_factor, double target_fpr, uint64_t seed)
  : seed_(seed) {
  rbits_ = choose_rbits(target_fpr);
  double cap_f = double(n) / std::max(0.05, load_factor);
  cap_ = next_pow2_u64((uint64_t)std::ceil(cap_f));
  if (cap_ < 8) cap_ = 8;
  mask_ = cap_ - 1;
  qbits_ = (uint32_t)std::log2((double)cap_);

  rem_.assign(cap_, 0);
  meta_.assign(cap_, 0);
  occ_.assign((cap_ + 63) / 64, 0ULL);
}

uint64_t QuotientFilter::bytes() const {
  return rem_.size()*sizeof(uint16_t) + meta_.size()*sizeof(uint8_t) + occ_.size()*sizeof(uint64_t);
}

inline bool QuotientFilter::occ(uint64_t i) const {
  return (occ_[i >> 6] >> (i & 63)) & 1ULL;
}
inline void QuotientFilter::set_occ(uint64_t i, bool v) {
  uint64_t &w = occ_[i >> 6];
  uint64_t bit = 1ULL << (i & 63);
  if (v) w |= bit;
  else w &= ~bit;
}

inline void QuotientFilter::qr(uint64_t key, uint64_t &q, uint16_t &r) const {
  uint64_t h = hash64(key, seed_);
  uint16_t rm = (rbits_ == 16) ? 0xFFFFu : (uint16_t)((1u << rbits_) - 1u);
  q = (h >> rbits_) & mask_;
  r = (uint16_t)(h & rm);
  if (r == 0) r = 1;
}

uint64_t QuotientFilter::find_cluster_start(uint64_t q) const {
  uint64_t b = q;
  for (uint64_t steps = 0; steps < cap_; steps++) {
    if (!is_shift(b)) break;
    b = prev(b);
  }
  return b;
}

uint64_t QuotientFilter::find_run_start(uint64_t q) const {
  uint64_t b = find_cluster_start(q);
  uint64_t s = b;
  uint64_t i = b;

  for (uint64_t steps = 0; steps < cap_; steps++) {
    if (i == q) break;
    i = next(i);
    if (occ(i)) {
      s = next(s);
      for (uint64_t k = 0; k < cap_; k++) {
        if (!is_cont(s)) break;
        s = next(s);
      }
    }
  }
  return s;
}

bool QuotientFilter::run_contains(uint64_t q, uint16_t r) const {
  if (!occ(q)) return false;
  uint64_t s = find_run_start(q);
  uint64_t pos = s;
  uint64_t scanned = 0;
  for (uint64_t steps = 0; steps < cap_; steps++) {
    if (is_empty(pos)) break;
    scanned++;
    if (rem_[pos] == r) {
      probe_total_ += scanned;
      probe_count_ += 1;
      return true;
    }
    uint64_t np = next(pos);
    if (!is_cont(np)) break;
    pos = np;
  }
  probe_total_ += scanned;
  probe_count_ += 1;
  return false;
}

bool QuotientFilter::contains(uint64_t key) const {
  std::shared_lock<std::shared_mutex> lk(mu_);
  uint64_t q; uint16_t r;
  qr(key, q, r);
  return run_contains(q, r);
}

void QuotientFilter::shift_right(uint64_t pos) {
  uint64_t e = pos;
  for (uint64_t steps = 0; steps < cap_; steps++) {
    if (is_empty(e)) break;
    e = next(e);
  }
  while (e != pos) {
    uint64_t p = prev(e);
    rem_[e] = rem_[p];
    meta_[e] = (uint8_t)(meta_[p] | SHIFT);
    e = p;
  }
  rem_[pos] = 0;
  meta_[pos] = 0;
}

void QuotientFilter::shift_left(uint64_t pos) {
  uint64_t cur = pos;
  while (true) {
    uint64_t nxt = next(cur);
    if (is_empty(nxt)) break;
    rem_[cur] = rem_[nxt];
    meta_[cur] = meta_[nxt];
    cur = nxt;
  }
  rem_[cur] = 0;
  meta_[cur] = 0;
}

void QuotientFilter::fix_shifted_bits(uint64_t cluster_start) {
  std::vector<uint64_t> occ_list;
  std::vector<uint64_t> run_starts;

  uint64_t i = cluster_start;
  for (uint64_t steps = 0; steps < cap_; steps++) {
    if (is_empty(i)) break;
    if (occ(i)) occ_list.push_back(i);
    if (!is_cont(i)) run_starts.push_back(i);
    i = next(i);
  }

  i = cluster_start;
  for (uint64_t steps = 0; steps < cap_; steps++) {
    if (is_empty(i)) break;
    if (is_cont(i)) meta_[i] |= SHIFT;
    i = next(i);
  }

  size_t m = std::min(occ_list.size(), run_starts.size());
  for (size_t k = 0; k < m; k++) {
    uint64_t rs = run_starts[k];
    uint64_t q = occ_list[k];
    meta_[rs] &= ~CONT;
    if (rs == q) meta_[rs] &= ~SHIFT;
    else meta_[rs] |= SHIFT;
  }
}

bool QuotientFilter::insert_impl(uint64_t q, uint16_t r) {
  bool had_run = occ(q);
  if (is_empty(q)) {
    set_occ(q, true);
    rem_[q] = r;
    meta_[q] = 0;
    n_items_++;
    return true;
  }

  set_occ(q, true);
  uint64_t cluster_start = find_cluster_start(q);
  uint64_t run_start = find_run_start(q);

  uint64_t pos = run_start;
  if (had_run) {
    uint64_t cur = run_start;
    while (true) {
      if (r <= rem_[cur]) { pos = cur; break; }
      uint64_t nxt = next(cur);
      if (!is_cont(nxt)) { pos = nxt; break; }
      cur = nxt;
    }
  } else {
    pos = run_start;
  }

  shift_right(pos);
  rem_[pos] = r;

  uint8_t m = 0;
  if (pos != run_start) m |= CONT;
  if (pos != q) m |= SHIFT;
  meta_[pos] = m;

  if (had_run && pos == run_start) {
    uint64_t nxt = next(pos);
    if (!is_empty(nxt)) meta_[nxt] |= CONT;
  }

  fix_shifted_bits(cluster_start);
  n_items_++;
  return true;
}

bool QuotientFilter::erase_impl(uint64_t q, uint16_t r) {
  if (!occ(q)) return false;

  uint64_t cluster_start = find_cluster_start(q);
  uint64_t run_start = find_run_start(q);

  uint64_t pos = run_start;
  bool found = false;
  for (uint64_t steps = 0; steps < cap_; steps++) {
    if (is_empty(pos)) break;
    if (rem_[pos] == r) { found = true; break; }
    uint64_t nxt = next(pos);
    if (!is_cont(nxt)) break;
    pos = nxt;
  }
  if (!found) return false;

  bool deleting_run_start = (pos == run_start);
  bool has_more = is_cont(next(pos));

  shift_left(pos);
  n_items_--;

  if (deleting_run_start && has_more) {
    meta_[pos] &= ~CONT;
  }
  if (deleting_run_start && !has_more) {
    set_occ(q, false);
  }

  fix_shifted_bits(cluster_start);
  return true;
}

bool QuotientFilter::insert(uint64_t key) {
  std::unique_lock<std::shared_mutex> lk(mu_);
  uint64_t q; uint16_t r;
  qr(key, q, r);
  if (run_contains(q, r)) return true;

  bool any_empty = false;
  for (uint64_t i = 0; i < cap_; i++) { if (is_empty(i)) { any_empty = true; break; } }
  if (!any_empty) return false;

  return insert_impl(q, r);
}

bool QuotientFilter::erase(uint64_t key) {
  std::unique_lock<std::shared_mutex> lk(mu_);
  uint64_t q; uint16_t r;
  qr(key, q, r);
  return erase_impl(q, r);
}

bool QuotientFilter::build(const std::vector<uint64_t>& keys) {
  std::unique_lock<std::shared_mutex> lk(mu_);
  for (auto k : keys) {
    uint64_t q; uint16_t r;
    qr(k, q, r);
    if (!insert_impl(q, r)) return false;
  }
  recompute_cluster_stats();
  return true;
}

void QuotientFilter::recompute_cluster_stats() {
  std::vector<uint64_t> lens;
  uint64_t i = 0;
  while (i < cap_) {
    if (is_empty(i)) { i++; continue; }
    uint64_t len = 0;
    while (i < cap_ && !is_empty(i)) { len++; i++; }
    lens.push_back(len);
  }
  if (lens.empty()) { cluster_mean_ = 0; cluster_p99_ = 0; return; }
  double mean = 0;
  for (auto L : lens) mean += (double)L;
  mean /= (double)lens.size();
  std::sort(lens.begin(), lens.end());
  size_t idx = (size_t)std::floor(0.99 * (lens.size() - 1));
  cluster_mean_ = mean;
  cluster_p99_ = (double)lens[idx];
}
