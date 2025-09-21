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
### Working-Set Size
The size of the cache on my computer is as follows:
<p align="left">
  <img  src="https://github.com/user-attachments/assets/d72c7bd2-2e66-4d7b-b168-de6df3e5efc5" style="width: 50%; height: auto;">
</p>

---
### Timing Measurement

---
## Tests
### Baseline (scalar) vs autovectorized

Compiling scalar-only (turn off auto-vectorization & unrolling): `g++ -O0 -fno-tree-vectorize -o outputfile program.cpp`

Compiling auto-vectorized: ` g++ -O3 -march=native -ffast-math -fopenmp -o benchmark_vec benchmark.cpp`



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

The above results reveal a clear locality-dependent trend. In the L1 cache regime (≈384 KiB), SIMD vectorization provides the greatest reduction in CPE, as the data used resides close to the core and vector units can operate at near-peak throughput. As the working set extends into the L2 and L3 cache regions (≈10 MiB and 18 MiB), memory access latency begins to dominate, and the relative SIMD advantage compresses because the vector pipelines are not continuously fed with data. Once the working set exceeds the last-level cache and becomes DRAM-resident, scalar and SIMD CPE values flatten out, showing that main memory bandwidth, not computing throughput, is the bottleneck. This observation matches the theoretical expectation of the roofline performance model: in the compute-bound region SIMD yields acceleration, but as arithmetic intensity decreases and working sets overflow the caches, performance is limited by memory bandwidth, reducing the attainable SIMD speedup.

---

### Alignment and Tail Handling

When the data is stored in memory in a way that matches the CPU’s vector width (aligned and in clean multiples), the processor can load and process chunks very efficiently. But if the data is shifted by even one element (misaligned), the CPU often needs extra instructions to fetch it, which slows things down. Similarly, if the number of elements isn’t a neat multiple of the vector width, the last few “leftover” elements (the tail) must be handled separately with slower scalar code. The result is that aligned, multiple-of-vector-size arrays run fastest, while misaligned or tail cases show noticeably lower performance.

<p align="center">
  <img  src="https://github.com/user-attachments/assets/c2a2362c-a51f-423a-afa7-22c1b82a7220" style="width: 60%; height: auto;">
</p>

This graph shows how memory alignment and leftover “tail” elements affect SIMD performance. For every problem size, the aligned arrays (blue) run faster than the misaligned arrays (orange). For example, at size 1024 the aligned case reaches about 18.1 GFLOP/s, while the misaligned case drops to about 16.2 GFLOP/s — roughly a 10% slowdown. At 2048 elements, the drop is similar (≈21.1 vs 19.5 GFLOP/s). When the size is not a multiple of the SIMD vector width (like 1023 or 2047), throughput falls further because the CPU has to handle the leftover “tail” with slower scalar or masked instructions. This quantified gap — about 5–15% lower performance for misalignment and extra loss for tail sizes — demonstrates that SIMD is most efficient with aligned data and problem sizes that divide evenly into the vector width.

---

### Stride/gather effects

Stride and gather effects describe how the pattern of memory access impacts SIMD efficiency. Stride means skipping elements when reading from memory, such as using every 2nd, 4th, or 8th value instead of accessing data contiguously. While SIMD instructions work best on long, continuous blocks of data, large strides reduce cache-line utilization (you load 64 bytes but only use a few of them) and confuse the hardware prefetcher, so performance drops. Gather refers to using an index array to fetch elements from scattered, non-contiguous locations in memory. This breaks the streaming nature of SIMD, forcing the processor to assemble data piece by piece. Both stride and gather create overhead because the CPU can’t fully exploit vector lanes or memory bandwidth, leading to much lower throughput compared to unit-stride contiguous access.

<p align="center">
  <img  src="https://github.com/user-attachments/assets/f7e5510b-2c6d-4201-9f7a-71388ebdb534" style="width: 60%; height: auto;">
</p>

From the stride and gather experiments, we see that unit stride (Stride=1) achieves the highest performance at about 4.3 GFLOP/s. As the stride increases, throughput steadily falls: Stride=2 and 4 still manage above 3.8 GFLOP/s, but Stride=8 drops to around 2.5 GFLOP/s, and Stride=16 falls near 1.2 GFLOP/s. At Stride=32, efficiency collapses further to below 1.0 GFLOP/s, an almost 80% slowdown compared to unit stride. The gather pattern performs similarly poorly (~1.1 GFLOP/s), since random or indirect indexing defeats SIMD’s ability to use cache lines efficiently and prevents hardware prefetchers from streaming data. In short, SIMD efficiency is strongly tied to contiguous access — non-unit stride and gather-like patterns waste bandwidth and significantly reduce vector throughput.

## Appendix
Screenshot A1. _Optimizers enabled on GCC_
<p align="left">
  <img  src="https://github.com/user-attachments/assets/b56997a3-ca74-4925-9b71-0307a463eb50" style="width: 40%; height: auto;">
</p>
