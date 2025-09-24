// saxpy.cpp — control miss rate via footprint & stride; perf-friendly
// Build: g++ -O3 -march=native -std=c++17 -DNDEBUG saxpy.cpp -o saxpy
// Usage examples (see bottom of file)

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <chrono>
#include <vector>
#include <random>
#include <algorithm>
#include <string>
#include <unistd.h>
#include <sys/mman.h>   // madvise for huge pages

// Aligned allocation (64B for cacheline/AVX)
static float* alloc_aligned(size_t n_elems, size_t align = 64) {
    void* p = nullptr;
    if (posix_memalign(&p, align, n_elems * sizeof(float)) != 0) {
        return nullptr;
    }
    return reinterpret_cast<float*>(p);
}

struct Args {
    size_t n = 1 << 24;        // elements (default 16,777,216 ~ 64 MiB footprint for 2 arrays)
    size_t stride = 1;         // in elements (stride=1 is contiguous)
    int trials = 3;
    float alpha = 1.5f;
    bool warm = true;          // do a warm-up pass
    bool huge = false;         // try to hint huge pages (2 MiB)
    std::string pattern = "seq"; // "seq" or "rand" (rand = shuffled indices)
};

static void usage(const char* prog) {
    std::fprintf(stderr,
        "Usage: %s [--n <elements>] [--stride <elems>] [--trials <k>] [--alpha <f>] \n"
        "          [--pattern seq|rand] [--no-warm] [--huge]\n"
        "\n"
        "Examples:\n"
        "  %s --n 8388608 --stride 1           # ~32 MiB footprint, unit-stride (prefetch-friendly)\n"
        "  %s --n 33554432 --stride 4096       # ~128 MiB footprint, 16 KiB stride (1 per page @4KiB)\n"
        "  %s --n 16777216 --pattern rand      # random access to stress caches\n",
        prog, prog, prog, prog);
}

static Args parse(int argc, char** argv) {
    Args a;
    for (int i = 1; i < argc; ++i) {
        std::string s = argv[i];
        auto need = [&](const char* flag) {
            if (i + 1 >= argc) { std::fprintf(stderr, "Missing value after %s\n", flag); std::exit(1); }
            return argv[++i];
        };
        if (s == "--n")           a.n = std::strtoull(need("--n"), nullptr, 10);
        else if (s == "--stride") a.stride = std::strtoull(need("--stride"), nullptr, 10);
        else if (s == "--trials") a.trials = std::atoi(need("--trials"));
        else if (s == "--alpha")  a.alpha = std::atof(need("--alpha"));
        else if (s == "--pattern")a.pattern = need("--pattern");
        else if (s == "--no-warm")a.warm = false;
        else if (s == "--huge")   a.huge = true;
        else if (s == "--help" || s == "-h") { usage(argv[0]); std::exit(0); }
        else { std::fprintf(stderr, "Unknown arg: %s\n", s.c_str()); usage(argv[0]); std::exit(1); }
    }
    if (a.stride == 0) a.stride = 1;
    return a;
}

int main(int argc, char** argv) {
    Args args = parse(argc, argv);

    const size_t N = args.n;
    const size_t S = args.stride;

    // Allocate two arrays (x and y). SAXPY touches both → footprint ≈ 2 * N * 4 bytes.
    float* x = alloc_aligned(N);
    float* y = alloc_aligned(N);
    if (!x || !y) { std::fprintf(stderr, "alloc failed\n"); return 2; }

    // Optional: huge page hint (works best if THP is enabled). Safe no-op if denied.
    if (args.huge) {
        madvise(x, N * sizeof(float), MADV_HUGEPAGE);
        madvise(y, N * sizeof(float), MADV_HUGEPAGE);
    }

    // Init with non-trivial values to avoid constant-folding or fast-path zeros.
    std::mt19937 rng(12345);
    std::uniform_real_distribution<float> dist(0.9f, 1.1f);
    for (size_t i = 0; i < N; ++i) {
        x[i] = dist(rng);
        y[i] = dist(rng);
    }

    // Optional index vector to support random access (to break spatial locality entirely).
    std::vector<size_t> idx;
    if (args.pattern == "rand") {
        idx.resize(N);
        for (size_t i = 0; i < N; ++i) idx[i] = i;
        std::shuffle(idx.begin(), idx.end(), rng);
    }

    const float alpha = args.alpha;

    // Warm-up to stabilize clocks & TLBs (does not count in reported times)
    if (args.warm) {
        if (args.pattern == "seq") {
            for (size_t i = 0; i < N; i += S) {
                y[i] = alpha * x[i] + y[i];
            }
        } else {
            for (size_t k = 0; k < N; ++k) {
                size_t i = idx[k];
                y[i] = alpha * x[i] + y[i];
            }
        }
    }

    // Trials
    double best_ms = 1e300, sum_ms = 0.0;
    volatile double checksum = 0.0; // prevent optimizing away

    for (int t = 0; t < args.trials; ++t) {
        // Restore y to baseline each trial (so work is comparable)
        for (size_t i = 0; i < N; ++i) y[i] = dist(rng);

        auto t0 = std::chrono::high_resolution_clock::now();

        if (args.pattern == "seq") {
            // Strided sequential access
            for (size_t i = 0; i < N; i += S) {
                y[i] = alpha * x[i] + y[i];
            }
        } else {
            // Random access
            for (size_t k = 0; k < N; ++k) {
                size_t i = idx[k];
                y[i] = alpha * x[i] + y[i];
            }
        }

        auto t1 = std::chrono::high_resolution_clock::now();
        double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
        sum_ms += ms; if (ms < best_ms) best_ms = ms;

        // Touch results to ensure the compiler can't drop the work
        double partial = 0.0;
        for (size_t i = 0; i < N; i += (N/1024 + 1)) partial += y[i];
        checksum += partial;
    }

    // FLOPs: SAXPY does 2 flops/element; we executed ~ceil(N/stride) updates for seq pattern.
    double iters = (args.pattern == "seq") ? std::ceil(double(N) / double(S)) : double(N);
    double flops = 2.0 * iters;
    double bytes_touched =  (args.pattern == "seq" ? iters : iters) * (sizeof(float) * 2); // x[i] read + y[i] R/W; lower bound

    double avg_ms = sum_ms / args.trials;
    double gflops_best = (flops / 1e9) / (best_ms / 1e3);
    double gflops_avg  = (flops / 1e9) / (avg_ms  / 1e3);
    double gibps_best  = (bytes_touched / (1024.0*1024.0*1024.0)) / (best_ms / 1e3);
    double gibps_avg   = (bytes_touched / (1024.0*1024.0*1024.0)) / (avg_ms  / 1e3);

    std::printf("# SAXPY summary\n");
    std::printf("n=%zu stride=%zu trials=%d pattern=%s alpha=%.2f huge=%d\n",
                N, S, args.trials, args.pattern.c_str(), alpha, args.huge ? 1 : 0);
    std::printf("best_ms=%.3f avg_ms=%.3f checksum=%.6f\n", best_ms, avg_ms, checksum);
    std::printf("gflops_best=%.3f gflops_avg=%.3f  gibps_best=%.3f gibps_avg=%.3f\n",
                gflops_best, gflops_avg, gibps_best, gibps_avg);

    // Minimal CSV line for perf post-processing
    std::printf("CSV,n,%zu,stride,%zu,pattern,%s,best_ms,%.3f,avg_ms,%.3f\n",
                N, S, args.pattern.c_str(), best_ms, avg_ms);

    std::free(x); std::free(y);
    return 0;
}
