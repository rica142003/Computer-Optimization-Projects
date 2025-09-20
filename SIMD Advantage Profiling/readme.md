# SIMD Advantage Profiling

## Introduction

## Tools and Setup
To ensure run-to-run variance, the CPU frequency is fixed. Using `lscpu | grep "MHz"` the CPU frequency was found to be 2496.011MHz. 
To pin a program to a core, `lscpu -e` was used to check the number of cores and threads on each core, the following in seen:
<p align="left">
  <img  src="https://github.com/user-attachments/assets/2dc35ec7-51fa-43db-a969-e68d54810a86" style="width: 30%; height: auto;">
</p>
From the above (and running `lscpu | grep Thread`) we know that SMT is on as there's 2 threads running per core.
To pin to the first thread of core 1 each of the files is run with taskset `-c 2 ./program`. 

GCC version 9.4.0 is used in a Linux WSL (Ubuntu 20.04.2) to compile C++ code. For the specific optimizers enabled check Appendix A. When compiling `-march=native` is set which means it enables all SIMD instructions the CPU supports. To check for the specific ISAs, fast math options, and FTZ/DAZ settings, a simple program is run with vectorization enabled with `-###` added to the compile.
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

## Appendix
Screenshot A1. _Optimizers enabled on GCC_
<p align="left">
  <img  src="https://github.com/user-attachments/assets/b56997a3-ca74-4925-9b71-0307a463eb50" style="width: 40%; height: auto;">
</p>
