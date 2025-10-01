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
#include <random>
#include <sys/resource.h>
#include <sched.h>

using namespace std;
using namespace chrono;

// Memory allocation
template<typename T>
unique_ptr<T[]> aligned_array(size_t n, size_t alignment = 64) {
    void* data = nullptr;
    if (posix_memalign(&data, alignment, n * sizeof(T)) != 0) throw bad_alloc();
    return unique_ptr<T[]>(static_cast<T*>(data));
}

// Kernels
void saxpy_stride(float a, const float* x, float* y, size_t n, size_t stride) {
    #pragma omp simd
    for (size_t i = 0; i < n; i += stride) y[i] = a * x[i] + y[i];
}

void saxpy_gather(float a, const float* x, float* y, const int* idx, size_t n) {
    #pragma omp simd
    for (size_t i = 0; i < n; ++i) y[idx[i]] = a * x[idx[i]] + y[idx[i]];
}

// Benchmark harness
double benchmark(const std::function<void()>& kernel, int min_iters = 100, double min_sec = 1.0) {
    for (int i=0;i<50;i++) kernel();
    int iters=0; double total=0; vector<double> times;
    while (iters < min_iters || total < min_sec*1e9) {
        auto s=high_resolution_clock::now(); kernel(); auto e=high_resolution_clock::now();
        double el = duration_cast<nanoseconds>(e-s).count();
        times.push_back(el); total += el; iters++;
    }
    sort(times.begin(), times.end());
    return times[times.size()/2];
}

void set_high_priority(){ setpriority(PRIO_PROCESS,0,-20); }

int main() {
    set_high_priority();
    ofstream csv("stride_gather_results.csv");
    csv << "Kernel,Size,Memory_KB,Time_ns,GFLOPs,Case,Trial\n";

    const int trials=3;
    cpu_set_t cpuset; CPU_ZERO(&cpuset); CPU_SET(0,&cpuset);
    sched_setaffinity(0,sizeof(cpuset),&cpuset);

    size_t n = 1<<16; // 65536
    auto x = aligned_array<float>(n,64);
    auto y = aligned_array<float>(n,64);
    fill_n(x.get(),n,1.0f);
    fill_n(y.get(),n,2.0f);

    // Index array for gather
    vector<int> idx(n);
    iota(idx.begin(),idx.end(),0);
    shuffle(idx.begin(),idx.end(),mt19937(42));
    auto idx_arr = aligned_array<int>(n,64);
    copy(idx.begin(),idx.end(),idx_arr.get());

    for (int trial=1; trial<=trials; trial++) {
        // Stride tests
        for (int stride : {1,2,4,8,16,32}) {
            double t = benchmark([&](){ saxpy_stride(2.0f,x.get(),y.get(),n,stride); });
            double gflops = (2.0*(n/stride))/(t/1e9)/1e9;
            csv << "SAXPY,"<<n<<","<<(n*4*2/1024.0)<<","<<t<<","<<gflops<<",Stride="<<stride<<","<<trial<<"\n";
        }
        // Gather test
        double t = benchmark([&](){ saxpy_gather(2.0f,x.get(),y.get(),idx_arr.get(),n); });
        double gflops = (2.0*n)/(t/1e9)/1e9;
        csv << "SAXPY,"<<n<<","<<(n*4*2/1024.0)<<","<<t<<","<<gflops<<",Gather,"<<trial<<"\n";
    }

    cout << "Results saved to stride_gather_results.csv\n";
    return 0;
}
