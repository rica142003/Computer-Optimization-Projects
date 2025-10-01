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
- [Anomalies and Limitations](#anomalies-and-limitations)
- [Conclusion](#conclusion)
- [Appendix](#appendix)


## Introduction

The goal of this project is to measure the speedup from SIMD vectorization on basic numeric kernels. SIMD runs several data operations in one instruction. The benefit depends on compute limits, memory hierarchy, and access patterns.

The experiments compare scalar and SIMD runs. They test alignment, tail handling, stride, gather access, and data type size. Results include timing, GFLOP/s, and cycles per element (CPE). A roofline model is also used.

The study shows when SIMD gives large gains and when the effect is reduced. This happens when memory or access patterns limit performance. The report provides a clear view of SIMD behavior under single-threaded conditions.

## Tools and Setup

- Compiler: GCC version 9.4.0
- ISA support: AVX, AVX2, FMA (no AVX-512, see Appendix), fastmath enabled
- CPU: Intel i7-1260P, SIMD width = 256-bit (8×f32, 4×f64 per vector)  
- Frequency: pinned at 2.496 GHz  
- Pinning: tasks pinned to physical core using `taskset -c 2`  (pin to the first thread of core 1)
- Flags:  
  - Scalar build: `-O0 -fno-tree-vectorize`  
  - Vectorized build: `-O3 -march=native -ffast-math -fopenmp`  
- Measurement: `std::chrono::high_resolution_clock` (median of ≥100 iterations, warm-up included)  
- Trials: ≥5 per data point, plotted with error bars

---

### Kernels and Flop Counts
1. SAXPY / AXPY

   The first kernel is SAXPY (Single-Precision A·X Plus Y). The operation is `y[i] = a * x[i] + y[i]`. Each step does one multiply and one add. This equals 2 FLOPs per element. The kernel reads from x, updates y, and writes back to y. The arithmetic intensity is low, so memory bandwidth strongly affects performance.
   
```c++
void saxpy(float a, const float* x, float* y, size_t n) {
    for (size_t i = 0; i < n; ++i) {
        y[i] = a * x[i] + y[i];
    }
}
```

2. Elementwise multiply

   The second kernel is elementwise multiply. It computes `c[i] = a[i] * b[i]`. Each step does one multiply, or 1 FLOP per element. The kernel moves two input vectors and one output vector for each result. This gives a lower FLOP-to-memory ratio than SAXPY. As a result, performance is more memory-bound.

```c++
void elementwise_mult(const float* a, const float* b, float* c, size_t n) {
    #pragma omp simd
    for (size_t i = 0; i < n; ++i) {
        c[i] = a[i] * b[i];
    }
}
```

3. 1D 3-point Stencil

   The third kernel is a 1D 3-point stencil. Each output is the sum of the left neighbor, the current element, and the right neighbor: `out[i] = in[i-1] + in[i] + in[i+1]`. This gives 2 FLOPs per element (two adds).

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

The first step is a warmup. The kernel runs 50 times before recording data. This keeps CPU frequency stable and fills instruction and data caches.

After warmup, the program enters the measurement loop. A timestamp is taken right before the kernel starts and another right after it ends. Timing uses std::chrono::high_resolution_clock, which gives nanosecond precision.

Each kernel is measured at least 100 times. The total run time is also required to be longer than one second. These rules reduce noise.

All timings are sorted, and the median is taken. The median avoids distortion from outliers. Performance in GFLOP/s is then calculated as:

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

Each kernel and size is tested in 5 trials. This gives a small dataset that can be averaged and used to calculate standard deviation. Error bars are then added to plots.

Results are stored in a .csv file. Speedup is calculated as: $\frac{T_{scalar}}{T_{vectorized}}$

### Compilation

The scalar-only (turn off auto-vectorization & unrolling) version is compiled using: `g++ -O0 -fno-tree-vectorize -o outputfile program.cpp`

The auto-vectorized is compiled using: ` g++ -O3 -march=native -ffast-math -fopenmp -o benchmark_vec benchmark.cpp`

Runs are pinned to one CPU core to reduce variability. A Python script plots the results after data collection.

## Test 2: Alignment and Tail Handling

This test studies performance under aligned and misaligned memory conditions. Memory is allocated at 64-byte boundaries so arrays are aligned with cache lines.

The program uses both exact multiples (e.g., 1024, 2048, 8192) and near multiples with a remainder, called “tail” cases (e.g., 1023, 2047, 8191). Arrays are allocated slightly larger (n+16) so the pointer can be shifted to simulate misalignment.

```c++
vector<size_t> sizes = {512, 1024, 1500, 2000, 4096, 6000, 8192};

float* x_aligned = x.get();
float* x_misaligned = x.get() + 1; // shift by 1 element
```

The runtime recording, repetitions for reliable data, and output is the same as Test #1.  

## Test 3: Stride and Gather Effects

This test measures performance of SAXPY with different memory access patterns. Stride tests use fixed spacing between elements. Gather tests use an index array to pick elements in irregular order.

Two kernel versions are used:
- Stride Kernel – processes every element with a step size (1, 2, 4, …).
- Gather Kernel – loads elements from positions given by an index array.

```
void saxpy_stride(float a, const float* x, float* y, size_t n, size_t stride) {
    for (size_t i = 0; i < n; i += stride) y[i] = a * x[i] + y[i];
}

void saxpy_gather(float a, const float* x, float* y, const int* idx, size_t n) {
    for (size_t i = 0; i < n; ++i) y[idx[i]] = a * x[idx[i]] + y[idx[i]];
}
```
The figure shows how stride and gather work. With stride-1, SIMD loads consecutive elements (best case). With stride-2, every other element is skipped, lowering efficiency. The gather kernel uses scattered indices, which forces SIMD to fetch data from random places in memory.

<p align="left">
  <img  src="https://github.com/user-attachments/assets/443d70b5-cc92-4d5f-bd58-0d189ac352d7" style="width: 50%; height: auto;">
</p>

Runtime recording, repetitions, and output collection follow the same method as Test #1.****

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

The graph shows SIMD speedup compared to scalar execution. For small problem sizes inside L1 cache, all three kernels reach over 10× speedup. Data is close to the CPU, so computation dominates.

As the size grows past L2 and L3 caches, the speedup drops. By the largest sizes, the speedup is only about 3–4×. This shows the kernels moving from compute-bound to memory-bound. SIMD helps arithmetic, but cannot fix the memory bottleneck. The trend is seen that larger data reduces SIMD gains because memory access becomes the main cost.

---

### Runtime vs Data Set Size

| Scalar     | Vectorized | 
|----------------|-----------------|
|![image](https://github.com/user-attachments/assets/51f1c645-8751-47f9-b326-e2db49fceaac)| ![image](https://github.com/user-attachments/assets/6909c590-a237-4126-a3c7-07215fc58d08)|

The runtime graphs compare scalar (NoVec) and vectorized (Vec) execution. Both scale almost linearly with problem size. SIMD runs are much faster, especially when the data fits in cache. For small workloads, vectorized kernels are about an order of magnitude faster.

As the data grows past L2 and L3 cache, runtimes for both versions increase at a similar rate. The gap between scalar and SIMD becomes smaller because memory bandwidth limits performance.

Among the kernels, Elementwise runtime rises more steeply at large sizes. SAXPY and Stencil stay closer to each other. This shows that Elementwise is more memory-bound, while the others maintain better efficiency.

Overall, vectorization cuts runtime greatly for compute-bound, cache-resident cases. The benefit drops once memory access becomes the main bottleneck.

---

### Locality sweep in GFLOP/s and CPE

| Scalar     | Vectorized | 
|----------------|-----------------|
|![image](https://github.com/user-attachments/assets/5d93a7f0-9491-4ead-b6a4-dc9d9a023723)| ![image](https://github.com/user-attachments/assets/aa01114c-c83e-4a96-92e6-84f121654fed)|

The GFLOP/s graphs show how throughput changes for scalar and SIMD runs. SIMD versions reach much higher peak performance, with SAXPY hitting about 18 GFLOP/s when the data fits in L1 cache. Elementwise and Stencil also improve, but at lower peaks.

As problem size grows past L2 and L3 cache, SIMD throughput falls sharply. The values converge toward scalar performance, since memory bandwidth limits execution. Scalar curves are flatter because they are already bound by instruction throughput. This shows SIMD can unlock peak compute power, but its advantage shrinks once memory becomes the bottleneck.

CPE is calculated as follows: $\frac{\text{Time(ns)} \times 2.496011 (\text{CPU Freq)}}{N}$

<p align="center">
  <img  src="https://github.com/user-attachments/assets/fc61e668-7f65-4b33-b106-d6c618adb8ff" style="width: 60%; height: auto;">
</p>

The CPE graph shows clear cache-dependent behavior.
- In the L1 region (~384 KiB), SIMD greatly lowers CPE, since data is close to the core and vector units run at near peak.
- In the L2 (~10 MiB) and L3 (~18 MiB) regions, memory latency slows access. SIMD advantage decreases because the vector pipelines cannot be kept full.
- Once data spills to DRAM, both scalar and SIMD curves flatten. Main memory bandwidth, not compute, is the bottleneck.

  
---

### Alignment and Tail Handling

<p align="center">
  <img  src="https://github.com/user-attachments/assets/8df2e670-f90f-4073-8bd1-699ea9d31e12" style="width: 60%; height: auto;">
</p>

The runtime graph compares aligned and misaligned arrays. For small sizes that fit in cache, the difference is very small. At larger sizes, alignment gives about 10–30% faster runtimes. The slowdown in misaligned cases comes from two effects:
1. Unaligned loads, which require extra cycles.
2. Tail handling overhead, where leftover elements must be processed outside the main SIMD loop.

These penalties grow with problem size. The results show that alignment and padding are important to reach peak SIMD performance.

---

### Stride/gather effects

<p align="center">
  <img  src="https://github.com/user-attachments/assets/1b844f3a-0628-4786-a2a5-4acc2bc3e6bb" style="width: 60%; height: auto;">
</p>

The stride test shows that contiguous access (stride=1) gives the best performance, about 4.3 GFLOP/s. As the stride increases, throughput drops. Stride=2 and 4 remain near 3.8 GFLOP/s, but Stride=8 falls to ~2.5 GFLOP/s. At Stride=16 performance drops to ~1.2 GFLOP/s, and by Stride=32 it is below 1.0 GFLOP/s, an 80% slowdown compared to stride=1.

The gather test performs similarly poorly, around 1.1 GFLOP/s. Random or indirect access prevents SIMD from using cache lines efficiently. Prefetchers cannot stream data, so memory stalls dominate.

These results confirm that SIMD efficiency depends on contiguous memory access. Non-unit strides and gather patterns waste bandwidth and sharply reduce throughput.

---

### Float32 vs Float64
<p align="center">
  <img  src="https://github.com/user-attachments/assets/a343205d-a2ba-4802-bca6-4f84c963e8fc" style="width: 80%; height: auto;">
</p>

The results show that float32 runs faster than float64 across all kernels. SIMD registers hold twice as many 32-bit floats as 64-bit doubles (e.g., 8 vs 4 lanes with AVX2). This gives float32 about 2× higher compute throughput.

For small problem sizes, both float32 and float64 achieve high GFLOP/s because the data fits in cache. Once the working set grows beyond cache, performance falls, with float64 dropping more quickly. This happens because doubles take more space and stress memory bandwidth harder.

The gap between float32 and float64 matches lane-width expectations. Float32 is more efficient for SIMD, while float64 is more limited by memory and register capacity.

---

## Roofline Model

The roofline model shows how kernel performance compares to hardware limits. The y-axis is performance (GFLOP/s). The x-axis is arithmetic intensity (FLOPs per byte). Two ceilings define the limits:

1. Sloped roof (bandwidth limit)
   This line is set by memory bandwidth.
   This line shows the maximum performance possible if the kernel is limited by memory bandwidth. It is calculated as:
   \[
   P = \text{BW} \times \text{AI}
   \]
   An effective bandwidth of ~114.6 GB/s was used. This value includes cache effects, which give higher bandwidth than DRAM alone.

3. Flat roof (compute limit)
   This is the CPU’s peak floating-point rate. With two 256-bit AVX2 FMA units at 2.496 GHz, the limit is about 80 GFLOP/s per core. Kernels cannot exceed this ceiling.

### Placement of points

Each kernel is plotted at its arithmetic intensity and achieved performance.  
- SAXPY has the highest arithmetic intensity (~0.167 FLOPs/B), so its points appear furthest to the right.  
- Stencil (~0.125 FLOPs/B) lies in the middle.  
- Elementwise multiply (~0.083 FLOPs/B) has the lowest intensity, so its points are furthest left.  

Within each kernel, SIMD points appear higher than scalar points at the same AI, reflecting the benefit of vectorization when the workload is cache-resident. However, once the problem size grows and memory bandwidth becomes the bottleneck, SIMD advantages compress and both scalar and vectorized points converge toward the same bandwidth-defined slope.

### Interpretation

Kernels with higher arithmetic intensity reach higher performance under the same bandwidth limit, which is why SAXPY performs best. Points high on the y-axis come from cache-resident runs (L1/L2), where effective bandwidth is large and performance is close to the compute roof. At large problem sizes, data spills to DRAM. All kernels flatten against the sloped roof, showing they are memory-bound. The roofline confirms that these kernels do not reach the compute peak. Instead, they are dominated by memory. SIMD provides strong speedup when data is in cache, but large-scale performance is limited by arithmetic intensity and bandwidth.

<p align="center">
  <img  src="https://github.com/user-attachments/assets/d0bf722b-9c73-4006-a534-0eea1bd5d84d" style="width: 70%; height: auto;">
</p> 


---

## Anomalies and Limitations

Some results did not match theory exactly. In several runs, scalar and SIMD runtimes converged sooner than expected once the data passed the last-level cache. This likely came from background noise, SMT sharing, or imperfect core pinning even with taskset.

At very large sizes, only a few repetitions were possible. Longer runtimes increased variance and made error bars wider.

For alignment and tail handling, the size of penalties varied across kernels. This is likely due to compiler differences in how prologue and epilogue loops were generated.

Prefetcher behavior and cache replacement also caused irregular GFLOP/s plateaus. These effects point to low-level microarchitecture features outside the scope of the tests.

Overall, the results show that isolating SIMD effects is complex. Hardware speculation, frequency scaling, and memory system behavior all add noise to the measurements.

---

## Conclusion

This project shows that SIMD gives large speedups for compute-bound workloads, with over 10× gains when data fits in cache. The advantage drops as problem size grows, since memory bandwidth becomes the main limit once caches are full.

Alignment and tail handling add 10–30% slowdown at large sizes. Stride and gather patterns perform much worse, as they waste cache lines and reduce efficiency.

Data type tests follow lane-width expectations: float32 runs about twice as fast as float64. Roofline analysis confirms the shift from compute-bound to memory-bound behavior.

Overall, SIMD performance depends on data locality, access patterns, and alignment. The results highlight both the strong benefits and the clear limits of vectorization on modern CPUs.

## Appendix
Screenshot A1. _Optimizers enabled on GCC_
<p align="left">
  <img  src="https://github.com/user-attachments/assets/b56997a3-ca74-4925-9b71-0307a463eb50" style="width: 40%; height: auto;">
</p>

Screenshot A2. _Checking for specific ISAs_

To check for the specific ISAs, fast math options, and FTZ/DAZ settings, a simple program is run with vectorization enabled with `-###` added to the compile. The following is seen:
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

