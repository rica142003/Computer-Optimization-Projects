# SSD Performance Profiling

# Table of Contents
- [Introduction](#introduction)
- [Methodology](#methodology)
  - [Data Hygiene and Setup](#data-hygiene-and-setup)
  - [Zero-Queue Baseline](#zero-queue-baseline)
  - [Block-Size & Pattern Sweep](#block-size--pattern-sweep)
  - [Read/Write Mix Sweep](#readwrite-mix-sweep)
  - [Queue-Depth/Parallelism Sweep](#queue-depthparallelism-sweep)
  - [Tail-Latency Characterization](#tail-latency-characterization)
- [Results](#results)
  - [Zero-Queue Baselines](#zero-queue-baselines)
  - [Block-Size & Pattern Sweep](#block-size--pattern-sweep-1)
  - [Read-Write Mix](#read-write-mix)
  - [Queue-Depth/Parallelism Sweep](#queue-depthparallelism-sweep-1)
  - [Tail-Latency Characterization](#tail-latency-characterization-1)
- [Anomalies/Limitations](#anomalieslimitations)
- [Enterprise Spec vs Measured Results](#enterprise-spec-vs-measured-results)

---

# Introduction

The goal of this project is to study how SSDs behave under different workloads and levels of concurrency. The project shows the trade-off between throughput and latency, the point where adding more queue depth stops improving performance, and how these results match models like Little’s Law.

Experiments cover several areas: zero-queue latency tests, block size sweeps, read/write mix changes, queue-depth scaling, and tail-latency analysis. These experiments give a full picture of device performance. The focus is not only on maximum bandwidth or IOPS but also on finding where performance gains flatten out, how access patterns change results, and what tail latencies mean for meeting service-level goals.

# Methodology

## Data Hygiene and Setup

The goal of the setup was to make sure the results show the real behavior of the device. All I/O used direct access (`direct=1`) with 4 KiB alignment. This bypassed the page cache and avoided partial-block penalties. Tests were run directly on the raw device instead of a filesystem. A USB flash drive was used for the SSD profiling experiments. Before random-write tests, the drive was filled with random data to reach steady state. TRIM and discard operations were noted to avoid temporary effects. Device temperature was kept stable with airflow and logged to watch for throttling.

The host system was controlled to reduce noise. Tests ran on a 12th Gen Intel(R) Core(TM) i7-1260P (x86-64) with Linux. The CPU frequency governor was set to `performance` at 4.9 GHz to stop scaling. This removed jitter from background scheduling. Runs were isolated from the main OS partition, with background tasks turned off. Workloads were pinned to cores with `taskset` to avoid thread movement.

Workloads used incompressible data to prevent fake gains from compression. The order of trials was randomized. Each configuration was repeated several times. Results are shown as averages with standard deviation, plus p95 and p99 latencies to show tail effects. Interface limits for USB 3.x, SATA, and PCIe were noted during analysis. All software and hardware settings were logged, including FIO version, Linux kernel, CPU model, and drive details. These steps make the results reproducible and focused on the device itself, not the host system.

### Known Limitations

There are some limits from the hardware and platform used. The tests were done on a USB flash drive, not on an enterprise SATA or NVMe SSD. The USB bus adds higher latency, more variation from shared controller paths, and lower throughput caps. This keeps performance below what is normally seen with real SSDs.

Consumer flash drives also use simple controllers with little or no DRAM. They depend on wear-leveling and garbage collection, which can cause sudden latency spikes during long tests.

The i7-1260P CPU was pinned to 4.9 GHz, but it is a laptop processor. It can still throttle under heavy load due to heat, even with airflow control.

Because of these limits, the results show real device behavior but only for a USB flash drive. The numbers are consistent within this setup, but they should not be compared directly to enterprise SSD benchmarks.

## Zero-Queue Baseline

Zero-queue latency was measured using fio with a job file called `zero_queue_baselines.fio`. The job file set queue depth to one and forced I/O alignment to the device sector size.

The tests ran on the raw block device (`/dev/sda`) with `direct=1` to bypass the Linux page cache. The ioengine was set to libaio. Both `iodepth=1` and `numjobs=1` made sure only one request was active at a time. Each test ran for 30 seconds to give stable averages. Latency percentiles (p50, p95, p99) were also collected to show tail behavior.

The job file included four workloads, run sequentially with `stonewall`:
- 4 KiB random read – models small-block reads, like database queries.
- 4 KiB random write – tests random small writes on flash.
- 128 KiB sequential read – models large streaming reads, like video playback.
- 128 KiB sequential write – models bulk data writes, like backups.

This method gave clear measurements of both average and tail latency at queue depth one. Block sizes of 4 KiB and 128 KiB were chosen because they align with the device’s 4 KiB sector size.

## Block-Size & Pattern Sweep

Block-size sweeps were done with fio job files. Each job file set the access pattern (random or sequential) and then varied the request size. Block sizes tested were 4 KiB, 16 KiB, 32 KiB, 64 KiB, 128 KiB, and 256 KiB. For sequential tests, larger sizes of 512 KiB and 1 MiB were also included. Workloads were separated with `stonewall` so they ran one after another, not at the same time. This made sure each block size showed its own performance.

Direct I/O (`direct=1`) was used to skip the page cache so results came from the device, not system memory. The raw block device was targeted for correct 4 KiB alignment. The Linux async I/O engine (`ioengine=libaio`) with queue depth set to one (`iodepth=1`) was used. Each run was time-based with a fixed runtime to stabilize results. Latency percentiles (p50, p95, p99) were collected to measure both average and tail performance.

## Read/Write Mix Sweep

Read/write mix tests were set up in an fio job file. The test varied the ratio of reads to writes while keeping all other settings the same. The access pattern was fixed to 4 KiB random I/O. Queue depth was held at one with `iodepth=1` and `numjobs=1`. Direct I/O was enabled on the raw block device to bypass the page cache and keep alignment correct. The Linux async I/O engine (libaio) was used, and each run lasted a fixed time to give stable averages.

Four jobs were defined: 100% reads, 100% writes, 70/30, and 50/50. Each job was separated with stonewall and isolated with new_group so results would not mix together. Latency percentiles (p50, p95, p99) were collected with throughput. These results allow direct plots of throughput and latency to show the trade-offs between read-heavy and write-heavy workloads.

## Queue-Depth/Parallelism Sweep

Queue-depth tests were run with a mix of fio job files and a wrapper bash script. The workload was fixed to 4 KiB random I/O on the raw block device. Direct I/O was enabled to bypass the page cache. The only parameter changed was queue depth (`iodepth=1` → 128) to measure the effect of concurrency. Each queue-depth setting was placed in its own section with stonewall and new_group so the results were kept separate and sequential.

The bash script automated the runs. It repeated trials, saved logs with consistent names, and stored outputs in organized folders. This made it possible to average results and add error bars. At least five queue-depth points were collected for each sweep. The results give both throughput and latency from the same runs, allowing a single trade-off curve. 

## Tail-latency characterization

Tail-latency tests used an fio job file set up to measure how queue depth changes latency distribution. The workload was fixed to 4 KiB random reads on the raw block device. Direct I/O (`direct=1`) bypassed the page cache. The Linux async I/O engine (ioengine=libaio) was used. Incompressible data (`refill_buffers=1`, `norandommap=1`) prevented controller compression from affecting results.

Latency percentiles were turned on with `lat_percentiles=1` and `percentile_list=50:95:99:99.9`. This captured both average and tail behavior. Two queue depths (QD=8 and QD=32) were defined as separate sections (stonewall, new_group) so results stayed independent. Each run lasted 60 seconds with a 5-second warm-up to reach steady state.

This setup produced percentile data at p50, p95, p99, and p99.9. Results show how tail latency grows at higher queue depths and allow analysis of service-level impact near the saturation point.

# Results

## Zero-queue baselines

| Workload             | Avg Latency | p95 Latency | p99 Latency | Throughput            |
| -------------------- | ----------- | ----------- | ----------- | --------------------- |
| 4 KiB RandRead   | 0.54 ms     | 0.72 ms     | 0.76 ms     | 1836 IOPS (7.3 MiB/s) |
| 4 KiB RandWrite  | 3.0 ms      | 8.3 ms      | 10.7 ms     | 328 IOPS (1.3 MiB/s)  |
| 128 KiB SeqRead  | 15.3 ms     | 44 ms       | 114 ms      | 65 IOPS (8.4 MiB/s)   |
| 128 KiB SeqWrite | 15.3 ms     | 44 ms       | 114 ms      | 65 IOPS (8.3 MiB/s)   |

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

<p align="center">
  <img src="https://github.com/user-attachments/assets/0f73530e-f12a-4579-8dd3-38070bffa3b8" width="80%">
</p>

The read/write mix sweep shows that throughput is highest for 100% reads and drops sharply once writes are introduced, while latency rises at the same time. Pure reads reach over 6 MB/s with low latency, but even a 70/30 read–write mix reduces throughput to around 1.5 MB/s and increases latency. At a 50/50 mix, throughput falls below 1 MB/s, and at 100% writes, latency climbs to more than 3 ms with throughput stuck near 1 MB/s. 

These results are expected for USB flash devices. Reads are simple fetches, but writes are slowed by write amplification, where small 4 KiB updates trigger larger block erases and rewrites. Limited or absent write buffering further hurts performance, as each write may need to commit directly to flash. Mixing reads and writes makes this worse, because reads get delayed while the controller handles slow writes and flushes. The overall pattern demonstrates the clear cost of random writes on flash media and why write-heavy or mixed workloads suffer much lower efficiency than read-heavy ones.

## Queue-Depth/Parallelism Sweep

<p align="center">
  <img src="https://github.com/user-attachments/assets/d432d211-aad1-47a3-989b-c3f27fc013ec" width="80%">
</p>

The queue-depth sweep shows that throughput increases slightly from QD=1 to QD=4 while latency remains low. The curve flattens after QD=4, which marks the “knee” predicted by Little’s Law (Throughput ≈ Concurrency / Latency). At this point, adding more outstanding requests no longer increases throughput because the device is already saturated. Throughput at the knee is ~1775 IOPS, which is close to the practical ceiling for this USB flash drive given the USB interface and controller design. 

Compared to vendor specifications for NVMe or SATA SSDs, which can reach hundreds of thousands of IOPS, this is far lower, but it is consistent with the known limits of USB storage. Beyond the knee, queueing overhead dominates: QD=8, 16, and higher do not improve throughput but instead drive latency sharply upward. This illustrates the diminishing returns of parallelism on devices with little internal concurrency. Tail-latency measurements at the knee (p95 and p99) remain close to the mean, showing predictable service times when queues are shallow. However, at deeper queues, tail latency grows quickly, which would cause poor quality of service for applications requiring consistent response times.

## Tail-Latency Characterization

<p align="center">
  <img src="https://github.com/user-attachments/assets/3555b939-7e46-4ae1-9c8c-a4cd81663ec7" width="60%">
</p>


| Job  | p50 (ms) | p95 (ms) | p99 (ms) | p99.9 (ms) |
| ---- | -------- | -------- | -------- | ---------- |
| qd8  | 3.95     | 4.23     | 4.42     | 4.69       |
| qd32 | 17.43    | 18.22    | 18.48    | 18.74      |

The results show how queue depth changes latency. At QD=8, the median is about 4 ms, and higher percentiles stay close to this value. Latency is stable and predictable with little variation.

At QD=32, latency rises to about 17–19 ms for all percentiles. The tail values stay close to the median because nearly every request waits in the queue once the device is saturated. This follows Little’s Law: adding more requests past the knee only increases waiting time, not throughput.

For service-level agreements, shallow queues may work if the target is a few milliseconds. Deep queues, however, push latency far above 5 ms and would break stricter requirements. The results show that once saturation is reached, all operations face longer and consistent delays.

# Anomalies/Limitations

Sequential throughput stayed around 8 MB/s, far below the USB interface limit. This shows the bottleneck is in the flash controller and memory channels, not the bus. The high latency for 128 KiB transfers suggests the device breaks up large requests internally or the OS adds buffering delays. Random writes performed poorly, with 3–10 ms latency, caused by write amplification and the lack of strong buffering in USB flash drives.

Sequential workloads scaled as expected, but random workloads never reached the same throughput. Prefetching and queue merging cannot help random access, so performance is limited by controller design. Latency grew sharply at large block sizes, showing the device cannot handle large streaming requests well. Throughput stayed well below interface limits, confirming little internal parallelism in the controller.

Throughput dropped quickly when writes were introduced. At 100% reads, throughput was over 6 MB/s. At 50/50 or 100% writes, it fell near 1 MB/s, with latency rising at the same time. This sharp decline reflects heavy write amplification and weak buffering. It is common for USB flash but highlights the controller’s weakness in mixed workloads.

Throughput flattened near 1775 IOPS, while latency rose quickly past QD=4. Higher queue depths did not increase throughput because the device lacks parallelism. Instead, extra requests only added waiting time. This shows the controller cannot use deep queues, so latency grows with no performance gain.

At QD=8, tail latencies (p95, p99, p99.9) were close to the median, meaning response times were predictable. At QD=32, latency rose to ~18 ms across all percentiles. The tail did not spread much because all requests slowed equally once the device was saturated. This is not an error but a core limit: once overloaded, the device gives uniformly poor service. For SLAs, this is critical—predictable 18 ms latency would still fail requirements for sub-5 ms response times.

# Enterprise spec vs measured results 

The Intel D7-P5600 NVMe SSD (1.6 TB) can reach about 130K IOPS for 4 KiB random writes. The USB flash drive measured only ~300–350 IOPS at QD=1 (~1 MB/s). This huge gap is expected. The NVMe SSD runs on PCIe 4.0×4 with ~7.5 GB/s link bandwidth, deep queues, many NAND channels, and large DRAM caches. The USB flash has a slower interface, little or no parallelism, and minimal caching. It reaches saturation quickly, so higher queue depths do not improve IOPS. NVMe, in contrast, performs best at QD=32 or higher.

Controller design explains much of the difference. Enterprise SSDs use over-provisioning, caching, and controlled garbage collection to keep write performance steady. Small writes are absorbed into cache and reorganized into large blocks to reduce write amplification. USB flash lacks these features. Each 4 KiB write may cause a full erase-program cycle, leading to long latencies. Background wear-leveling and garbage collection add even more delay. Enterprise SSDs handle these tasks in a more predictable way.

Data patterns and interface limits also matter. NVMe benchmarks use random, steady-state data. Consumer USB drives may rely on SLC caching or compressible data for short bursts, but incompressible data shows the true cost. PCIe supports deep queues and low driver overhead, while USB adds protocol delays and usually allows only shallow queues. These differences explain why the NVMe SSD sustains ~130K IOPS while the USB flash levels off near ~300.
