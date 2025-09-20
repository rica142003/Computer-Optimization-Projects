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

    SAXPY is streaming muliply and add, it has 1 multiply and 1 add, which makes it 2 FLOPs/element. When writing the function (as shown below) `__restrict` is an important part of this function as this enables no aliasing which is important when testing SIMD/vectorization because if two pointers might alias (point to the same memory), the compiler cannot safely reorder or vectorize certain operations.
```c++
static void saxpy(f32 a, const f32* __restrict x, f32* __restrict y, size_t n) {
    for (size_t i=0;i<n;i++) y[i] = a*x[i] + y[i];
}
```

2. **Dot Product / reduction**

    This kernel also has 1 add and 1 multiply, which makes it 2 FLOPs/element. Dot product is implemented as:
```c++
static f32 dot(const f32* __restrict x, const f32* __restrict y, size_t n) {
    f64 acc = 0.0; // widen to reduce Floating Point error
    for (size_t i=0;i<n;i++) acc += (f64)x[i]*y[i];
    return (f32)acc;
}
```

3. **1D 3-point Stencil**

    This kernel has 3 multiplys and 2 adds, which gives 5 FLOPs/element. It's implemented as:
```c++
static void stencil3(f32 a, f32 b, f32 c, const f32* __restrict x, f32* __restrict out, size_t n) {
    if (n<3) return;
    out[0] = x[0];
    for (size_t i=1;i<n-1;i++) {
        out[i] = a*x[i-1] + b*x[i] + c*x[i+1];
    }
    out[n-1] = x[n-1];
}
```
---
### Working-Set Size


## Appendix
Screenshot A1. _Optimizers enabled on GCC_
<p align="left">
  <img  src="https://github.com/user-attachments/assets/b56997a3-ca74-4925-9b71-0307a463eb50" style="width: 40%; height: auto;">
</p>
