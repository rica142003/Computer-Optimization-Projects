# SSD Performance Profiling

# Introduction

# Methodology

## Zero-queue baseline

To measure the zero-queue latency of the flash device, fio was used with a dedicated job file (zero_queue_baselines.fio). 
The job file enforces a queue depth of one, bypassing the operating system’s page cache, and aligning I/O to the device’s sector size.

The global configuration targeted the raw block device (/dev/sda) with direct=1, ensuring that all I/O bypassed the Linux page cache so results reflect the flash device rather than host memory. 
`ioengine` was set to `libaio` to use the Linux asynchronous I/O interface, and `iodepth=1` with `numjobs=1` to enforce QD=1, guaranteeing only one request at a time. 
Each workload was run for 30 seconds (`time_based=1`, `runtime=30s`) to produce stable averages. 
Latency percentiles (p50, p95, p99) were enabled to capture tail behavior.

The job file defined four workloads separated by stonewall directives so they execute sequentially rather than concurrently:

- 4 KiB random read (randread_4k) – models small-block read workloads such as database queries.
- 4 KiB random write (randwrite_4k) – stresses flash write performance under small random updates.
- 128 KiB sequential read (seqread_128k) – models large streaming reads, such as video playback.
- 128 KiB sequential write (seqwrite_128k) – models large sequential writes, such as bulk data backup.

This setup provided a clean measurement of both average latency and tail latency at queue depth one. 
The block sizes (4 KiB and 128 KiB) were chosen as multiples of the device’s 4 KiB sector size, ensuring proper alignment.

# Results

## Zero-queue baselines

| Workload             | Avg Latency | p95 Latency | p99 Latency | Throughput            |
| -------------------- | ----------- | ----------- | ----------- | --------------------- |
| **4 KiB RandRead**   | 0.54 ms     | 0.72 ms     | 0.76 ms     | 1836 IOPS (7.3 MiB/s) |
| **4 KiB RandWrite**  | 3.0 ms      | 8.3 ms      | 10.7 ms     | 328 IOPS (1.3 MiB/s)  |
| **128 KiB SeqRead**  | 15.3 ms     | 44 ms       | 114 ms      | 65 IOPS (8.4 MiB/s)   |
| **128 KiB SeqWrite** | 15.3 ms     | 44 ms       | 114 ms      | 65 IOPS (8.3 MiB/s)   |

The results are consistent with a USB flash drive. 
Random operations show limited performance because the controller and interface are simple. 
Sequential transfers stall at only a few MB/s, which is typical for low-end flash storage.

The 4 KiB random read latency around 0.5 ms with throughput below 10 MB/s aligns with expectations for USB flash. 
The 4 KiB random write latency between 3–10 ms reflects slow write paths and limited buffering, a known characteristic of this device class.

The 128 KiB sequential workloads show throughput of ~8 MB/s. 
The reported latencies are high because low throughput translates into long per-operation service times. This is in line with the observed IOPS values.

As a baseline, these measurements are valid for the device under test. 
They provide a reference point for further sweeps of queue depth, block size, and read/write mixes. 
However, they should not be compared to SSDs connected over SATA or NVMe. 
Instead, they demonstrate how USB flash drives behave and why queuing, block size, and access pattern effects are affected.

## Block-size Sweep

| Sequential Read             |  Random Read | 
:-------------------------:|:-------------------------:
![](https://github.com/user-attachments/assets/dd73aeff-f1f3-4f7d-a066-526171eea9cc)  |  ![](https://github.com/user-attachments/assets/00d3d556-ddf7-41f3-8b38-33f8f41fd613) |  
![](https://github.com/user-attachments/assets/a9452e9e-76a4-4932-a1d6-d53af06b57a1)  |  ![](https://github.com/user-attachments/assets/207a0ff1-a3d2-42ac-8a68-ffa239de359a) |  

The block-size sweep shows how performance changes as requests get larger. For sequential reads, the average latency goes up slowly as block size increases and then jumps sharply after 64 KiB. This makes sense because larger blocks take more time to complete. At the same time, throughput in MB/s gets better with bigger block sizes and levels off close to the limit of the USB interface at about 100 MB/s. The IOPS number falls because fewer requests can fit into a second when each one is much larger.

For random reads, the trend is similar but weaker. Throughput improves with block size, but not as much as in the sequential case. Latency is higher because random access does not allow prefetching or streaming. The IOPS fall faster because the device struggles more with large random requests.

These results are shaped by prefetching, queue coalescing, and controller limits. Sequential access benefits from prefetching and from combining nearby requests into larger ones, which helps efficiency. Random access cannot use these tricks, so it stays slower. At large block sizes, both sequential and random transfers run into the maximum bandwidth of the USB flash drive. That is why throughput stops improving and latency rises sharply.

The cross-over between IOPS and bandwidth is clear. At small blocks like 4 KiB, performance is measured in IOPS, many small operations per second but little data moved. At large blocks like 64–128 KiB, performance is measured in MB/s, fewer operations but much more data per operation. This trade-off is normal and shows how the USB flash controller handles different workloads.


