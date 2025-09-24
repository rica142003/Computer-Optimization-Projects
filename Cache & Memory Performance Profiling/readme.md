# Cache & Memory Performance Profiling

## Baseline
```
> lscpu | grep -i 'cache'
L1d cache:                            448 KiB (12 instances)
L1i cache:                            640 KiB (12 instances)
L2 cache:                             9 MiB (6 instances)
L3 cache:                             18 MiB (1 instance)
```

### Isolating single-access latency

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

## Results

### Baseline
| Level | Working Set (KiB) | n (floats) | Latency (ns) | Bandwidth (GB/s) |
|-------|-------------------|------------|--------------|------------------|
| L1d   | 448               | 114,688    | 4.38         | 45.00            |
| L2    | 9,216             | 2,359,296  | 33.88        | 26.22            |
| L3    | 18,432            | 4,718,592  | 78.47        | 23.74            |
| DRAM  | 65,536            | 16,777,216 | 112.76       | 20.10            |

