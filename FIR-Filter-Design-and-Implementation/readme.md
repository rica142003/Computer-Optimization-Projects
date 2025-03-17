# FIR Filter Design and Implementation
## Objective
The objective of this project is to ...

## MATLAB Filter Design
MATLAB was used to design a digital filter based on specific parameters. The DSP System Toolbox provides the ```designfilt``` command, which opens an interactive design window as shown below. The goal was to create a low-pass filter with a transition region from 0.2π to 0.23π radians/sample and a stopband attenuation of 80 dB.

<p align="center">
  <img  src="https://github.com/user-attachments/assets/e8e99d0d-ba5e-44b1-961e-e8209b926b7e" style="width: 40%; height: auto;">
</p>

After designing the filter using designfilt, the ```filterAnalyzer``` tool was used to check the filter's performance, shown below. The filter was designed with the Equiripple method using the smallest possible order, resulting in 175 coefficients. This met all the required specifications.

<p align="center">
  <img  src="https://github.com/user-attachments/assets/2756113b-0c8a-4d0d-94e6-a6d0e1ef1862" style="width: 80%; height: auto;">
</p>

### Exporting coefficents to Q1.15 format
Coefficients were easily extracted from the filter using ```.Coefficients```. However, converting these floating-point values (e.g., -0.001121) into a format suitable for FPGA design required additional steps. A Python script was used to convert these values to a 16-bit Q1.15 fixed-point format. The script multiplies each coefficient by $2^{15}$ and formats the result into 16-bit two's complement. For example, the coefficient 0.000165 becomes 16'h0005. This conversion was done for all 175 coefficients, allowing them to be easily used in FPGA implementation.

## FPGA Implementation
### <ins> Pipelined </ins>
Pipelining a FIR filter is breaking the filter's calculation into multiple smaller steps that are each handled separately. Instead of one sample waiting for the entire computation to finish, multiple samples are processed simultaneously at different stages and can speed up the overall process. But it is trading slight latency and complexity for increased throughput and efficiency. 

- Data Shift Register (Delay Line):
The incoming data samples x[n] are stored and shifted through a sequence of registers (data_pipe). Each clock cycle, new input data shifts older data samples through the delay line, maintaining the correct sample delays essential for FIR operation.

- MAC Logic:
The multiply-accumulate operation multiplies delayed samples by their corresponding coefficients b[i] and sums these products. This stage utilizes parallel DSP resources to perform efficient multiplication and summation in parallel, reducing combinational delays and enhancing frequency performance.

<p align="center">
  <img  src="https://github.com/user-attachments/assets/10a1b4d1-0674-4541-af2c-9529e6cbbe1d" style="width: 80%; height: auto;">
</p>

The above is a RTL generated schematic from my implementation, this clearly shows pipeline registers ```RTL_REG_ASYNC``` inserted between arithmetic operations, notably between multipliers ```RTL_MULT``` and adders ```RTL_ADD```. These registers capture intermediate results, enabling simultaneous execution of multiple computation stages. 

### <ins>Reduced-complexity parallel processed (L=2) </ins>
Reduced complexity parallel processing improves the efficiency of FIR filters by splitting the input data stream into parallel paths, allowing multiple filter operations to be processed simultaneously. Parallel processing reduces the computational load per path by half, allowing higher throughput without increasing clock frequency. This approach is particularly useful for high-order filters, where the total number of MAC operations would otherwise create a bottleneck. By processing two paths simultaneously, the overall filter processing rate effectively doubles.

My parallelized FIR filter uses a L=2 structure where the input samples are divided into even (`x_even`) and odd (`x_odd`) indexed samples. The filter coefficients are also split into two sets: `coeffs_even[]` for even-indexed samples and `coeffs_odd[]` for odd-indexed samples. 
Two parallel shift registers store the incoming samples over time, maintaining the history needed for convolution. On each clock cycle, the even and odd samples are shifted down the registers, and a multiply-accumulate (MAC) operation is performed independently for each path. The even path computes the sum of products between even-indexed samples and `coeffs_even[]`, while the odd path computes the sum of products for the odd-indexed samples and `coeffs_odd[]`. 

<p align="center">
  <img  src="https://github.com/user-attachments/assets/ae0c849a-1345-4584-9a7c-c18466abe4d7" style="width: 60%; height: auto;">
</p>

The above is a RTL generated schematic from my implementation, it contains two distinct processing paths, one for even-indexed samples and one for odd-indexed samples, which allows simultaneous computation and effectively doubles the processing rate compared to a single-path filter. Each path has its own set of MAC units, indicated by the ```RTL_MULT``` and ```RTL_ADD``` blocks, confirming that both paths operate independently. The presence of separate shift registers ```RTL_REG_ASYNC``` for the even and odd data streams ensures that the input samples are processed concurrently without interference. 
The independent MAC operations in both paths demonstrate true parallelization, reducing latency and increasing throughput without increasing the clock frequency. This design is scalable, as more paths could be added to further increase processing efficiency.

### <ins>Reduced-complexity parallel processed (L=3) </ins>

Similar to L=2, L=3 has 3 parallel branches instead of 2.

<p align="center">
  <img  src="https://github.com/user-attachments/assets/865947c2-e3b1-4a59-bc23-1596e14f40d7" style="width: 60%; height: auto;">
</p>

This code demonstrates an L=3 parallelized FIR filter because it splits the input stream into three distinct data paths (`x0`, `x1`, `x2`) that process every third sample in parallel. Each path goes through the same filter structure (in the instantiated `fir_filter_3path` module), and their outputs (`y0`, `y1`, `y2`) correspond to the filtered results of those three interleaved input streams. By handling three samples per clock cycle (one on each path) rather than a single sample, the filter is effectively operating in a parallelized fashion with a decimation factor of three.

### <ins> Pipelined & Reduced-complexity parallel processed (L=3) </ins>

The code implements three separate FIR branches—one for each of the inputs x(3k), x(3k+1), and x(3k+2). By dividing the overall filter coefficients into three distinct sets (coeffs0, coeffs1, coeffs2), each branch processes its own subset of samples and coefficients in parallel. Furthermore, each branch has its own shift register, multiplier array, and final adder tree, allowing all three paths to operate simultaneously. The outputs of these three branches are then each registered (stored in flip-flops) before being sent out, which provides a pipeline stage that helps increase the maximum operating frequency by splitting the computation across multiple clock cycles.

<p align="center">
  <img  src="https://github.com/user-attachments/assets/683ffa3c-7e28-4c99-b57a-a866e7ac753d" style="width: 60%; height: auto;">
</p>

In the schematic, you can observe three distinct “chains” or “ladders” of multipliers and adders—one chain per path. Each ladder corresponds to one set of shift registers (for one of the parallel inputs) feeding into multipliers and then into an adder tree. The diagonal or stepped structure in the schematic visually illustrates the shifting of data through each path over time, and the separate multiplier-accumulator blocks confirm that multiple data samples are being processed in parallel. Additionally, the final registers at the outputs demonstrate the pipeline stage, as they store the computed results before the next set of inputs is processed, confirming the design’s pipelined nature.

## Quantized Filter Results


| Pipelined             |  L = 2 | 
:-------------------------:|:-------------------------:
![]()  |  ![](https://github.com/user-attachments/assets/a4770471-7e5e-4391-a1b8-f252234e2432) |  

| L = 3             |  L = 3 + Pipelined |
:-------------------------:|:-------------------------:
![]()  |  ![](https://github.com/user-attachments/assets/7f13af68-131a-4525-84f3-a0b49e71d006) | 

Pipelined & Parallelized L = 3: ```Time=            11570000: freq=0.722147```

## Hardware Implementation Results

### <ins>  Area Utilization </ins>

|  | LUTs     | FFs | DSP Blocks | I/O Pins |
|----------------|-----------------|-----------------|-----------------|-----------------|
| Pipelined      | 2540     | 2540     |173 | 52 |
| Parallelized L = 2 | 34| 2848 | 173 |  98|
| Parallelized L = 3 | 49| 2739 | 170 |  146|
| Pipelined & Parallelized L = 3 | 1743| 1632 | 90 |  146|

The table reflects trade-offs in FIR filter implementations: 
- The pipelined design uses many LUTs and FFs to insert registers for high-speed operation while maintaining constant DSP usage and minimal I/O
- Parallelized designs lower LUT counts by offloading computations to DSPs but require more FFs and I/O pins to handle multiple data paths concurrently
- The combined pipelined and parallelized approach strikes a balance by reducing DSP usage through time-multiplexing while still accommodating increased parallel I/O, thus optimizing throughput and resource allocation based on design priorities.
- Overall, the hybrid pipelined & parallelized design emerges as the best option if you need high performance with efficient resource sharing, as it offers a balanced compromise by reducing DSP and logic usage while still delivering the throughput required by parallel data processing.

### <ins> Power Estimation</ins> 

<p align="center">

| Pipelined             |  L = 2 | 
:-------------------------:|:-------------------------:
![]()  |  ![](https://github.com/user-attachments/assets/59a1f6ed-cf5e-4c5c-8132-280de96f9017) |  

| L = 3             |  L = 3 + Pipelined |
:-------------------------:|:-------------------------:
![](https://github.com/user-attachments/assets/c4a38b3d-6996-4e35-8d02-7e3e4abef679)  |  ![](https://github.com/user-attachments/assets/bdf61b1a-52aa-4e26-ad5c-5ed054b4b553) | 

</p>

### Timing
|  | Worst Negative Slack     | Worst Hold Slack | Worst Pulse Width Slack |
|----------------|-----------------|-----------------|-----------------|
| Pipelined      | 0.157ns     | 0.085ns |9.500ns |
| L = 2      | -     | 0.073ns |9.500ns |
| L = 2      | -     | 0.077ns |9.500ns |
| L = 3 + Pipelined    | 7.214ns     | 0.071ns |9.600ns |


