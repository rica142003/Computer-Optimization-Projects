# Cache & Memory Performance Profiling

## Setup

CPU is pinned to its maximum frequency at 4.7GHz. 

Cache ??? is as follows:
```
> lscpu | grep -i 'cache'
L1d cache:                            448 KiB (12 instances)
L1i cache:                            640 KiB (12 instances)
L2 cache:                             9 MiB (6 instances)
L3 cache:                             18 MiB (1 instance)
```

## Baseline

Working set sizes are set to be just larger than each cache level. This benchmark ensures that accesses spill over to the next level.

### Isolating Single-Access Latency

Pointer-chasing is implemented to measure true single-access latency. Instead of streaming sequentially, memory accesses are arranged in a randomized ring where each access depends on the result of the previous one. This ensures that the CPU cannot prefetch subsequent addresses, no memory-level parallelism (MLP) can hide latency, and each access time reflects the raw cost of a cache hit or miss. This is shown below:
```
    for (size_t i = 0; i < iters; i++) {
        p = ring[p];   // next access depends on previous
        asm volatile("" :: "r"(p) : "memory"); // prevent reordering
    }
```
To avoid compiler optimizations, inline assembly barriers (`asm volatile(""::"r"(p):"memory")`) and volatile sinks are used.

### Latency Calculation
Timing is measured using the `__rdtscp` instruction, which provides cycle-accurate counters and serializes execution with respect to memory operations. The nanosecond values are derived by dividing cycles by the CPU’s fixed frequency: $\text{Latency (ns)} = \text{Cycles} / f_{GHz}$

### Compilation

The program is compiled using the following flags: `-03 -march=native -fno-tree-vectorize -fno-unroll-loops -fno-peel-loops -fno-prefetch-loop-arrays -fno-builtin`. This ensures that there is no vectorization so we can truly see the latency results.

To ensure no run-to-run variability, and memory is allocated locally, the program is run using `numactl` (prevents from moving between cores). This is as follows: `numactl --cpunodebind=0 --membind=0 ./baseline`. `--cpunodebind=0` pins the process to NUMA node 0’s CPUs, and `--membind=0` forces all allocations (malloc, new, std::vector) to come from NUMA node 0 memory.
This ensures that latency results reflect local L1/L2/L3/DRAM only.

## Pattern and Granularity Sweep

## Read/Write Mix Sweep

## Results

### Baseline

| Level | Footprint_KiB | Access     | Latency_ns | Latency_cycles |
|-------|---------------|------------|------------|----------------|
| L1    | 320.0         | read       | 1.063830   | 5.000000       |
| L1    | 320.0         | write(RFO) | 2.553191   | 12.000000      |
| L2    | 1536.0        | read       | 3.191489   | 15.000000      |
| L2    | 1536.0        | write(RFO) | 4.255319   | 20.000000      |
| L3    | 12288.0       | read       | 8.297872   | 39.000000      |
| L3    | 12288.0       | write(RFO) | 13.617021  | 64.000000      |
| DRAM  | 262144.0      | read       | 48.723404  | 229.000000     |
| DRAM  | 262144.0      | write(RFO) | 50.212766  | 236.000000     |


### Pattern and Granularity Sweep
| Pattern | Stride (bytes) | Latency (ns) | Latency (cycles @ 4.7 GHz) | Bandwidth (GB/s) |
|---------|----------------|--------------|----------------------------|------------------|
| Sequential (stride=1) | 4              | 0.363631         | 1.70906                       | 20.4894 |
| Stride 64B | 64              | 6.29428         | 29.5831                       | 1.18371 |
| Stride 256B | 256              | 15.2712         | 71.7747                       | 0.487884 |
| Stride 1024B | 1024              | 18.8521         | 88.6048                       | 0.395213 |
| Random  | N/A            | 121.11         | 569.218                       | N/A |

### Read/Write mix sweep 


