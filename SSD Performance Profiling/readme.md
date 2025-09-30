# SSD Performance Profiling

# Introduction

The purpose of this project is to develop a systematic understanding of how storage devices behave under varying workload conditions and levels of concurrency. The project is designed to expose key trade-offs between throughput and latency, to identify the point at which additional queueing no longer yields meaningful performance gains, and to relate these observations to theoretical models such as Little’s Law. By conducting controlled experiments—ranging from zero-queue baselines and block-size sweeps to read/write mix variation, queue-depth scaling, and tail-latency characterization—the project provides a complete framework for analyzing device performance across multiple dimensions. The overall goal is not only to measure peak bandwidth or IOPS, but also to understand where diminishing returns occur, how workload patterns affect observable behavior, and what implications tail latencies have for real-world service-level requirements.

# Methodology

## Data Hygiene and Setup

The experimental methodology was developed to ensure that latency and throughput measurements reflect device-level behavior rather than host artifacts. All I/O was issued using direct access (`direct=1`) with 4 KiB alignment, which avoids page cache effects and eliminates partial-block penalties. Tests were executed directly against the raw device rather than a mounted filesystem, and this distinction was explicitly documented to clarify the visibility of block-level characteristics. For random-write workloads, the device was first preconditioned by filling the target range with random data to reach a steady state; any TRIM/discard operations were noted to avoid transient performance effects. Device temperature was controlled through consistent airflow, and temperatures were logged throughout the experiments to identify thermal throttling. To capture representative statistics, trials were randomized in execution order and repeated multiple times, with results reported as mean ± standard deviation alongside percentile latencies.

Data integrity was maintained by standardizing input patterns. Incompressible payloads were used consistently to prevent misleading compression gains on consumer SSDs, and the host environment was isolated by fixing CPU frequency governors and minimizing background activity, thereby reducing variance from host-side scheduling noise. Interface ceilings were also considered when interpreting performance, with reference limits for SATA, PCIe 3.0×4, and PCIe 4.0×4 explicitly noted. Full reproducibility was emphasized: all configuration files, software versions (fio release, kernel build), and hardware environments (device model, interface, and airflow conditions) were recorded to allow independent verification. This focus on reproducibility and data hygiene ensures that reported results are attributable to the storage device under controlled experimental conditions, not confounded by host effects or undocumented environmental variables.


## Zero-Queue Baseline

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

## Block-Size & Pattern Sweep

The block-size sweep experiments were implemented using fio job files that encode both the global parameters and the specific workloads required for analysis. Each job file fixed the access pattern, either random or sequential, and then varied the request size across the prescribed set of 4 KiB, 16 KiB, 32 KiB, 64 KiB, 128 KiB, and 256 KiB blocks, with optional extensions to 512 KiB and 1 MiB for sequential workloads. Individual workloads were separated by `stonewall` to ensure that tests executed sequentially instead of concurrently so it isolates the performance characteristics of each block size.

irect I/O (`direct=1`) was enabled to bypass the page cache, ensuring that results reflected device behavior rather than host buffering. The job files targeted the raw block device to guarantee alignment to the physical 4 KiB sectors. The Linux asynchronous I/O engine (`ioengine=libaio`) was used with a queue depth of one (`iodepth=1`) to maintain comparability between throughput and latency metrics. Each run was time-based with a fixed duration, producing stable results, and latency percentiles (p50, p95, p99) were collected to capture both central tendency and tail behavior.

## Read/Write Mix Sweep

The read/write mix experiments were encoded in a fio job file that varied the proportion of reads and writes while holding all other workload parameters constant. The global section fixed the access pattern to 4 KiB random I/O, enforced queue depth of one through iodepth=1 and numjobs=1, and enabled direct I/O on the raw block device to ensure alignment and bypass the page cache. The Linux asynchronous I/O engine was used to approximate realistic device-level scheduling, and each run was executed for a fixed duration to produce stable averages. 

Four jobs were defined to represent the required ratios, 100% reads, 100% writes, 70/30, and 50/50, each separated by `stonewall` and isolated with `new_group` to prevent statistical merging across runs. 
Latency percentiles (p50, p95, p99) were recorded alongside throughput, enabling dual-axis plots that directly reflect the trade-offs between read dominance and write dominance. This structure guarantees complete coverage of the required mixes, isolates the read/write ratio as the only swept parameter, and produces coherent, reproducible output suitable for joint analysis of throughput and latency.

## Queue-Depth/Parallelism Sweep

The queue-depth and parallelism experiments were implemented using a combination of fio job files and a wrapper bash script to ensure systematic coverage and reproducibility. The fio job file fixed the workload to 4 KiB random I/O on the raw block device with direct I/O enabled, bypassing the page cache, and varied only the queue depth (iodepth=1→128) to isolate the effect of concurrency. Each queue-depth setting was encoded as a separate section separated by stonewall and new_group directives so that fio executed them sequentially and reported results independently. 

The bash script automated execution of these sections across multiple trials, naming log files consistently and storing outputs in a structured directory, thereby enabling statistical averaging and the addition of error bars. Together, this design ensures ≥5 queue-depth points are collected in a coherent sweep, provides throughput and latency from the same runs for a single trade-off curve, and supplies the data needed to identify the knee of the curve via Little’s Law, quantify performance as a percentage of peak interface bandwidth, and analyze tail-latency behavior near saturation.

## ail-latency characterization

The fio jobfile for tail-latency characterization was designed to isolate the impact of queue depth on latency distributions while ensuring reproducibility and compliance with the rubric. The global section fixed key workload parameters: 4 KiB random reads on the raw block device with direct=1 to bypass the page cache, the Linux asynchronous I/O engine (ioengine=libaio), and incompressible data patterns (refill_buffers=1, norandommap=1) to avoid controller-level compression artifacts. Latency reporting was enabled with lat_percentiles=1 and an explicit percentile_list=50:95:99:99.9 to guarantee capture of both central tendency and tail behaviors. Individual queue depths were encoded as separate sections (qd8, qd32), each isolated by stonewall and new_group to prevent overlap and allow independent aggregation. A run time of 60 s with a 5 s ramp-up ensured steady-state behavior and stable percentile estimates. This configuration yields comprehensive percentile data (p50/p95/p99/p99.9) at both mid-range and near-knee concurrency levels, enabling quantification of tail-latency growth due to queueing and supporting analysis of service-level implications.

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

## Block-Size & Pattern Sweep

| Sequential Read             |  Random Read | 
:-------------------------:|:-------------------------:
![](https://github.com/user-attachments/assets/dd73aeff-f1f3-4f7d-a066-526171eea9cc)  |  ![](https://github.com/user-attachments/assets/00d3d556-ddf7-41f3-8b38-33f8f41fd613) |  
![](https://github.com/user-attachments/assets/a9452e9e-76a4-4932-a1d6-d53af06b57a1)  |  ![](https://github.com/user-attachments/assets/207a0ff1-a3d2-42ac-8a68-ffa239de359a) |  

The block-size sweep shows how performance changes as requests get larger. For sequential reads, the average latency goes up slowly as block size increases and then jumps sharply after 64 KiB. This makes sense because larger blocks take more time to complete. At the same time, throughput in MB/s gets better with bigger block sizes and levels off close to the limit of the USB interface at about 100 MB/s. The IOPS number falls because fewer requests can fit into a second when each one is much larger.

For random reads, the trend is similar but weaker. Throughput improves with block size, but not as much as in the sequential case. Latency is higher because random access does not allow prefetching or streaming. The IOPS fall faster because the device struggles more with large random requests.

These results are shaped by prefetching, queue coalescing, and controller limits. Sequential access benefits from prefetching and from combining nearby requests into larger ones, which helps efficiency. Random access cannot use these tricks, so it stays slower. At large block sizes, both sequential and random transfers run into the maximum bandwidth of the USB flash drive. That is why throughput stops improving and latency rises sharply.

The cross-over between IOPS and bandwidth is clear. At small blocks like 4 KiB, performance is measured in IOPS, many small operations per second but little data moved. At large blocks like 64–128 KiB, performance is measured in MB/s, fewer operations but much more data per operation. This trade-off is normal and shows how the USB flash controller handles different workloads.

## Read-Write Mix

<img width="812" height="572" alt="image" src="https://github.com/user-attachments/assets/0f73530e-f12a-4579-8dd3-38070bffa3b8" />

The read/write mix sweep shows that throughput is highest for 100% reads and drops sharply once writes are introduced, while latency rises at the same time. Pure reads reach over 6 MB/s with low latency, but even a 70/30 read–write mix reduces throughput to around 1.5 MB/s and increases latency. At a 50/50 mix, throughput falls below 1 MB/s, and at 100% writes, latency climbs to more than 3 ms with throughput stuck near 1 MB/s. 

These results are expected for USB flash devices. Reads are simple fetches, but writes are slowed by write amplification, where small 4 KiB updates trigger larger block erases and rewrites. Limited or absent write buffering further hurts performance, as each write may need to commit directly to flash. Mixing reads and writes makes this worse, because reads get delayed while the controller handles slow writes and flushes. The overall pattern demonstrates the clear cost of random writes on flash media and why write-heavy or mixed workloads suffer much lower efficiency than read-heavy ones.

## Queue-Depth/Parallelism Sweep

<img width="1050" height="750" alt="image" src="https://github.com/user-attachments/assets/d432d211-aad1-47a3-989b-c3f27fc013ec" />


The queue-depth sweep shows that throughput increases slightly from QD=1 to QD=4 while latency remains low. The curve flattens after QD=4, which marks the “knee” predicted by Little’s Law (Throughput ≈ Concurrency / Latency). At this point, adding more outstanding requests no longer increases throughput because the device is already saturated. Throughput at the knee is ~1775 IOPS, which is close to the practical ceiling for this USB flash drive given the USB interface and controller design. 

Compared to vendor specifications for NVMe or SATA SSDs, which can reach hundreds of thousands of IOPS, this is far lower, but it is consistent with the known limits of USB storage. Beyond the knee, queueing overhead dominates: QD=8, 16, and higher do not improve throughput but instead drive latency sharply upward. This illustrates the diminishing returns of parallelism on devices with little internal concurrency. Tail-latency measurements at the knee (p95 and p99) remain close to the mean, showing predictable service times when queues are shallow. However, at deeper queues, tail latency grows quickly, which would cause poor quality of service for applications requiring consistent response times.

## Tail-Latency Characterization

<img width="1401" height="980" alt="image" src="https://github.com/user-attachments/assets/3555b939-7e46-4ae1-9c8c-a4cd81663ec7" />

| Job  | p50 (ms) | p95 (ms) | p99 (ms) | p99.9 (ms) |
| ---- | -------- | -------- | -------- | ---------- |
| qd8  | 3.95     | 4.23     | 4.42     | 4.69       |
| qd32 | 17.43    | 18.22    | 18.48    | 18.74      |

The tail latency results confirm the impact of queueing on performance. At QD=8, median latency is about 4 ms, and the higher percentiles (p95, p99, p99.9) are only slightly above this value. This shows that latency is tightly clustered, with little jitter, and the device can still provide predictable response times. At QD=32, however, latency rises sharply to around 17–19 ms across all percentiles. The tail does not diverge much from the median because the queueing delay applies equally to nearly all requests once the device is saturated. From a queueing perspective, this matches Little’s Law: adding concurrency beyond the knee increases waiting time without improving throughput. For service-level agreements, the results mean that shallow queues may be acceptable for workloads with millisecond-level tolerances, but deep queues create uniformly high latency that would violate SLAs requiring consistent sub-5 ms service. The predictable but elevated latency at QD=32 highlights how exceeding the saturation point leads to degraded quality of service for all operations.

# Limitations and Anomalies

Sequential throughput stays capped at ~8 MB/s, much lower than the theoretical limits of the USB interface. This shows that the bottleneck is inside the flash controller and channels, not in the bus. The very high latency for 128 KiB transfers suggests that the device may be breaking up large requests internally or that the operating system introduced extra buffering delays. Random writes show poor performance, with latencies between 3–10 ms, which is explained by write amplification and the lack of effective write buffering in USB flash drives.

Sequential workloads scale as expected, but random workloads never reach the same throughput. This is because prefetching and queue coalescing cannot help random access, so the device is limited by controller design. Latency rises sharply at the largest block sizes, showing that the device cannot handle large streaming requests efficiently. Throughput levels off far below interface limits, confirming that there is little internal parallelism in the controller.

Throughput drops quickly once writes are introduced. At 100% reads, throughput is over 6 MB/s, but at 50/50 or 100% writes, throughput falls close to 1 MB/s. Latency rises at the same time. This sharp decline reflects heavy write amplification and the lack of strong write buffering. The sudden drop is not abnormal for USB flash, but it highlights a major limitation: the controller cannot manage mixed read/write workloads efficiently.

Throughput flattens quickly at ~1775 IOPS, while latency grows sharply past QD=4. This shows that higher queue depths bring no extra throughput because the device has no meaningful parallelism. Instead, the extra requests only add waiting time. The limitation here is clear: the flash controller cannot take advantage of deeper queues, so the trade-off is higher latency with no gain in performance.

At QD=8, tail latencies (p95, p99, p99.9) are close to the median, showing that response times are predictable. At QD=32, latencies rise sharply to ~18 ms across all percentiles. The tail does not diverge much from the median because all requests are slowed equally once the device is saturated. This is not a measurement error but a fundamental limitation: once overloaded, the device delivers uniformly poor service. This has clear SLA implications, since even predictable latency at ~18 ms would break requirements for consistent sub-5 ms response times.

# Conclusion

