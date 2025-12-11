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

// Kernels using raw pointers for better control
void saxpy(float a, const float* x, float* y, size_t n) {
    #pragma omp simd
    for (size_t i = 0; i < n; ++i) {
        y[i] = a * x[i] + y[i];
    }
}

void stencil(const float* input, float* output, size_t n) {
    #pragma omp simd
    for (size_t i = 1; i < n - 1; ++i) {
        output[i] = input[i-1] + input[i] + input[i+1];
    }
}

void elementwise_mult(const float* a, const float* b, float* c, size_t n) {
    #pragma omp simd
    for (size_t i = 0; i < n; ++i) {
        c[i] = a[i] * b[i];
    }
}

// More robust benchmarking with improved timing
double benchmark(const std::function<void()>& kernel, int min_iterations = 100, double min_duration = 1.0) {
    // Extended warmup to stabilize CPU frequency and caches
    for (int i = 0; i < 50; ++i) {
        kernel();
    }
    
    int iterations = 0;
    double total_time = 0;
    vector<double> times;
    
    // Run for at least min_duration seconds and min_iterations
    while (iterations < min_iterations || total_time < min_duration * 1e9) {
        auto start = high_resolution_clock::now();
        kernel();
        auto end = high_resolution_clock::now();
        double elapsed = duration_cast<nanoseconds>(end - start).count();
        times.push_back(elapsed);
        total_time += elapsed;
        iterations++;
    }
    
    // Use median instead of mean to reduce outlier impact
    sort(times.begin(), times.end());
    return times[times.size() / 2]; // Return median time
}

// Function to set high process priority
void set_high_priority() {
    setpriority(PRIO_PROCESS, 0, -20);
}

int main() {
    // Try to set high priority (may require sudo)
    set_high_priority();
    
    ofstream csv_file("benchmark_results.csv");
    
    // Write CSV header
    csv_file << "Kernel,Size,Memory_KB,Time_ns,GFLOPs,Vectorization,Trial" << endl;
    
    const int num_trials = 5;
    
    try {
        // Set thread affinity to a specific core for more consistent results
        cpu_set_t cpuset;
        CPU_ZERO(&cpuset);
        CPU_SET(0, &cpuset); // Use core 0
        sched_setaffinity(0, sizeof(cpuset), &cpuset);
        
        // Your cache sizes
        const size_t L1_SIZE = 384 * 1024;       // 384 KiB
        const size_t L2_SIZE = 10 * 1024 * 1024; // 10 MiB
        const size_t LLC_SIZE = 18 * 1024 * 1024; // 18 MiB
        const size_t DRAM_SIZE = 32 * 1024 * 1024; // 32 MB

        // Calculate problem sizes that fit in different cache levels
        vector<size_t> sizes = {
            L1_SIZE / (4 * 3),    // L1 cache
            L2_SIZE / (4 * 3),    // L2 cache
            LLC_SIZE / (4 * 3),   // L3 cache
            DRAM_SIZE / (4 * 3)   // DRAM
        };
        
        // Add some sizes around the boundaries
        for (size_t base : {L1_SIZE/(4*3), L2_SIZE/(4*3), LLC_SIZE/(4*3)}) {
            sizes.push_back(base * 0.8);
            sizes.push_back(base * 1.2);
        }

        size_t biggest = DRAM_SIZE / (4 * 3);
        sizes.push_back(biggest * 2);   // 2× DRAM
        sizes.push_back(biggest * 4);   // 4× DRAM
        
        // Sort and remove duplicates
        sort(sizes.begin(), sizes.end());
        sizes.erase(unique(sizes.begin(), sizes.end()), sizes.end());
        
        for (size_t n : sizes) {
            cout << "Testing n = " << n << " (memory: " << (n * 4 * 3 / 1024.0) << " KB)" << endl;
            
            // Allocate aligned memory
            auto x = aligned_array<float>(n, 64);
            auto y = aligned_array<float>(n, 64);
            auto in = aligned_array<float>(n, 64);
            auto out = aligned_array<float>(n, 64);
            auto a = aligned_array<float>(n, 64);
            auto b = aligned_array<float>(n, 64);
            auto c = aligned_array<float>(n, 64);
            
            // Initialize arrays
            fill_n(x.get(), n, 1.0f);
            fill_n(y.get(), n, 2.0f);
            fill_n(in.get(), n, 1.0f);
            fill_n(out.get(), n, 0.0f);
            fill_n(a.get(), n, 1.0f);
            fill_n(b.get(), n, 2.0f);
            fill_n(c.get(), n, 0.0f);
            
            // Pre-warm the caches by touching all memory
            volatile float sink;
            for (size_t i = 0; i < n; ++i) {
                sink = x[i] + y[i] + in[i] + out[i] + a[i] + b[i] + c[i];
            }
            
            // Run multiple trials for each kernel
            for (int trial = 0; trial < num_trials; trial++) {
                cout << "Trial " << trial + 1 << " of " << num_trials << endl;
                
                // SAXPY
                auto saxpy_kernel = [&]() { saxpy(2.0f, x.get(), y.get(), n); };
                double saxpy_time = benchmark(saxpy_kernel, 100, 1.0);
                double saxpy_gflops = (2.0 * n) / (saxpy_time / 1e9) / 1e9;
                
                // Write to CSV
                csv_file << "SAXPY," << n << "," << (n * 4 * 3 / 1024.0) << "," 
                         << saxpy_time << "," << saxpy_gflops << ",Vectorized," << trial + 1 << endl;
                
                // Stencil
                auto stencil_kernel = [&]() { stencil(in.get(), out.get(), n); };
                double stencil_time = benchmark(stencil_kernel, 100, 1.0);
                double stencil_gflops = (2.0 * n) / (stencil_time / 1e9) / 1e9;
                
                // Write to CSV
                csv_file << "Stencil," << n << "," << (n * 4 * 3 / 1024.0) << "," 
                         << stencil_time << "," << stencil_gflops << ",Vectorized," << trial + 1 << endl;
                
                // Element-wise multiplication
                auto mult_kernel = [&]() { elementwise_mult(a.get(), b.get(), c.get(), n); };
                double mult_time = benchmark(mult_kernel, 100, 1.0);
                double mult_gflops = (1.0 * n) / (mult_time / 1e9) / 1e9;
                
                // Write to CSV
                csv_file << "Elementwise," << n << "," << (n * 4 * 3 / 1024.0) << "," 
                         << mult_time << "," << mult_gflops << ",Vectorized," << trial + 1 << endl;
            }
            
            cout << "----------------------------------------" << endl;
        }
    } catch (const bad_alloc& e) {
        cerr << "Memory allocation failed: " << e.what() << endl;
        csv_file.close();
        return 1;
    } catch (const exception& e) {
        cerr << "Error: " << e.what() << endl;
        csv_file.close();
        return 1;
    }
    
    csv_file.close();
    cout << "Results saved to benchmark_results.csv" << endl;
    
    return 0;
}
