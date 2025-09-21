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

<img width="1980" height="1180" alt="image" src="https://github.com/user-attachments/assets/af79d916-5bdf-4895-9289-7991075c51ee" />
<img width="1980" height="1180" alt="image" src="https://github.com/user-attachments/assets/96107937-d59b-4488-bf9f-31af3ad83a1e" />
<img width="1697" height="1103" alt="image" src="https://github.com/user-attachments/assets/5d93a7f0-9491-4ead-b6a4-dc9d9a023723" />

<img width="1718" height="1103" alt="image" src="https://github.com/user-attachments/assets/aa01114c-c83e-4a96-92e6-84f121654fed" />


## Appendix
Screenshot A1. _Optimizers enabled on GCC_
<p align="left">
  <img  src="https://github.com/user-attachments/assets/b56997a3-ca74-4925-9b71-0307a463eb50" style="width: 40%; height: auto;">
</p>
