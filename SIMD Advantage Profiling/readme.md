# SIMD Advantage Profiling

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
This shows that the CPU (11th generation Intel Core) supports up through AVX2 + FMA, but not AVX-512 (notice all `-mno-avx512*`). Fast math options are not enabled (see Appendix A). This also means FTZ/DAZ options are OFF as `-ffast-math` is disabled (general standard).

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
// --- In main(), allocate aligned arrays ---
auto x = aligned_array<float>(n+16, 64);
auto y = aligned_array<float>(n+16, 64);

// misaligned pointers (shift by one element = 4 bytes)
float* x_misaligned = x.get() + 1;
float* y_misaligned = y.get() + 1;
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

---
## Results

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

<p align="center">
  <img  src="https://github.com/user-attachments/assets/3f9f697a-8ed8-4b08-a32c-b07896b6986c" style="width: 90%; height: auto;">
</p>


---

### Runtime vs Data Set Size

| Scalar     | Vectorized | 
|----------------|-----------------|
|![image](https://github.com/user-attachments/assets/51f1c645-8751-47f9-b326-e2db49fceaac)| ![image](https://github.com/user-attachments/assets/6909c590-a237-4126-a3c7-07215fc58d08)|

---

### Locality sweep in GFLOP/s and CPE

| Scalar     | Vectorized | 
|----------------|-----------------|
|![image](https://github.com/user-attachments/assets/5d93a7f0-9491-4ead-b6a4-dc9d9a023723)| ![image](https://github.com/user-attachments/assets/aa01114c-c83e-4a96-92e6-84f121654fed)|


CPE is calculated as follows:
<p align="left">
  <img  src="https://github.com/user-attachments/assets/bf0b7b29-ff62-4959-b60f-439b6b9819f1" style="width: 30%; height: auto;">
</p>

<p align="center">
  <img  src="https://github.com/user-attachments/assets/fc61e668-7f65-4b33-b106-d6c618adb8ff" style="width: 60%; height: auto;">
</p>

The above results show a clear locality-dependent trend. In the L1 cache regime (≈384 KiB), SIMD vectorization provides the greatest reduction in CPE, as the data used resides close to the core and vector units can operate at near-peak throughput. As the working set extends into the L2 and L3 cache regions (≈10 MiB and 18 MiB), memory access latency begins to dominate, and the relative SIMD advantage compresses because the vector pipelines are not continuously fed with data. Once the working set exceeds the last-level cache and becomes DRAM-resident, scalar and SIMD CPE values flatten out, showing that main memory bandwidth, not computing throughput, is the bottleneck. This observation matches the theoretical expectation of the roofline performance model: in the compute-bound region SIMD yields acceleration, but as arithmetic intensity decreases and working sets overflow the caches, performance is limited by memory bandwidth, reducing the attainable SIMD speedup.

---

### Alignment and Tail Handling

<p align="center">
  <img  src="https://github.com/user-attachments/assets/c2a2362c-a51f-423a-afa7-22c1b82a7220" style="width: 60%; height: auto;">
</p>

This graph shows how memory alignment and leftover “tail” elements affect SIMD performance. For every problem size, the aligned arrays (blue) run faster than the misaligned arrays (orange). For example, at size 1024 the aligned case reaches about 18.1 GFLOP/s, while the misaligned case drops to about 16.2 GFLOP/s — roughly a 10% slowdown. At 2048 elements, the drop is similar (≈21.1 vs 19.5 GFLOP/s). When the size is not a multiple of the SIMD vector width (like 1023 or 2047), throughput falls further because the CPU has to handle the leftover “tail” with slower scalar or masked instructions. This quantified gap — about 5–15% lower performance for misalignment and extra loss for tail sizes — demonstrates that SIMD is most efficient with aligned data and problem sizes that divide evenly into the vector width.

---

### Stride/gather effects

<p align="center">
  <img  src="https://github.com/user-attachments/assets/f7e5510b-2c6d-4201-9f7a-71388ebdb534" style="width: 60%; height: auto;">
</p>

From the stride and gather experiments, we see that unit stride (Stride=1) achieves the highest performance at about 4.3 GFLOP/s. As the stride increases, throughput steadily falls: Stride=2 and 4 still manage above 3.8 GFLOP/s, but Stride=8 drops to around 2.5 GFLOP/s, and Stride=16 falls near 1.2 GFLOP/s. At Stride=32, efficiency collapses further to below 1.0 GFLOP/s, an almost 80% slowdown compared to unit stride. The gather pattern performs similarly poorly (~1.1 GFLOP/s), since random or indirect indexing defeats SIMD’s ability to use cache lines efficiently and prevents hardware prefetchers from streaming data. In short, SIMD efficiency is strongly tied to contiguous access — non-unit stride and gather-like patterns waste bandwidth and significantly reduce vector throughput.

## Appendix
Screenshot A1. _Optimizers enabled on GCC_
<p align="left">
  <img  src="https://github.com/user-attachments/assets/b56997a3-ca74-4925-9b71-0307a463eb50" style="width: 40%; height: auto;">
</p>
