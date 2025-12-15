#include "common.h"
#include "cli.h"
#include "dataset.h"
#include "timing.h"
#include "filters.h"
#include "blocked_bloom.h"
#include "xor_filter.h"
#include "cuckoo_filter.h"
#include "quotient_filter.h"

#include <pthread.h>
#include <sched.h>

static void pin_this_thread(int cpu) {
#if defined(__linux__)
  cpu_set_t set;
  CPU_ZERO(&set);
  CPU_SET(cpu, &set);
  (void)pthread_setaffinity_np(pthread_self(), sizeof(set), &set);
#else
  (void)cpu;
#endif
}

static std::unique_ptr<IFilter> make_filter(const BenchConfig& c) {
  if (c.filter == "bloom") return std::make_unique<BlockedBloom>(c.n, c.target_fpr, c.seed);
  if (c.filter == "xor") return std::make_unique<XorFilter>(c.n, c.fp_bits, c.seed);
  if (c.filter == "cuckoo") return std::make_unique<CuckooFilter>(c.n, c.fp_bits, c.load_factor, c.seed);
  if (c.filter == "quotient") return std::make_unique<QuotientFilter>(c.n, c.load_factor, c.target_fpr, c.seed);
  std::cerr << "Unknown filter: " << c.filter << "\n";
  std::exit(2);
}


static void compute_fpr(const IFilter& f, const std::vector<uint64_t>& neg, BenchResult& out) {
  uint64_t fp = 0;
  for (auto k : neg) if (f.contains(k)) fp++;
  out.achieved_fpr = double(fp) / double(std::max<size_t>(1, neg.size()));
}

static void warmup_queries(const IFilter& f,
                           const std::vector<uint64_t>& pos,
                           const std::vector<uint64_t>& neg,
                           double neg_share,
                           uint64_t warm_ops,
                           uint64_t seed) {
  if (warm_ops == 0) return;
  std::minstd_rand rng((uint32_t)seed);
  size_t pN = pos.size(), nN = neg.size();
  for (uint64_t i = 0; i < warm_ops; i++) {
    bool use_neg = (double(rng() % 10000) / 10000.0) < neg_share;
    uint64_t k = use_neg ? neg[rng() % nN] : pos[rng() % pN];
    (void)f.contains(k);
  }
}

struct OpStream {
  std::minstd_rand rng;
  explicit OpStream(uint32_t seed) : rng(seed) {}
  inline double frand() { return double(rng() % 10000) / 10000.0; }
  inline uint32_t urand() { return (uint32_t)rng(); }
};

static BenchResult bench_read_only(const BenchConfig& c, IFilter& filter,
                                   const std::vector<uint64_t>& pos, const std::vector<uint64_t>& neg) {
  BenchResult r;
  warmup_queries(filter, pos, neg, c.neg_share, c.warmup_ops, c.seed ^ 0x1111ULL);

  double cycles_per_ns = calibrate_cycles_per_ns(30);

  std::vector<std::vector<double>> samples((size_t)c.threads);
  for (auto& v : samples) v.reserve(20000);

  uint64_t sample_mask = 255; // ~1/256 sampled

  auto worker = [&](int tid, uint64_t ops, std::atomic<uint64_t>& done) {
    pin_this_thread(tid);
    OpStream os((uint32_t)(c.seed + tid * 1337 + 7));
    size_t pN = pos.size(), nN = neg.size();
    for (uint64_t i = 0; i < ops; i++) {
      bool use_neg = os.frand() < c.neg_share;
      uint64_t k = use_neg ? neg[os.urand() % nN] : pos[os.urand() % pN];
      if ((i & sample_mask) == 0 && samples[(size_t)tid].size() < 20000) {
        uint64_t t0 = rdtscp_u64();
        (void)filter.contains(k);
        uint64_t t1 = rdtscp_u64();
        samples[(size_t)tid].push_back(double(t1 - t0) / cycles_per_ns);
      } else {
        (void)filter.contains(k);
      }
    }
    done.fetch_add(ops, std::memory_order_relaxed);
  };

  std::atomic<uint64_t> done{0};
  std::vector<std::thread> ths;
  uint64_t per = c.ops / (uint64_t)std::max(1, c.threads);
  uint64_t rem = c.ops - per * (uint64_t)std::max(1, c.threads);

  double t0 = now_sec();
  for (int t = 0; t < c.threads; t++) {
    uint64_t ops = per + (t == 0 ? rem : 0);
    ths.emplace_back(worker, t, ops, std::ref(done));
  }
  for (auto& t : ths) t.join();
  double t1 = now_sec();

  r.ops_per_s = double(done.load()) / std::max(1e-9, t1 - t0);

  std::vector<double> all;
  for (auto& v : samples) all.insert(all.end(), v.begin(), v.end());
  if (!all.empty()) {
    r.p50_ns = percentile(all, 0.50);
    r.p95_ns = percentile(all, 0.95);
    r.p99_ns = percentile(all, 0.99);
  }
  return r;
}

static BenchResult bench_mixed(const BenchConfig& c, IFilter& filter,
                               const std::vector<uint64_t>& pos,
                               const std::vector<uint64_t>& neg,
                               const std::vector<uint64_t>& updates) {
  BenchResult r;
  bool dynamic = (c.filter == "cuckoo" || c.filter == "quotient");
  double q_frac = 0.95;
  if (c.workload == "balanced") q_frac = 0.50;
  if (!dynamic) q_frac = 1.0;

  warmup_queries(filter, pos, neg, c.neg_share, c.warmup_ops, c.seed ^ 0x2222ULL);

  auto worker = [&](int tid, uint64_t ops, std::atomic<uint64_t>& done) {
    pin_this_thread(tid);
    OpStream os((uint32_t)(c.seed + tid * 7331 + 99));
    size_t pN = pos.size(), nN = neg.size(), uN = updates.size();

    for (uint64_t i = 0; i < ops; i++) {
      double x = os.frand();
      if (x < q_frac) {
        bool use_neg = os.frand() < c.neg_share;
        uint64_t k = use_neg ? neg[os.urand() % nN] : pos[os.urand() % pN];
        (void)filter.contains(k);
      } else {
        if (!dynamic) continue;
        uint64_t k = updates[os.urand() % uN];
        if (c.workload == "balanced") {
          if ((i & 1) == 0) (void)filter.insert(k);
          else (void)filter.erase(k);
        } else {
          (void)filter.insert(k);
        }
      }
    }
    done.fetch_add(ops, std::memory_order_relaxed);
  };

  std::atomic<uint64_t> done{0};
  std::vector<std::thread> ths;
  uint64_t per = c.ops / (uint64_t)std::max(1, c.threads);
  uint64_t rem = c.ops - per * (uint64_t)std::max(1, c.threads);

  double t0 = now_sec();
  for (int t = 0; t < c.threads; t++) {
    uint64_t ops = per + (t == 0 ? rem : 0);
    ths.emplace_back(worker, t, ops, std::ref(done));
  }
  for (auto& t : ths) t.join();
  double t1 = now_sec();

  r.ops_per_s = double(done.load()) / std::max(1e-9, t1 - t0);

  if (c.filter == "cuckoo") {
    auto* cf = dynamic_cast<CuckooFilter*>(&filter);
    if (cf) { r.fail_rate = cf->fail_rate(); r.avg_kicks = cf->avg_kicks(); r.stash_hits = (double)cf->stash_hits(); }
  } else if (c.filter == "quotient") {
    auto* qf = dynamic_cast<QuotientFilter*>(&filter);
    if (qf) { r.avg_probe = qf->avg_probe(); r.cluster_mean = qf->cluster_mean(); r.cluster_p99 = qf->cluster_p99(); }
  }

  return r;
}

static double compute_bpe(const IFilter& f) {
  uint64_t n = std::max<uint64_t>(1, f.size());
  return double(f.bytes() * 8) / double(n);
}

static void print_result_line(const BenchConfig& c, const BenchResult& r, double bpe) {
  std::ostringstream os;
  os << "run=" << c.run
     << " filter=" << c.filter
     << " dist=" << c.dist
     << " n=" << c.n
     << " target_fpr=" << std::setprecision(6) << c.target_fpr
     << " fp_bits=" << c.fp_bits
     << " achieved_fpr=" << std::setprecision(8) << r.achieved_fpr
     << " bpe=" << std::setprecision(6) << bpe
     << " workload=" << c.workload
     << " neg_share=" << c.neg_share
     << " threads=" << c.threads
     << " load_factor=" << c.load_factor
     << " ops_per_s=" << std::setprecision(6) << std::scientific << r.ops_per_s
     << " p50=" << std::fixed << std::setprecision(0) << r.p50_ns << "ns"
     << " p95=" << std::fixed << std::setprecision(0) << r.p95_ns << "ns"
     << " p99=" << std::fixed << std::setprecision(0) << r.p99_ns << "ns";

  if (c.filter == "cuckoo") {
    os << " fail_rate=" << std::setprecision(6) << r.fail_rate
       << " avg_kicks=" << std::setprecision(6) << r.avg_kicks
       << " stash_hits=" << std::setprecision(0) << r.stash_hits;
  } else if (c.filter == "quotient") {
    os << " avg_probe=" << std::setprecision(6) << r.avg_probe
       << " cluster_mean=" << std::setprecision(6) << r.cluster_mean
       << " cluster_p99=" << std::setprecision(6) << r.cluster_p99;
  }

  std::cout << os.str() << "\n";
}

int main(int argc, char** argv) {
  BenchConfig c = parse_args(argc, argv);

  auto pos = make_keys(c.n, c.dist, c.seed);
  auto neg = make_negative_keys(c.n, c.dist, c.seed, 0x9e3779b97f4a7c15ULL);
  auto updates = make_negative_keys(std::max<uint64_t>(1, c.n/10), c.dist, c.seed ^ 0x7777ULL, 0x12345678ULL);

  auto filt = make_filter(c);

  bool ok = filt->build(pos);
  if (!ok) std::cerr << "build_failed filter=" << c.filter << "\n";
  BenchResult r;
compute_fpr(*filt, neg, r);
double fpr_saved = r.achieved_fpr;

if (c.workload == "read_only") r = bench_read_only(c, *filt, pos, neg);
else                           r = bench_mixed(c, *filt, pos, neg, updates);

r.achieved_fpr = fpr_saved;   // restore it before printing

  double bpe = compute_bpe(*filt);

  if (c.check) {
    uint64_t miss = 0;
    for (size_t i = 0; i < std::min<size_t>(pos.size(), 20000); i++) {
      if (!filt->contains(pos[i])) miss++;
    }
    std::cerr << "check positives_sample_miss=" << miss << "\n";
  }

  print_result_line(c, r, bpe);
  return 0;
}
