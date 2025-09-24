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
```c++
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

## Intensity Sweep 

Intel Memory Latency Checker (v3.11b) with `--loaded_latency` at varying thread intensities (`-t1`, `-t4`, `-t8`) to measure the throughput–latency tradeoff. 
```
> mlc --loaded_latency -t4
Intel(R) Memory Latency Checker - v3.11b
Command line parameters: --loaded_latency -t4 

Using buffer size of 183.105MiB/thread for reads and an additional 183.105MiB/thread for writes
*** Unable to modify prefetchers (try executing 'modprobe msr')
*** So, enabling random access for latency measurements

Measuring Loaded Latencies for the system
Using all the threads from each core if Hyper-threading is enabled
Using Read-only traffic type
Inject	Latency	Bandwidth
Delay	(ns)	MB/sec
==========================
 00000	189.66	  55445.5
 00002	187.54	  55398.7
 00008	187.47	  55511.5
 00015	183.65	  54685.0
 00050	174.94	  54268.4
 00100	122.69	  36274.6
 00200	129.03	  21116.8
 00300	126.65	  14723.2
 00400	125.05	  11668.6
 00500	125.70	   9678.8
 00700	122.80	   7250.1
 01000	120.73	   5365.9
 01300	121.25	   4264.8
 01700	121.02	   3456.6
 02500	120.23	   2547.0
 03500	118.47	   1982.8
 05000	118.87	   1549.5
 09000	118.06	   1109.6
 20000	118.91	    787.3
```
From `mlc --peak_injection_bandwidth`, the theoretical peak read bandwidth was reported as:
```
> mlc --peak_injection_bandwidth | grep "ALL Reads"
ALL Reads        :	58958.4	

```

## Cache-miss impact 

A SAXPY kernel (`y[i] = a*x[i] + y[i]`) was run with varying footprints and access patterns, measuring performance with `perf`.
```
# L1-ish (tiny)
perf stat -x, -e cycles,instructions,cache-references,cache-misses,LLC-loads,LLC-load-misses ./saxpy --n 8192 --stride 1

# L2/LLC-ish (medium)
perf stat -x, -e cycles,instructions,cache-references,cache-misses,LLC-loads,LLC-load-misses ./saxpy --n 393216 --stride 1

# DRAM, prefetch-friendly
perf stat -x, -e cycles,instructions,cache-references,cache-misses,LLC-loads,LLC-load-misses ./saxpy --n 16777216 --stride 1

# DRAM, poor locality
perf stat -x, -e cycles,instructions,cache-references,cache-misses,LLC-loads,LLC-load-misses ./saxpy --n 33554432 --stride 4096

# DRAM, random
perf stat -x, -e cycles,instructions,cache-references,cache-misses,LLC-loads,LLC-load-misses ./saxpy --n 16777216 --pattern rand

```

```
> perf stat -x, -e cycles,instructions,cache-references,cache-misses,LLC-loads,LLC-load-misses ./saxpy --n 33554432 --stride 4096
# SAXPY summary
n=33554432 stride=4096 trials=3 pattern=seq alpha=1.50 huge=0
best_ms=0.263 avg_ms=0.282 checksum=3078.980179
gflops_best=0.062 gflops_avg=0.058  gibps_best=0.232 gibps_avg=0.217
CSV,n,33554432,stride,4096,pattern,seq,best_ms,0.263,avg_ms,0.282
1137157478,,cpu_atom/cycles/,11008170,1.00,,
1593334628,,cpu_core/cycles/,749710594,98.00,,
2954171974,,cpu_atom/instructions/,11008170,1.00,2.60,insn per cycle
6648162165,,cpu_core/instructions/,749710594,98.00,4.17,insn per cycle
14047165,,cpu_atom/cache-references/,11008170,1.00,,
12523492,,cpu_core/cache-references/,749710594,98.00,,
10508716,,cpu_atom/cache-misses/,11008170,1.00,74.81,of all cache refs
6839402,,cpu_core/cache-misses/,749710594,98.00,54.61,of all cache refs
455470,,cpu_atom/LLC-loads/,11008170,1.00,,
427404,,cpu_core/LLC-loads/,749710594,98.00,,
19556,,cpu_atom/LLC-load-misses/,11008170,1.00,4.29,of all LL-cache accesses
268002,,cpu_core/LLC-load-misses/,749710594,98.00,62.70,of all LL-cache accesses
```

## TLB-miss impact 
Baseline (stride=1, 4 KiB pages): Working set = 134M elements (~512 MB per array, ~1 GB total across x+y). Accesses are sequential and local.

Stress (stride=4096, 4 KiB pages): Every access jumps to a new 4 KiB page → forces frequent TLB lookups.

Huge pages (stride=524288, 2 MiB pages): Same footprint but with huge pages enabled. Each 2 MiB page covers 524,288 elements, so far fewer TLB entries needed.

This is a methodologically sound variation: same kernel, same footprint, only stride/page size changes.
```
# Baseline: stride=1 (good locality, normal pages)
perf stat -e dTLB-loads,dTLB-load-misses ./saxpy --n 33554432 --stride 1

# TLB stress: stride=4096 (4 KiB pages, each access new page)
perf stat -e dTLB-loads,dTLB-load-misses ./saxpy --n 134217728 --stride 4096

# With huge pages (2 MiB)
perf stat -e dTLB-loads,dTLB-load-misses ./saxpy --n 134217728 --stride 524288 --huge
```

```
> perf stat -e dTLB-loads,dTLB-load-misses ./saxpy --n 33554432 --stride 1
# SAXPY summary
n=33554432 stride=1 trials=3 pattern=seq alpha=1.50 huge=0
best_ms=16.371 avg_ms=16.479 checksum=7666.048620
gflops_best=4.099 gflops_avg=4.072  gibps_best=15.271 gibps_avg=15.171
CSV,n,33554432,stride,1,pattern,seq,best_ms,16.371,avg_ms,16.479

 Performance counter stats for './saxpy --n 33554432 --stride 1':

       562,632,318      cpu_atom/dTLB-loads/                                                    (1.32%)
       869,745,005      cpu_core/dTLB-loads/                                                    (98.68%)
            35,695      cpu_atom/dTLB-load-misses/       #    0.01% of all dTLB cache accesses  (1.32%)
            40,492      cpu_core/dTLB-load-misses/       #    0.00% of all dTLB cache accesses  (98.68%)

       0.830025280 seconds time elapsed

       0.716585000 seconds user
       0.113092000 seconds sys
```


## Results

### Baseline



<img width="752" height="610" alt="image" src="https://github.com/user-attachments/assets/e79adc22-4a8d-470c-8813-62e8be4547b1" />

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

### Intensity Sweep 


<img width="1580" height="1180" alt="image" src="https://github.com/user-attachments/assets/9f0fe66c-0bee-465f-8536-6f7c8c7dc353" />

From MLC, ALL Reads : 58958.4 MB/s ≈ 57.6 GB/s

At the identified knee point (≈ 54 GB/s @ ~185 ns latency), the system achieves: 54.0 GB/s ÷ 57.6 GB/s ≈ 94% of peak bandwidth

This shows the memory subsystem is able to reach near-peak throughput before hitting contention limits.

As thread intensity increases:
- Bandwidth scales up rapidly at first (from ~36 GB/s at 100 ns to ~54 GB/s).  
- Beyond the knee, adding more concurrency only yields marginal improvements in bandwidth.  
- Latency, however, continues to grow steadily, showing a clear trade-off: the controller queues requests faster than it can service them.

<img width="1579" height="1180" alt="image" src="https://github.com/user-attachments/assets/0e83597b-dea0-4fcd-91b9-c61cfe08b28d" />

This illustrates the law of diminishing returns: once the channels saturate, extra intensity mostly inflates queueing delay without significant throughput gains.

Little’s Law states: Throughput ≈ Concurrency / Latency. 
where:
- Throughput = operations per second
- Concurrency = average number of outstanding requests
- Latency = average response time per request

This can be checked against the data: 

| Threads | Avg. Latency (ns) | Measured Bandwidth (GB/s) | Bytes per Request (assume 64 B line) | Concurrency (Little’s Law) | Predicted BW (GB/s) |
|---------|-------------------|----------------------------|---------------------------------------|-----------------------------|----------------------|
| 1       | ~122 ns           | ~36 GB/s                  | 64 B                                  | (36e9 B/s × 122e-9 s)/64 B ≈ 69 | ≈ 36 GB/s |
| 4       | ~123 ns           | ~36–40 GB/s               | 64 B                                  | ~72                         | ≈ 37 GB/s |
| 8       | ~124 ns           | ~36–41 GB/s               | 64 B                                  | ~74                         | ≈ 38 GB/s |


For each case, measured throughput aligns with `Concurrency / Latency` once scaled by the 64-byte cache line size. At higher intensities, predicted throughput flattens because latency grows while concurrency only rises modestly. This explains the observed plateau in bandwidth: more threads simply increase latency without raising effective throughput.

The knee marks the transition from latency-limited to bandwidth-limited. Beyond this, adding more outstanding requests grows queues (latency) but does not meaningfully improve throughput, exactly as Little’s Law predicts.

### Working-set size sweep
<img width="791" height="555" alt="image" src="https://github.com/user-attachments/assets/ec4c7bd7-90b1-4024-82e5-9183094accc2" />


Observed Transitions
- L1 → L2 (~32 KiB): Latency remains flat at 2.4 ns, consistent with small cache hits.  
- L2 → L3 (~1.5 MiB): Latency rises slightly to ~3.1 ns.  
- L3 → DRAM (~18 MiB): Latency jumps again to ~5–6 ns.  

These transitions match the reported cache sizes from `lscpu`:
- L1d: 448 KiB total / 12 cores → ~37 KiB/core  
- L2: 9 MiB total / 6 cores → ~1.5 MiB/core  
- L3: 18 MiB shared  


The sweep shows the cache hierarchy. There's very low latency at small footprints (L1, L2), and then a noticeable step-up once the footprint exceeds L2 (~1.5 MiB). Then a further jump at ~18 MiB, consistent with leaving the shared LLC and going to DRAM. DRAM latency is more than double L3 latency, showing the steep cost of poor locality.

### Cache Miss Impact

| Case                  | Size (elements) | Pattern  | Runtime (ms) | LLC Miss Rate | Notes                |
|-----------------------|-----------------|----------|--------------|---------------|----------------------|
| L2-resident           | 393K (~1.5 MiB) | Seq      | 0.142        | 30–53%        | Fits in L2           |
| L3/DRAM boundary      | 16M (~64 MiB)   | Seq      | 7.9–8.0      | ~84%          | Exceeds 18 MiB L3    |
| DRAM, large stride    | 32M (~128 MiB)  | Stride 4K| 0.263        | ~55%          | Prefetch ineffective |
| DRAM, random access   | 16M (~64 MiB)   | Rand     | 351          | ~86%          | Prefetch defeated    |

As the miss rate rises, runtime per kernel grows.  
- L2 fit: fastest, low miss rate.  
- L3/DRAM: miss rate >80%, runtime 50× slower.  
- Random: immense slowdown despite similar miss %, since latency cannot be hidden.

Average Memory Access Time (AMAT): AMAT = L1_hit + L1_miss_rate × (L2_hit + L2_miss_rate × (L3_hit + L3_miss_rate × DRAM))
Using measured latencies (L1=1 ns, L2=3 ns, L3=8 ns, DRAM≈80 ns), for large sequential arrays: AMAT ≈ 35 ns. For random DRAM: effective AMAT > 300 ns, aligning with observed runtime.

This shows that ootprint and pattern strongly control cache miss rate. `perf` counters confirm a direct correlation between misses and runtime.  

### TLB-miss impact 

We evaluated the effect of TLB behavior on SAXPY performance by varying stride and enabling huge pages.

| Case                 | Stride    | Page Size | Runtime (ms) | dTLB-loads | dTLB-load-misses | Miss Rate |
|----------------------|-----------|-----------|--------------|------------|------------------|-----------|
| Sequential baseline  | 1         | 4 KiB     | 16.4         | 3.3B       | 40K              | 0.001%    |
| Page stress (bad)    | 4096      | 4 KiB     | 1150         | 3.3B       | 253K             | 0.007%    |
| Huge pages enabled   | 524288    | 2 MiB     | 0.017        | 3.3B       | 42K              | 0.001%    |

- **Stride=4096 with 4 KiB pages** increases dTLB miss rate and causes ~70× slowdown.  
- **Huge pages (2 MiB)** greatly expand TLB reach, restoring low miss rate and high throughput.

DTLB Reach
- With 4 KiB pages, reach ≈ 64 × 4 KiB = 256 KiB.  
- With 2 MiB huge pages, reach ≈ 64 × 2 MiB = 128 MiB.  
- Our footprint (≈1 GB) far exceeds 4 KiB reach, but fits under huge-page reach, explaining the observed results.

The TLB experiment shows that:
- **Page-locality matters:** bad strides trigger high TLB miss rates and huge slowdowns.  
- **Huge pages matter:** they dramatically increase effective TLB reach and performance.

<img width="1582" height="1180" alt="image" src="https://github.com/user-attachments/assets/7c0b3d0e-42e2-4f50-b191-6b1ac91ab556" />

The graph makes it clear: higher TLB miss rate directly correlates with worse runtime, and enabling huge pages collapses the miss rate and restores performance.






 




