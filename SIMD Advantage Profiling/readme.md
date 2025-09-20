# SIMD Advantage Profiling

## Introduction

## Setup
To ensure run-to-run variance, the CPU frequency is fixed. Using `lscpu | grep "MHz"` the CPU frequency was found to be 2496.011MHz. 
To pin a program to a core, `lscpu -e` was used to check the number of cores and threads on each core, the following in seen:

Also from the above (and also running `lscpu | grep Thread`) we know that SMT is on as there's 2 threads running per core.
To pin to the first thread of core 1 each of the files is run with taskset `-c 2 ./program`. 

GCC version 9.4.0 is used in a Linux WSL (Ubuntu 20.04.2) to compile C++ code. 

## Appendix
Optimizers enabled on GCC
<img width="624" height="1434" alt="image" src="https://github.com/user-attachments/assets/b56997a3-ca74-4925-9b71-0307a463eb50" />
