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

// ---------------- Kernels (templated) ----------------
template<typename T>
void saxpy(T a, const T* x, T* y, size_t n) {
    #pragma omp simd
    for (size_t i = 0; i < n; ++i) {
        y[i] = a * x[i] + y[i];
    }
}

template<typename T>
void stencil(const T* input, T* output, size_t n) {
    #pragma omp simd
    for (size_t i = 1; i < n - 1; ++i) {
        output[i] = input[i-1] + input[i] + input[i+1];
    }
}

template<typename T>
void elementwise_mult(const T* a, const T* b, T* c, size_t n) {
    #pragma omp simd
    for (size_t i = 0; i < n; ++i) {
        c[i] = a[i] * b[i];
    }
}

// ---------------- Benchmark ----------------
double benchmark(const std::function<void()>& kernel, int min_iterations = 100, double min_duration = 1.0) {
    for (int i = 0; i < 50; ++i) kernel(); // warmup
    
    int iterations = 0;
    double total_time = 0;
    vector<double> times;
    
    while (iterations < min_iterations || total_time < min_duration * 1e9) {
        auto start = high_resolution_clock::now();
        kernel();
        auto end = high_resolution_clock::now();
        double elapsed = duration_cast<nanoseconds>(end - start).count();
        times.push_back(elapsed);
        total_time += elapsed;
        iterations++;
    }
    sort(times.begin(), times.end());
    return times[times.size() / 2]; // median
}

// ---------------- Priority ----------------
void set_high_priority() {
    setpriority(PRIO_PROCESS, 0, -20);
}

// ---------------- Run kernels for type ----------------
template<typename T>
void run_kernels(const string& dtype, ofstream& csv_file, const vector<size_t>& sizes, int num_trials) {
    for (size_t n : sizes) {
        cout << "[" << dtype << "] Testing n = " << n 
             << " (memory: " << (n * sizeof(T) * 3 / 1024.0) << " KB)" << endl;
        
        auto x = aligned_array<T>(n);
        auto y = aligned_array<T>(n);
        auto in = aligned_array<T>(n);
        auto out = aligned_array<T>(n);
        auto a = aligned_array<T>(n);
        auto b = aligned_array<T>(n);
        auto c = aligned_array<T>(n);

        fill_n(x.get(), n, T(1.0));
        fill_n(y.get(), n, T(2.0));
        fill_n(in.get(), n, T(1.0));
        fill_n(out.get(), n, T(0.0));
        fill_n(a.get(), n, T(1.0));
        fill_n(b.get(), n, T(2.0));
        fill_n(c.get(), n, T(0.0));

        volatile T sink;
        for (size_t i = 0; i < n; ++i)
            sink = x[i] + y[i] + in[i] + out[i] + a[i] + b[i] + c[i];

        for (int trial = 0; trial < num_trials; trial++) {
            cout << "Trial " << trial + 1 << " of " << num_trials << endl;

            // SAXPY
            auto saxpy_kernel = [&]() { saxpy<T>(T(2.0), x.get(), y.get(), n); };
            double saxpy_time = benchmark(saxpy_kernel, 100, 1.0);
            double saxpy_gflops = (2.0 * n) / (saxpy_time / 1e9) / 1e9;
            csv_file << "SAXPY-" << dtype << "," << n << "," << (n * sizeof(T) * 3 / 1024.0)
                     << "," << saxpy_time << "," << saxpy_gflops << ",Vectorized," << trial+1 << endl;

            // Stencil
            auto stencil_kernel = [&]() { stencil<T>(in.get(), out.get(), n); };
            double stencil_time = benchmark(stencil_kernel, 100, 1.0);
            double stencil_gflops = (2.0 * n) / (stencil_time / 1e9) / 1e9;
            csv_file << "Stencil-" << dtype << "," << n << "," << (n * sizeof(T) * 3 / 1024.0)
                     << "," << stencil_time << "," << stencil_gflops << ",Vectorized," << trial+1 << endl;

            // Elementwise
            auto mult_kernel = [&]() { elementwise_mult<T>(a.get(), b.get(), c.get(), n); };
            double mult_time = benchmark(mult_kernel, 100, 1.0);
            double mult_gflops = (1.0 * n) / (mult_time / 1e9) / 1e9;
            csv_file << "Elementwise-" << dtype << "," << n << "," << (n * sizeof(T) * 3 / 1024.0)
                     << "," << mult_time << "," << mult_gflops << ",Vectorized," << trial+1 << endl;
        }
        cout << "----------------------------------------" << endl;
    }
}

int main() {
    set_high_priority();
    ofstream csv_file("benchmark_results.csv");
    csv_file << "Kernel,Size,Memory_KB,Time_ns,GFLOPs,Vectorization,Trial" << endl;
    
    const int num_trials = 5;

    // Pin to core 0
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(0, &cpuset);
    sched_setaffinity(0, sizeof(cpuset), &cpuset);

    // Cache sizes
    const size_t L1_SIZE = 384 * 1024;
    const size_t L2_SIZE = 10 * 1024 * 1024;
    const size_t LLC_SIZE = 18 * 1024 * 1024;
    const size_t DRAM_SIZE = 32 * 1024 * 1024;

    vector<size_t> sizes = {
        L1_SIZE / (4 * 3), L2_SIZE / (4 * 3), LLC_SIZE / (4 * 3), DRAM_SIZE / (4 * 3)
    };
    for (size_t base : {L1_SIZE/(4*3), L2_SIZE/(4*3), LLC_SIZE/(4*3)}) {
        sizes.push_back(base * 0.8);
        sizes.push_back(base * 1.2);
    }
    size_t biggest = DRAM_SIZE / (4 * 3);
    sizes.push_back(biggest * 2);
    sizes.push_back(biggest * 4);
    sort(sizes.begin(), sizes.end());
    sizes.erase(unique(sizes.begin(), sizes.end()), sizes.end());

    // Run for float32
    run_kernels<float>("float32", csv_file, sizes, num_trials);
    // Run for float64
    run_kernels<double>("float64", csv_file, sizes, num_trials);

    csv_file.close();
    cout << "Results saved to benchmark_results.csv" << endl;
    return 0;
}
