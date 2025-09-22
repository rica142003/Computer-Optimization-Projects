# SIMD Advantage Profiling

## Table of Contents
- [Introduction](#introduction)
- [Tools and Setup](#tools-and-setup)
- [Kernels and Flop Counts](#kernels-and-flop-counts)
- [Test 1: Baseline (scalar) vs autovectorized with locality sweep](#test-1-baseline-scalar-vs-autovectorized-with-locality-sweep)
  - [Warmup and Timing](#warmup-and-timing)
  - [Locality Sweep](#locality-sweep)
  - [Repetitions and Data Collection](#repetitions-and-data-collection)
  - [Compilation](#compilation)
- [Test 2: Alignment and Tail Handling](#test-2-alignment-and-tail-handling)
- [Test 3: Stride and Gather Effects](#test-3-stride-and-gather-effects)
- [Results and Discussion](#results-and-discussion)
  - [Vectorization Verification](#vectorization-verification)
  - [Baseline (scalar) vs auto-vectorized](#baseline-scalar-vs-auto-vectorized)
  - [Runtime vs Data Set Size](#runtime-vs-data-set-size)
  - [Locality sweep in GFLOP/s and CPE](#locality-sweep-in-gflops-and-cpe)
  - [Alignment and Tail Handling](#alignment-and-tail-handling)
  - [Stride/gather effects](#stridegather-effects)
  - [Float32 vs Float64](#float32-vs-float64)
- [Roofline Model](#roofline-model)
- [Appendix](#appendix)

## Introduction

## Tools and Setup
GCC version 9.4.0 is used in a Linux WSL (Ubuntu 20.04.2) to compile C++ code. For the specific optimizers enabled check Appendix A. When compiling `-march=native` is set which means it enables all SIMD instructions the CPU supports. To check for the specific ISAs, fast math options, and FTZ/DAZ settings, a simple program is run with vectorization enabled with `-###` added to the compile. The following is seen:
```
"-march=tigerlake"
-msse -msse2 -msse3 -mssse3 -msse4.1 -msse4.2
-mavx -mavx2
-mfma
-mf16c -mlzcnt -mbmi -mbmi2
-m...
-mno-avx512f ...
```
This shows that the CPU (11th generation Intel Core) supports up through AVX2 + FMA, but not AVX-512 (notice all `-mno-avx512*`). This is also seen here:

<p align="left">
  <img  src="https://github.com/user-attachments/assets/8437c096-8419-4c60-939e-102ee2c8501e" style="width: 80%; height: auto;">
</p>

There's avx, avx2, and fma listed, but not avx512f.

To reduce run-to-run variance, the CPU frequency is fixed. Using `lscpu | grep "MHz"` the CPU frequency was found to be 2496.011MHz. 
To pin a program to a core, `lscpu -e` was used to check the number of cores and threads on each core, the following in seen:
<p align="left">
  <img  src="https://github.com/user-attachments/assets/2dc35ec7-51fa-43db-a969-e68d54810a86" style="width: 30%; height: auto;">
</p>

From the above (and running `lscpu | grep Thread`) we know that SMT is on as there's 2 threads running per core.
To pin to the first thread of core 1 each of the files is run with `taskset -c 2 ./program`. 

---

### Kernels and Flop Counts
1. **SAXPY / AXPY**

    SAXPY is streaming muliply and add, it has 1 multiply and 1 add, which makes it 2 FLOPs/element. 
```c++
void saxpy(float a, const float* x, float* y, size_t n) {
    for (size_t i = 0; i < n; ++i) {
        y[i] = a * x[i] + y[i];
    }
}
```

2. **Elementwise multiply**

    It is implemented as:
```c++
void elementwise_mult(const float* a, const float* b, float* c, size_t n) {
    #pragma omp simd
    for (size_t i = 0; i < n; ++i) {
        c[i] = a[i] * b[i];
    }
}
```

3. **1D 3-point Stencil**

    This kernel has 3 multiplys and 2 adds, which gives 5 FLOPs/element. It's implemented as:
```c++
void stencil(const float* input, float* output, size_t n) {
    #pragma omp simd
    for (size_t i = 1; i < n - 1; ++i) {
        output[i] = input[i-1] + input[i] + input[i+1];
    }
}
```

---
## Test 1: Baseline (scalar) vs autovectorized with locality sweep 
This program is designed to sweep across problem sizes, benchmark kernels, and compare SIMD/vectorized vs scalar execution

### Warmup and Timing 

The first step is a warmup phase, where the kernel is run fifty times before any measurements are taken. This is done to stabilize the CPU frequency, prime the instruction and data caches. Once the warmup is complete, the function enters a measurement loop.

For each iteration, the program records a timestamp immediately before the kernel executes and another timestamp right after it finishes. These timestamps are taken using `std::chrono::high_resolution_clock`, which provides nanosecond precision. This process is repeated many times, ensuring that at least 100 iterations are performed and that the total accumulated run time exceeds one full second. These two conditions together help reduce noise.

Instead of returning the average (which can be skewed by outliers), it sorts all collected timings and returns the median.This timing is combined with the number of floating-point operations performed in the kernel to compute performance in GFLOP/s.
```
double gflops = (operations * n) / (time_in_seconds) / 1e9;
```
### Locality Sweep

The size of the cache on my computer is as follows:
<p align="left">
  <img  src="https://github.com/user-attachments/assets/d72c7bd2-2e66-4d7b-b168-de6df3e5efc5" style="width: 50%; height: auto;">
</p>

The program systematically tests kernel performance at different problem sizes that correspond to the capacity of the memory hierarchy (L1, L2, L3, DRAM). In the `main()` function, the code sets up representative sizes:
```
const size_t L1_SIZE = 384 * 1024;       // 384 KiB
const size_t L2_SIZE = 10 * 1024 * 1024; // 10 MiB
const size_t LLC_SIZE = 18 * 1024 * 1024; // 18 MiB
const size_t DRAM_SIZE = 32 * 1024 * 1024; // 32 MB
```

### Repetitions and Data Collection

In addition to warmup and median-based timing, the program runs five independent trials for each kernel and problem size. Running 5 trials creates small dataset that can later be aggregated (e.g., average and standard deviation) which gives error bars when plotting results. 

The results are stored as a .csv file, from which the speedup can be calucated using: $\frac{T_{scalar}}{T_{vectorized}}$

### Compilation

The scalar-only (turn off auto-vectorization & unrolling) version is compiled using: `g++ -O0 -fno-tree-vectorize -o outputfile program.cpp`

The auto-vectorized is compiled using: ` g++ -O3 -march=native -ffast-math -fopenmp -o benchmark_vec benchmark.cpp`

When the files are run they're pinned to a CPU core so ensure no variability. After the results are collected, the data plotted using a Python script.

## Test 2: Alignment and Tail Handling
This program is designed to study the performance of vectorized kernels under different memory alignment and tail-handling conditions.

The code allocates memory blocks aligned to a specified boundary (default: 64 bytes). This ensures that data arrays are placed on cache-line and SIMD-friendly boundaries, which is crucial for testing alignment effects.

The `main` function sets up test sizes that include both aligned multiples of cache-line-friendly sizes (e.g., 1024, 2048, 8192) and non-multiples that leave a remainder or “tail” (e.g., 1023, 2047, 8191). Arrays are allocated slightly larger than needed (n+16) to allow for pointer shifts when simulating misaligned access.

```c++
vector<size_t> sizes = {512, 1024, 1500, 2000, 4096, 6000, 8192};

float* x_aligned = x.get();
float* x_misaligned = x.get() + 1; // shift by 1 element
```

The runtime recording, repetitions for reliable data, and output is the same as Test #1.  

## Test 3: Stride and Gather Effects
This program benchmarks stride-based and gather-based SAXPY kernels. Stride tests explore how non-unit strides reduce SIMD efficiency, while gather tests simulate irregular memory access patterns.

The program defines two kernel variants of SAXPY:
1. Stride Kernel: Processes elements with a fixed stride (e.g., 1, 2, 4,…).
2. Gather Kernel: Accesses elements indirectly via an index array, simulating irregular memory access.

```
void saxpy_stride(float a, const float* x, float* y, size_t n, size_t stride) {
    for (size_t i = 0; i < n; i += stride) y[i] = a * x[i] + y[i];
}

void saxpy_gather(float a, const float* x, float* y, const int* idx, size_t n) {
    for (size_t i = 0; i < n; ++i) y[idx[i]] = a * x[idx[i]] + y[idx[i]];
}
```
For each trial the program runs stride benchmarks for multiple stride values, and runs a gather benchmark using the shuffled index array.

The runtime recording, repetitions for reliable data, and output is the same as Test #1.  

<p align="left">
  <img  src="https://github.com/user-attachments/assets/443d70b5-cc92-4d5f-bd58-0d189ac352d7" style="width: 70%; height: auto;">
</p>

---
## Results and Discussion

### Vectorization Verification

We know this is vectorized by the following:
<p align="left">
  <img  src="https://github.com/user-attachments/assets/4d611016-c80f-49d2-941a-2f9595d23eeb" style="width: 70%; height: auto;">
</p>

`vaddps`, and `vmulps` are both SIMD commands showing that vectorization indeed happened, but for the other compiled program without vectorization none of these commands pop up.
Another way of checking for vectorization is running with `-fopt-info-vec-optimized` to see what exactly was vectorized:
<p align="left">
  <img  src="https://github.com/user-attachments/assets/fd8dd5d2-8f6d-4862-937b-362e5f715a8e" style="width: 90%; height: auto;">
</p>

---

### Baseline (scalar) vs auto-vectorized 

<p align="center">
  <img  src="https://github.com/user-attachments/assets/96107937-d59b-4488-bf9f-31af3ad83a1e" style="width: 90%; height: auto;">
</p>

The speedup graph shows how much faster SIMD is compared to scalar execution as problem size grows. For small datasets that fit within L1 cache, SIMD achieves over 10× speedup across all three kernels, since the data is readily available and computation dominates. As the working set increases beyond L2 and L3 cache sizes, the speedup steadily declines to around 3–4×. This drop indicates a shift from compute-bound to memory-bound behavior—SIMD can only accelerate arithmetic operations, but once memory access becomes the bottleneck, its relative advantage diminishes.

---

### Runtime vs Data Set Size

| Scalar     | Vectorized | 
|----------------|-----------------|
|![image](https://github.com/user-attachments/assets/51f1c645-8751-47f9-b326-e2db49fceaac)| ![image](https://github.com/user-attachments/assets/6909c590-a237-4126-a3c7-07215fc58d08)|

The runtime graphs show that both scalar (NoVec) and vectorized (Vec) executions scale linearly with problem size, but SIMD achieves much lower runtimes—often an order of magnitude faster—when the data fits in cache. For small sizes, vectorized kernels clearly outperform scalar ones, but as the working set exceeds L2 and L3 caches, the gap narrows since memory bandwidth dominates performance. Among the kernels, Elementwise tends to rise more steeply at larger sizes, while SAXPY and Stencil maintain relatively closer performance. Overall, vectorization drastically reduces runtime for compute-bound, cache-resident workloads, but its advantage diminishes once the problem size becomes memory-bound.

---

### Locality sweep in GFLOP/s and CPE

| Scalar     | Vectorized | 
|----------------|-----------------|
|![image](https://github.com/user-attachments/assets/5d93a7f0-9491-4ead-b6a4-dc9d9a023723)| ![image](https://github.com/user-attachments/assets/aa01114c-c83e-4a96-92e6-84f121654fed)|

The GFLOP/s graph highlights absolute throughput differences between scalar and vectorized versions. SIMD versions consistently achieve much higher GFLOP/s, peaking around 18 for SAXPY when data fits in cache. However, as problem size increases, SIMD performance falls off sharply due to memory bandwidth limitations, converging toward scalar performance levels. In contrast, scalar curves remain relatively flat because they are already limited by execution throughput rather than memory. This contrast shows that SIMD boosts peak compute performance significantly, but memory constraints eventually dominate both scalar and vectorized execution at large problem sizes.

CPE is calculated as follows: $\frac{\text{Time(ns)} \times 2.496011 (\text{CPU Freq)}}{N}$

<p align="center">
  <img  src="https://github.com/user-attachments/assets/fc61e668-7f65-4b33-b106-d6c618adb8ff" style="width: 60%; height: auto;">
</p>

The above results show a clear locality-dependent trend. In the L1 cache regime (≈384 KiB), SIMD vectorization provides the greatest reduction in CPE, as the data used resides close to the core and vector units can operate at near-peak throughput. As the working set extends into the L2 and L3 cache regions (≈10 MiB and 18 MiB), memory access latency begins to dominate, and the relative SIMD advantage compresses because the vector pipelines are not continuously fed with data. Once the working set exceeds the last-level cache and becomes DRAM-resident, scalar and SIMD CPE values flatten out, showing that main memory bandwidth, not computing throughput, is the bottleneck. This observation matches the theoretical expectation of the roofline performance model: in the compute-bound region SIMD yields acceleration, but as arithmetic intensity decreases and working sets overflow the caches, performance is limited by memory bandwidth, reducing the attainable SIMD speedup.

---

### Alignment and Tail Handling

<p align="center">
  <img  src="https://github.com/user-attachments/assets/8df2e670-f90f-4073-8bd1-699ea9d31e12" style="width: 60%; height: auto;">
</p>

---

### Stride/gather effects

<p align="center">
  <img  src="https://github.com/user-attachments/assets/1b844f3a-0628-4786-a2a5-4acc2bc3e6bb" style="width: 60%; height: auto;">
</p>

From the stride and gather experiments, we see that unit stride (Stride=1) achieves the highest performance at about 4.3 GFLOP/s. As the stride increases, throughput steadily falls: Stride=2 and 4 still manage above 3.8 GFLOP/s, but Stride=8 drops to around 2.5 GFLOP/s, and Stride=16 falls near 1.2 GFLOP/s. At Stride=32, efficiency collapses further to below 1.0 GFLOP/s, an almost 80% slowdown compared to unit stride. The gather pattern performs similarly poorly (~1.1 GFLOP/s), since random or indirect indexing defeats SIMD’s ability to use cache lines efficiently and prevents hardware prefetchers from streaming data. In short, SIMD efficiency is strongly tied to contiguous access — non-unit stride and gather-like patterns waste bandwidth and significantly reduce vector throughput.

---

### Float32 vs Float64
<p align="center">
  <img  src="https://github.com/user-attachments/assets/a343205d-a2ba-4802-bca6-4f84c963e8fc" style="width: 80%; height: auto;">
</p>

Float32 consistently outperforms float64 across all kernels because SIMD vector registers can fit twice as many 32-bit floats as 64-bit doubles (e.g., 8 lanes vs 4 lanes with AVX2, 16 vs 8 lanes with AVX-512). At small problem sizes, both of them achieve high GFLOPs since the entire dataset fits in cache, so memory is not a bottleneck. But as the problem size grows beyond cache capacity, performance drops, especially for float64, because larger size stresses memory bandwidth more heavily. The gap between float32 and float64 aligns with expected lane-width reasoning: float32 has roughly 2× throughput advantage in vectorized compute, though memory effects and kernel arithmetic intensity slightly blur the ratio.

## Roofline Model

<p align="center">
  <img  src="https://github.com/user-attachments/assets/58b4594e-8855-4801-89c8-84a71ac8759d" style="width: 80%; height: auto;">
</p>

## Appendix
Screenshot A1. _Optimizers enabled on GCC_
<p align="left">
  <img  src="https://github.com/user-attachments/assets/b56997a3-ca74-4925-9b71-0307a463eb50" style="width: 40%; height: auto;">
</p>
