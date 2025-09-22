#include <iostream>
#include <chrono>
#include <vector>
#include <cmath>
#include <cstdlib>
#include <functional>
#include <algorithm>
#include <memory>
#include <fstream>
#include <numeric>
#include <sys/resource.h>
#include <sched.h>

using namespace std;
using namespace chrono;

// Safe aligned memory allocation
template<typename T>
unique_ptr<T[]> aligned_array(size_t n, size_t alignment = 64) {
    void* data = nullptr;
    if (posix_memalign(&data, alignment, n * sizeof(T)) != 0) {
        throw bad_alloc();
    }
    return unique_ptr<T[]>(static_cast<T*>(data));
}

// Kernels
void saxpy(float a, const float* x, float* y, size_t n) {
    #pragma omp simd
    for (size_t i = 0; i < n; ++i) y[i] = a * x[i] + y[i];
}

// Benchmark harness
double benchmark(const std::function<void()>& kernel, int min_iters = 100, double min_sec = 1.0) {
    for (int i = 0; i < 50; ++i) kernel(); // warmup iterations
    int iters = 0;
    double total_time = 0;
    vector<double> times;
    while (iters < min_iters || total_time < min_sec * 1e9) {
        auto start = high_resolution_clock::now();
        kernel();
        auto end = high_resolution_clock::now();
        double elapsed = duration_cast<nanoseconds>(end - start).count();
        times.push_back(elapsed);
        total_time += elapsed;
        iters++;
    }
    sort(times.begin(), times.end());
    return times[times.size()/2]; // median
}

void set_high_priority() { setpriority(PRIO_PROCESS, 0, -20); }

int main() {
    set_high_priority();
    ofstream csv("alignment_tail_results.csv");
    csv << "Kernel,Size,Memory_KB,Time_ns,GFLOPs,Case,Trial\n";

    const int trials = 3;
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset); CPU_SET(0, &cpuset);
    sched_setaffinity(0, sizeof(cpuset), &cpuset);

    // Choose sizes: aligned multiples and some odd sizes (tail)
    vector<size_t> sizes = {512, 1024, 1500, 2000, 4096, 6000, 8192};

    for (size_t n : sizes) {
        cout << "Testing n=" << n << endl;
        auto x = aligned_array<float>(n+16, 64);
        auto y = aligned_array<float>(n+16, 64);

        // Initialize
        fill_n(x.get(), n+16, 1.0f);
        fill_n(y.get(), n+16, 2.0f);

        // Cache warm-up: touch everything once
        volatile float sink = 0;
        for (size_t i = 0; i < n; i++) sink += x[i] + y[i];

        float* x_aligned = x.get();
        float* y_aligned = y.get();
        float* x_misaligned = x.get() + 1; // shift by 1 element
        float* y_misaligned = y.get() + 1;

        for (int trial=1; trial<=trials; trial++) {
            // Aligned
            double t = benchmark([&](){ saxpy(2.0f, x_aligned, y_aligned, n); });
            double gflops = (2.0*n)/(t/1e9)/1e9;
            csv << "SAXPY," << n << "," << (n*4*3/1024.0) << "," << t << "," << gflops << ",Aligned," << trial << "\n";

            // Misaligned
            t = benchmark([&](){ saxpy(2.0f, x_misaligned, y_misaligned, n); });
            gflops = (2.0*n)/(t/1e9)/1e9;
            csv << "SAXPY," << n << "," << (n*4*3/1024.0) << "," << t << "," << gflops << ",Misaligned," << trial << "\n";
        }
    }

    cout << "Results saved to alignment_tail_results.csv\n";
    return 0;
}
