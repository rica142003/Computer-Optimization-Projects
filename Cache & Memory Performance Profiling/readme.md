# Cache & Memory Performance Profiling

# Introduction

# Methodology

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

<p align="left">
  <img  src="https://github.com/user-attachments/assets/e79adc22-4a8d-470c-8813-62e8be4547b1" style="width: 40%; height: auto;">
</p>

### Isolating Single-Access Latency

Running taskset -c 0 mlc --idle_latency provides the correct method for isolating single-access latency in the memory hierarchy. The --idle_latency mode in Intel’s Memory Latency Checker issues one request at a time with no overlap, thereby eliminating queuing effects and capturing the true service time of each level (L1, L2, L3, and DRAM). Pinning the tool to a single core with taskset -c 0 ensures that measurements are not distorted by thread migration or NUMA placement.

## Pattern and Granularity Sweep

Stride (bytes) → stride (elements): 64B→16, 256B→64, 1024B→256 (float = 4B).

Use a footprint well above LLC so you stress memory (e.g., n=16,777,216 → ~64 MiB per array; n=33,554,432 → ~128 MiB per array).
```
# Sequential (prefetch-friendly), three granularities
./saxpy --n 33554432 --stride 16   > out_seq_64B.txt
./saxpy --n 33554432 --stride 64   > out_seq_256B.txt
./saxpy --n 33554432 --stride 256  > out_seq_1024B.txt

# Random (prefetch defeated). Stride is irrelevant in rand mode—keep it 1 for clarity.
./saxpy --n 33554432 --pattern rand > out_rand_64B.txt
./saxpy --n 33554432 --pattern rand > out_rand_256B.txt
./saxpy --n 33554432 --pattern rand > out_rand_1024B.txt
```

Latency is estimated with: `lat_ns = (avg_ms * 1e6) / iters`

## Read/Write Mix Sweep

`mlc --loaded_latency R/W3/W5` gives: ALL Reads (100% read), 2:1 Reads-Writes (close to 70/30), 1:1 Reads-Writes (50/50)
100% Writes is not a menu option and therefore is not explored.

## Intensity Sweep 

Intel Memory Latency Checker (v3.11b) with `--loaded_latency` at varying thread intensities (`-t1`, `-t4`, `-t8`) to measure the throughput–latency tradeoff. 
```
> mlc --loaded_latency -t4
Intel(R) Memory Latency Checker - v3.11b
Command line parameters: --loaded_latency -t4 

Using buffer size of 183.105MiB/thread for reads and an additional 183.105MiB/thread for writes
* Unable to modify prefetchers (try executing 'modprobe msr')
* So, enabling random access for latency measurements

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


# Results

## Baseline

<p align="center">
  <img  src="https://github.com/user-attachments/assets/3c5027d0-3190-4732-85bb-9ff6a94608fe" style="width: 80%; height: auto;">
</p>

The graph captures the expected step-like increases in access latency as the working set grows beyond each cache level. In the **sub-megabyte region**, latencies remain flat at ~2.4 ns, corresponding to fast **L1 cache** hits. Once the buffer size exceeds the L1 capacity (~448 KiB), latency rises modestly to ~3.1 ns, reflecting **L2 cache** accesses. As the buffer crosses the L2 boundary (~9 MiB), latency increases more sharply, reaching ~5.7 ns in the **L3 cache** region. The vertical red markers align with these cache boundaries, clearly illustrating how each jump in buffer size forces requests to traverse deeper levels of the hierarchy. The overall shape emphasizes the efficiency of small, cache-resident data and the costlier access times as locality decreases, providing a clean baseline for interpreting later experiments that add concurrency or stress memory bandwidth.


## Pattern and Granularity Sweep

| Latency             |  Bandwidth| 
:-------------------------:|:-------------------------:
![](https://github.com/user-attachments/assets/2c140715-f207-4fd5-8fd7-bc02d3300ba1)  |  ![](https://github.com/user-attachments/assets/2f71df6d-3f2d-4c51-8ba5-9d776f3459c1) |  

The latency and bandwidth curves illustrate the strong role of stride and prefetching in memory system performance:

- Sequential, 64 B stride (≈1 cache line):  
  Latency is lowest (~7 ns/access) and bandwidth peaks (~0.27 GiB/s). This is the best-case scenario: accesses are contiguous, and the hardware prefetcher can perfectly anticipate the next cache line.

- Sequential, larger strides (256 B and 1024 B):  
  Latency rises (up to ~17 ns/access) and bandwidth falls. With wider strides, each access skips multiple cache lines. The prefetcher cannot fully predict or issue those fetches in time, so effective spatial locality decreases. The dip and partial recovery at 1024 B suggests that some prefetch logic still works when the stride is consistent but large, though not nearly as effectively as at 64 B.

- Random access (all strides):  
  Latency stays high (~23–24 ns/access) and bandwidth low (~0.08–0.09 GiB/s), with very little dependence on stride. This reflects the fact that random access completely defeats the prefetcher. Each load becomes a near-independent memory operation, dominated by DRAM latency.

Prefetchers are optimized for small, contiguous strides (1–2 cache lines). Sequential 64 B access achieves near-ideal performance. As stride grows, prefetching cannot keep up and performance degrades. In the random case, prefetching provides no benefit, leaving the system fully memory-latency-bound. These trends match the expected hierarchy behavior and highlight the importance of locality-aware access patterns in high-performance code.

## Read/Write mix sweep 

| Latency             |  Bandwidth| 
:-------------------------:|:-------------------------:
![](https://github.com/user-attachments/assets/f0d93d58-c1e6-4410-9e9a-d71422771c10)  |  ![](https://github.com/user-attachments/assets/28d44335-6354-4d72-b6b2-7bfdf56a814f) |  

For 100% reads, bandwidth remains nearly flat at high values until a critical injection delay is reached, after which performance falls sharply. Latency in this case stays low and relatively stable, indicating efficient servicing of read requests with minimal queuing overhead. In contrast, when writes are introduced (70%R/30%W and 50%R/50%W), the maximum sustainable bandwidth is slightly reduced, and the bandwidth drop-off occurs earlier. This reflects the higher service cost of writes, which demand additional controller resources such as program/erase cycles and block management, thereby reducing effective throughput at lower injection delays.

Latency trends reinforce this distinction. Mixed workloads exhibit higher average latencies than pure reads, with the 50/50 mix showing the largest penalty. At low injection delays, latency remains bounded, but as the system nears saturation, latencies rise steeply, especially for mixed workloads where write amplification and scheduling contention become more prominent. Together, these results illustrate how workload composition strongly influences both the efficiency and predictability of memory subsystems: read-heavy traffic maximizes throughput with stable latency, while increasing write fractions accelerate bandwidth collapse and amplify queueing effects.


## Intensity Sweep 

<p align="center">
  <img  src="https://github.com/user-attachments/assets/a17ad6a5-e64d-43dd-b4d9-940fbfc50ec7" style="width: 50%; height: auto;">
</p>

The “knee” appears around 60 GB/s, where bandwidth approaches saturation and latency begins to climb steeply from ~110 ns up past 140 ns. Below this point, additional concurrency yields meaningful throughput gains with little latency penalty; beyond it, diminishing returns dominate, consistent with queuing theory and Little’s Law. Thus, ~60 GB/s represents the effective knee where the memory system transitions from efficient scaling to overloaded behavior.

To determine the theoretical peak memory bandwidth of the system, the `dmidecode` tool was used to query detailed RAM specifications. Running `sudo dmidecode -t memory | egrep -i 'Speed|Type'` revealed that the installed memory is LPDDR5 configured at 5200 MT/s. Using the standard bandwidth formula—Memory Speed (MT/s) × 8 bytes (per 64-bit channel) × number of channels (2 for dual-channel)—the peak bandwidth was calculated as ($5200 \times 10^6 \times 8 \times 2 = 83.2$) GB/s. Comparing this to the measured intensity sweep, the knee point around 60 GB/s corresponds to roughly 72% of the theoretical peak, which shows efficiency while also showing the start of diminishing returns as concurrency increases and memory latency rises.

## Working-set size sweep

<p align="center">
  <img  src="https://github.com/user-attachments/assets/ec4c7bd7-90b1-4024-82e5-9183094accc2" style="width: 50%; height: auto;">
</p>

Latency is flat and minimal (~2.4 ns) while the footprint fits in L1, rises slightly at the L2 boundary (~1.5 MiB), then steps up again when spilling into L3 (~18 MiB), and finally climbs sharply into the DRAM region where latency more than doubles (~5+ ns). Each “knee” of the curve aligns almost perfectly with your CPU’s reported cache sizes, illustrating how memory access time grows as the working set exceeds the reach of progressively larger but slower levels of the hierarchy.

## Cache Miss Impact

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

## TLB-miss impact 

We evaluated the effect of TLB behavior on SAXPY performance by varying stride and enabling huge pages.

| Case                 | Stride    | Page Size | Runtime (ms) | dTLB-loads | dTLB-load-misses | Miss Rate |
|----------------------|-----------|-----------|--------------|------------|------------------|-----------|
| Sequential baseline  | 1         | 4 KiB     | 16.4         | 3.3B       | 40K              | 0.001%    |
| Page stress (bad)    | 4096      | 4 KiB     | 1150         | 3.3B       | 253K             | 0.007%    |
| Huge pages enabled   | 524288    | 2 MiB     | 0.017        | 3.3B       | 42K              | 0.001%    |

- Stride=4096 with 4 KiB pages increases dTLB miss rate and causes ~70× slowdown.  
- Huge pages (2 MiB) greatly expand TLB reach, restoring low miss rate and high throughput.

DTLB Reach
- With 4 KiB pages, reach ≈ 64 × 4 KiB = 256 KiB.  
- With 2 MiB huge pages, reach ≈ 64 × 2 MiB = 128 MiB.  
- Our footprint (≈1 GB) far exceeds 4 KiB reach, but fits under huge-page reach, explaining the observed results.

The TLB experiment shows that:
- Page-locality matters: bad strides trigger high TLB miss rates and huge slowdowns.  
- Huge pages matter: they dramatically increase effective TLB reach and performance.

<p align="center">
  <img  src="https://github.com/user-attachments/assets/7c0b3d0e-42e2-4f50-b191-6b1ac91ab556" style="width: 50%; height: auto;">
</p>

The graph makes it clear: higher TLB miss rate directly correlates with worse runtime, and enabling huge pages collapses the miss rate and restores performance.






 




