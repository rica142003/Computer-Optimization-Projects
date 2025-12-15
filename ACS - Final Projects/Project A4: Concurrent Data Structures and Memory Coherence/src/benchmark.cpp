
#include "hashtable.h"
#include <atomic>
#include <chrono>
#include <cstring>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

static inline uint64_t xorshift64(uint64_t &s) {
  s ^= s << 13;
  s ^= s >> 7;
  s ^= s << 17;
  return s;
}

struct Args {
  std::string variant = "coarse";   // coarse | striped
  std::string workload = "mixed";   // lookup | insert | mixed
  uint64_t nkeys = 100000;
  int threads = 1;
  int seconds = 2;
  uint64_t seed = 1;
  uint64_t nbuckets = 1<<20;        // default; will be adjusted
  uint64_t stripes = 256;
};

static void usage(const char *prog) {
  std::cerr
    << "Usage: " << prog << " [options]\n"
    << "  --variant   coarse|striped\n"
    << "  --workload  lookup|insert|mixed\n"
    << "  --nkeys     N (prefill keys)\n"
    << "  --threads   T\n"
    << "  --seconds   duration seconds\n"
    << "  --seed      RNG seed\n"
    << "  --nbuckets  number of buckets\n"
    << "  --stripes   number of stripe locks (striped variant)\n";
}

static bool parse_int(const char* s, uint64_t &out) {
  char *end = nullptr;
  unsigned long long v = std::strtoull(s, &end, 10);
  if (!end || *end != '\0') return false;
  out = (uint64_t)v;
  return true;
}

static bool parse_args(int argc, char **argv, Args &a) {
  for (int i = 1; i < argc; i++) {
    std::string k = argv[i];
    auto need = [&](const char* opt)->const char* {
      if (i+1 >= argc) { std::cerr << "Missing value for " << opt << "\n"; return nullptr; }
      return argv[++i];
    };
    if (k == "--variant") a.variant = need("--variant");
    else if (k == "--workload") a.workload = need("--workload");
    else if (k == "--nkeys") { uint64_t v; if(!parse_int(need("--nkeys"), v)) return false; a.nkeys=v; }
    else if (k == "--threads") { uint64_t v; if(!parse_int(need("--threads"), v)) return false; a.threads=(int)v; }
    else if (k == "--seconds") { uint64_t v; if(!parse_int(need("--seconds"), v)) return false; a.seconds=(int)v; }
    else if (k == "--seed") { uint64_t v; if(!parse_int(need("--seed"), v)) return false; a.seed=v; }
    else if (k == "--nbuckets") { uint64_t v; if(!parse_int(need("--nbuckets"), v)) return false; a.nbuckets=v; }
    else if (k == "--stripes") { uint64_t v; if(!parse_int(need("--stripes"), v)) return false; a.stripes=v; }
    else if (k == "-h" || k == "--help") { usage(argv[0]); return false; }
    else { std::cerr << "Unknown option: " << k << "\n"; usage(argv[0]); return false; }
  }
  return true;
}

int main(int argc, char **argv) {
  Args a;
  if (!parse_args(argc, argv, a)) return 1;

  Variant v = (a.variant == "striped") ? Variant::STRIPED : Variant::COARSE;

  // Choose buckets so average chain length stays small.
  uint64_t nb = a.nbuckets;
  if (nb < a.nkeys * 2) nb = 1;
  while (nb < a.nkeys * 2) nb <<= 1;

  HashTable ht((size_t)nb, v, (size_t)a.stripes);

  // Prefill keys [0, nkeys)
  for (uint64_t k = 0; k < a.nkeys; k++) ht.insert(k, k);

  std::atomic<bool> start{false};
  std::atomic<bool> stop{false};

  std::vector<uint64_t> ops(a.threads, 0);
  std::vector<uint64_t> finds(a.threads, 0);
  std::vector<uint64_t> inserts(a.threads, 0);
  std::vector<uint64_t> misses(a.threads, 0);

  auto t_begin = std::chrono::steady_clock::now();
  auto t_end_target = t_begin + std::chrono::seconds(a.seconds);

  std::vector<std::thread> th;
  th.reserve(a.threads);

  for (int tid = 0; tid < a.threads; tid++) {
    th.emplace_back([&, tid](){
      uint64_t s = a.seed ^ (0x9e3779b97f4a7c15ull + (uint64_t)tid*0xBF58476D1CE4E5B9ull);
      uint64_t local_ops = 0, local_f=0, local_i=0, local_m=0;
      uint64_t dummy = 0;

      while (!start.load(std::memory_order_acquire)) { /* spin */ }

      while (!stop.load(std::memory_order_relaxed)) {
        uint64_t r = xorshift64(s);
        bool do_find = false;
        if (a.workload == "lookup") do_find = true;
        else if (a.workload == "insert") do_find = false;
        else { // mixed 70/30
          do_find = (r % 10) < 7;
        }

        if (do_find) {
          uint64_t key = r % a.nkeys;
          if (ht.find(key, dummy)) { /* hit */ }
          else local_m++;
          local_f++;
        } else {
          // Insert keys in a disjoint range to avoid too many updates.
          uint64_t key = a.nkeys + (r % (a.nkeys));
          ht.insert(key, key);
          local_i++;
        }
        local_ops++;

        if ((local_ops & 0x3FFF) == 0) {
          // cheap stop check
          if (std::chrono::steady_clock::now() >= t_end_target) break;
        }
      }
      ops[tid] = local_ops;
      finds[tid] = local_f;
      inserts[tid] = local_i;
      misses[tid] = local_m;
    });
  }

  start.store(true, std::memory_order_release);
  std::this_thread::sleep_for(std::chrono::seconds(a.seconds));
  stop.store(true, std::memory_order_release);

  for (auto &t : th) t.join();

  auto t_done = std::chrono::steady_clock::now();
  double secs = std::chrono::duration<double>(t_done - t_begin).count();

  uint64_t total_ops=0,total_f=0,total_i=0,total_m=0;
  for (int i=0;i<a.threads;i++){
    total_ops += ops[i];
    total_f += finds[i];
    total_i += inserts[i];
    total_m += misses[i];
  }

  double ops_s = (secs > 0) ? (double)total_ops / secs : 0.0;

  // CSV header (documented in scripts/parse_perf.py)
  // variant,workload,nkeys,threads,seconds,seed,ops,total_finds,total_inserts,total_misses,ops_per_s
  std::cout
    << a.variant << ","
    << a.workload << ","
    << a.nkeys << ","
    << a.threads << ","
    << a.seconds << ","
    << a.seed << ","
    << total_ops << ","
    << total_f << ","
    << total_i << ","
    << total_m << ","
    << ops_s
    << "\n";

  return 0;
}
