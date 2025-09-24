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

### Isolating Single-Access Latency

Pointer chase is implemented as:
```
size_t latency_test(std::vector<size_t>& ptrs, size_t iters) {
    volatile size_t idx = 0;
    for (size_t i = 0; i < iters; i++) {
        idx = ptrs[idx];  // each load depends on previous
    }
    return idx;
}
```

Using `numactl --cpunodebind=0 --membind=0 ./baseline`. 
`--cpunodebind=0` pins the process to NUMA node 0’s CPUs, and `--membind=0` forces all allocations (malloc, new, std::vector) to come from NUMA node 0 memory.
This ensures that latency results reflect local L1/L2/L3/DRAM only.

### Calculating Latency using CPU Frequency

Latency (cycles) is calculated using: $\text{Latency (ns)} \times \text{CPU Freq (GHz)}$

## Results

### Baseline
| Level | Working Set (KiB) | n (floats) | Latency (ns) | Latency (cycles @ 4.7 GHz) | Bandwidth (GB/s) |
|-------|-------------------|------------|--------------|----------------------------|------------------|
| L1d   | 448               | 114688    | 4.49628         | 21.1325                       | 32.3536 |
| L2   | 9216               | 2359296    | 36.1189         | 169.759                       | 27.5329 |
| L3   | 18432               | 4718592    | 78.3019         | 368.019                       | 22.9061 |
| DRAM   | 65536               | 16777216    | 114.772         | 539.428                       | 22.0466 |

