# Cache & Memory Performance Profiling

## Table of Contents

  - [Introduction](#introduction)
  - [System Configuration](#system-configuration)
  - [Methodology](#methodology)
  - [Results](#results)
    - [Zero-Queue Baselines](#zero-queue-baselines)
    - [Pattern and Granularity Sweep](#pattern-and-granularity-sweep)
    - [Read/Write Mix Sweep](#readwrite-mix-sweep)
    - [Intensity Sweep](#intensity-sweep)
    - [Working-Set Size Sweep](#working-set-size-sweep)
    - [Cache-Miss Impact](#cache-miss-impact)
    - [TLB-Miss Impact](#tlb-miss-impact)
  - [Scripts, Data, and Analysis](#scripts-data-and-analysis)
  - [Anomalies and Limitations](#anomalies-and-limitations)
  - [Conclusion](#conclusion)
  - [How to Reproduce](#how-to-reproduce)
    - [1. Fix CPU Frequency](#1-fix-cpu-frequency)
    - [2. Pin to one core](#2-pin-to-one-core)
    - [3. Zero-Queue Latency](#3-zero-queue-latency)
    - [4. Pattern and Granularity Sweep](#4-pattern-and-granularity-sweep)
    - [5. Read/Write Mix Sweep](#5-readwrite-mix-sweep)
    - [6. Intensity Sweep](#6-intensity-sweep)
    - [7. Working-Set Size Sweep](#7-working-set-size-sweep)
    - [8. Cache-Miss Impact](#8-cache-miss-impact)
    - [9. TLB-Miss Impact](#9-tlb-miss-impact)

## Introduction
Modern CPUs rely on a hierarchy of caches before reaching DRAM, with each level offering different speeds and sizes. This hierarchy is critical for reducing the long latency of main memory. In this project, cache and memory behavior were studied through experiments that measured zero-queue latencies, throughput under different access patterns, read/write ratios, and intensity scaling. Additional tests examined how cache misses and TLB misses affect a lightweight kernel. Together, these experiments reveal how performance depends on locality and concurrency, and where bottlenecks arise when hardware limits are reached.

---

## System Configuration
The experiments were performed on a Linux system with the CPU frequency fixed at its maximum value of 4.7 GHz using the performance governor. Fixing the frequency removed variability due to frequency scaling and ensured consistent timing results. Tests were pinned to a single core with `taskset` to prevent thread migration and NUMA interference. Cache sizes were obtained from `lscpu`, reporting 448 KiB of L1d, 640 KiB of L1i, 9 MiB of L2, and 18 MiB of L3 cache. The memory type was LPDDR5, rated at 6400 MT/s but configured at 5200 MT/s, giving a calculated peak bandwidth of 83.2 GB/s. Hyper-threading was left enabled but controlled by pinning experiments to physical cores. Background processes were minimized during testing, and runs were repeated to check for noise.  

The tool versions were carefully recorded. Intel Memory Latency Checker (MLC) v3.11b was used for latency, bandwidth, and loaded-latency sweeps. Linux `perf` was used to measure cache references, cache misses, and TLB misses. A custom SAXPY kernel in C++ was used for lightweight workloads, compiled with GCC at `-O3` optimization. Bash scripts automated the runs, logging raw outputs to CSV files. Python with Matplotlib was used to parse and visualize the results.  

This controlled setup ensured that the experiments were repeatable and the results could be reproduced on similar hardware.

---

## Methodology
Zero-queue latency was measured using MLC in `--idle_latency` mode. This mode issues one request at a time, eliminating queuing effects, and when combined with core pinning, it provided stable and reproducible latency values.  

The effect of access pattern and granularity was tested using the SAXPY kernel with sequential and random access. Strides of 64B, 256B, and 1024B were chosen, and array sizes were made larger than the last-level cache to ensure memory traffic. Latency was derived from average runtime, while bandwidth was calculated from the data size and runtime.  

The impact of read/write mixes was explored with MLC in `--loaded_latency` mode. Ratios of 100% reads, 70/30 reads-to-writes, and 50/50 mixes were tested. A pure 100% write mode was not available in MLC, and this is recorded as a limitation.  

To study intensity scaling, MLC was run at different thread counts (`-t1`, `-t4`, and `-t8`). This produced throughput versus latency curves that revealed the “knee,” the point at which performance stopped scaling efficiently. The measured bandwidths were then compared against the theoretical peak value derived from DIMM specifications.  

Working-set size sweeps were conducted by gradually increasing footprint sizes to cross cache boundaries. The observed latency transitions were compared against reported cache sizes to validate the measurements.  

Cache-miss impact was analyzed by running SAXPY with different footprints and access patterns. `perf` counters measured cache references, LLC misses, and runtime. The Average Memory Access Time (AMAT) model was then applied to explain the relationship between miss rates and performance.  

Finally, TLB-miss impact was studied by varying page locality. Baseline runs used 4 KiB pages with stride=1, stress runs used 4 KiB pages with stride=4096 to force new-page accesses, and huge-page runs used 2 MiB pages with stride=524288. TLB miss counters were collected with `perf` and correlated directly with observed runtime changes.

---

## Results

### Zero-Queue Baselines
<p align="center">
  <img src="https://github.com/user-attachments/assets/3c5027d0-3190-4732-85bb-9ff6a94608fe" style="width: 80%; height: auto;">
</p>

The results show a clear step-like increase in latency as the working set exceeds each cache level. Access latency remains low at around 2.4 ns in the L1 cache, rises to 3.1 ns in the L2 cache, then grows to about 5.7 ns in the L3 cache, and finally becomes much higher when spilling into DRAM. Vertical markers on the plot align closely with the known cache boundaries, validating the measurement method.

---

### Pattern and Granularity Sweep
| Latency | Bandwidth |
|:---:|:---:|
| ![](https://github.com/user-attachments/assets/2c140715-f207-4fd5-8fd7-bc02d3300ba1) | ![](https://github.com/user-attachments/assets/2f71df6d-3f2d-4c51-8ba5-9d776f3459c1) |

Sequential access with a 64B stride provided the lowest latency and highest bandwidth. When the stride was increased to 256B and 1024B, the prefetcher became less effective, leading to higher latency and reduced throughput. Interestingly, some partial recovery was observed at 1024B, which may indicate hidden prefetcher heuristics. In the random case, latency remained high and bandwidth remained low regardless of stride, confirming that prefetching was completely ineffective.

---

### Read/Write Mix Sweep
| Latency | Bandwidth |
|:---:|:---:|
| ![](https://github.com/user-attachments/assets/f0d93d58-c1e6-4410-9e9a-d71422771c10) | ![](https://github.com/user-attachments/assets/28d44335-6354-4d72-b6b2-7bfdf56a814f) |

The read-only workload sustained high bandwidth and low latency until saturation. Introducing writes reduced sustainable bandwidth and increased latency. The 70/30 mix performed slightly worse than pure reads, while the 50/50 mix showed the strongest penalty. These results highlight the extra cost of handling writes, such as controller overhead and write amplification, compared to read-heavy traffic.

---

### Intensity Sweep
<p align="center">
  <img src="https://github.com/user-attachments/assets/a17ad6a5-e64d-43dd-b4d9-940fbfc50ec7" style="width: 50%; height: auto;">
</p>

Throughput scaled almost linearly with concurrency up to about 60 GB/s, after which latency rose sharply while bandwidth flattened. This knee point represents about 72% of the theoretical peak bandwidth of 83.2 GB/s. Below the knee, additional concurrency improved throughput without much penalty, while above it, latency dominated. The results align well with Little’s Law, which predicts that throughput equals concurrency divided by latency.

---

### Working-Set Size Sweep
<p align="center">
  <img src="https://github.com/user-attachments/assets/ec4c7bd7-90b1-4024-82e5-9183094accc2" style="width: 50%; height: auto;">
</p>

As the footprint grew, latency stayed flat within L1, rose slightly at L2, increased again at L3, and then jumped sharply into the DRAM region. These transitions matched closely with the reported cache sizes, illustrating the clear boundaries of each level in the hierarchy.

---

### Cache-Miss Impact
| Case | Size | Pattern | Runtime (ms) | LLC Miss Rate |
|------|------|---------|--------------|---------------|
| L2 fit | ~1.5 MiB | Seq | 0.142 | 30–53% |
| L3/DRAM | ~64 MiB | Seq | 7.9–8.0 | ~84% |
| DRAM stride | ~128 MiB | Stride 4K | 0.263 | ~55% |
| DRAM random | ~64 MiB | Rand | 351 | ~86% |

The experiments showed that higher miss rates directly increase runtime. When the working set fit in L2, performance was fast with relatively low miss rates. Once the footprint exceeded L3, miss rates rose above 80% and runtime slowed dramatically. Random access was the worst case, with very long runtimes even though the miss percentage was similar to sequential DRAM access. The AMAT model explained these results, linking latency penalties at each level with the observed runtime.

---

### TLB-Miss Impact
| Case | Stride | Page Size | Runtime (ms) | Miss Rate |
|------|--------|-----------|--------------|-----------|
| Baseline | 1 | 4 KiB | 16.4 | 0.001% |
| Stress | 4096 | 4 KiB | 1150 | 0.007% |
| Huge pages | 524288 | 2 MiB | 0.017 | 0.001% |

Using a stride of 4096 with 4 KiB pages caused a 70× slowdown, since each access forced a new TLB lookup. When huge pages were enabled, performance was restored because the effective TLB reach was extended. Although the measured miss percentages were small, their performance impact was very large, showing that TLB misses are extremely costly.

<p align="center">
  <img src="https://github.com/user-attachments/assets/7c0b3d0e-42e2-4f50-b191-6b1ac91ab556" style="width: 50%; height: auto;">
</p>

---

## Scripts, Data, and Analysis
All experiments were automated using Bash scripts that called MLC with specific flags and logged results into CSV files. A lightweight SAXPY kernel written in C++ was compiled with GCC at `-O3` to avoid artificial bottlenecks. Raw outputs included latencies in nanoseconds, bandwidth in MB/s or GB/s, and hardware counters from `perf`. Python scripts were used to aggregate the data, remove outliers, and generate plots. Each experiment was repeated at least three times, with results reported as mean ± standard deviation to ensure reliability.  

The analysis ties results closely to theory and counter data. The cache hierarchy was validated by the clear latency jumps at L1, L2, and L3 boundaries. Prefetcher effects were visible in the stride experiments, which showed near-ideal performance for small strides and poor performance for random patterns. Read/write mix results demonstrated the extra burden of writes on the controller. The intensity sweep confirmed the expected throughput–latency knee predicted by Little’s Law. Cache-miss and TLB-miss studies showed how microarchitectural events impact application runtime. The AMAT model and TLB reach calculations explained the observed performance trends.

---

## Anomalies and Limitations
Several anomalies and limitations were noted. MLC did not support pure 100% write tests in `--loaded_latency`, leaving that case unmeasured. In the granularity sweep, performance partially recovered at 1024B stride, which may reflect undocumented prefetch heuristics. The intensity sweep knee was measured at 72% of theoretical peak, which may be due to controller policies or DRAM row-buffer effects. Cache-miss counters sometimes showed similar percentages for workloads with very different runtimes, likely because of hidden memory-level parallelism. TLB misses had very low percentages but caused large slowdowns, confirming their high cost. Finally, small inconsistencies may have been caused by environmental noise such as background tasks, thermal variation, or limited ability to disable hardware prefetchers.

---

## Conclusion
This project provided a detailed characterization of cache and memory behavior on a modern CPU. By fixing the CPU frequency, pinning cores, minimizing background processes, and repeating runs, the experiments produced stable and reproducible results. Each required aspect of the memory hierarchy was examined: zero-queue latency, access pattern effects, read/write mixes, concurrency scaling, cache-miss behavior, and TLB performance. The results not only confirmed expected theoretical behavior, such as cache boundaries and Little’s Law, but also revealed practical limitations like controller overheads, prefetcher quirks, and the disproportionate cost of TLB misses.  

Overall, the study shows that performance depends strongly on locality and concurrency. Sequential, cache-friendly workloads achieve near-ideal behavior, while random or write-heavy workloads expose bottlenecks and inefficiencies. The methodology, based on MLC, `perf`, and controlled workloads, can be replicated on similar hardware and extended to other systems to better understand how modern memory hierarchies behave in practice.

---

## How to Reproduce

To make results reproducible, all experiments were run on Linux with the CPU frequency fixed at maximum and workloads pinned to a single core. The steps below describe exactly how to replicate the experiments.

### 1. Fix CPU Frequency
Lock the CPU to its maximum frequency (4.7 GHz in this case) using the performance governor.  
```bash
sudo cpupower frequency-set -g performance
lscpu | grep "MHz"    # confirm max frequency is active
```

### 2. Pin to one core

Pin experiments to core 0 to avoid thread migration and NUMA interference.
```
taskset -c 0 <command>
```
### 3. Zero-Queue Latency

Use MLC in idle mode to measure L1, L2, L3, and DRAM single-access latencies.

```
taskset -c 0 ./mlc --idle_latency
```

### 4. Pattern and Granularity Sweep

Run the SAXPY kernel with sequential and random accesses at different strides (64B, 256B, 1024B).
```
./saxpy --n 33554432 --stride 16          # ~64B stride
./saxpy --n 33554432 --stride 64          # ~256B stride
./saxpy --n 33554432 --stride 256         # ~1024B stride
./saxpy --n 33554432 --pattern rand       # random access
```

### 5. Read/Write Mix Sweep

Use MLC loaded-latency mode to test different mixes.

```
taskset -c 0 ./mlc --loaded_latency -R    # 100% reads
taskset -c 0 ./mlc --loaded_latency -W3   # ~70% reads / 30% writes
taskset -c 0 ./mlc --loaded_latency -W5   # ~50% reads / 50% writes
```

### 6. Intensity Sweep

The intensity sweep is obtained directly from the injection delay sweep in MLC.
```
taskset -c 0 ./mlc --loaded_latency -R
```
This command prints a table of Delay / Latency / Bandwidth. Parse these values and plot bandwidth vs. latency. The knee point is where latency rises sharply while bandwidth saturates.

### 7. Working-Set Size Sweep

Increase footprint sizes to cross cache boundaries.

```
./saxpy --n 8192        --stride 1     # fits in L1
./saxpy --n 393216      --stride 1     # fits in L2
./saxpy --n 16777216    --stride 1     # DRAM, sequential
./saxpy --n 33554432    --stride 4096  # DRAM, poor locality
./saxpy --n 16777216    --pattern rand # DRAM, random
```

### 8. Cache-Miss Impact

Measure cache references and misses with perf.
```
perf stat -e cycles,instructions,cache-references,cache-misses \
  ./saxpy --n 16777216 --stride 1
```

### 9. TLB-Miss Impact

Compare baseline 4 KiB pages, stressed 4 KiB pages, and huge 2 MiB pages.

```
perf stat -e dTLB-loads,dTLB-load-misses ./saxpy --n 33554432 --stride 1
perf stat -e dTLB-loads,dTLB-load-misses ./saxpy --n 134217728 --stride 4096
perf stat -e dTLB-loads,dTLB-load-misses ./saxpy --n 134217728 --stride 524288 --huge
```


