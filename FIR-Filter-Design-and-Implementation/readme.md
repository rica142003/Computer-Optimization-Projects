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

### Exporting coefficents
Coefficients were easily extracted from the filter using ```.Coefficients```. However, converting these floating-point values (e.g., -0.001121) into a format suitable for FPGA design required additional steps. A Python script was used to convert these values to a 16-bit Q1.15 fixed-point format. The script multiplies each coefficient by $2^{15}$ and formats the result into 16-bit two's complement. For example, the coefficient 0.000165 becomes 16'h0005. This conversion was done for all 175 coefficients, allowing them to be easily used in FPGA implementation.

## FPGA Implementation
### Pipelined 
Pipelining a FIR filter is breaking the filter's calculation into multiple smaller steps that are each handled separately. Instead of one sample waiting for the entire computation to finish, multiple samples are processed simultaneously at different stages and can speed up the overall process. But it is trading slight latency and complexity for increased throughput and efficiency. 

- Data Shift Register (Delay Line):
The incoming data samples x[n] are stored and shifted through a sequence of registers (data_pipe). Each clock cycle, new input data shifts older data samples through the delay line, maintaining the correct sample delays essential for FIR operation.

- MAC Logic:
The multiply-accumulate operation multiplies delayed samples by their corresponding coefficients b[i] and sums these products. This stage utilizes parallel DSP resources to perform efficient multiplication and summation in parallel, reducing combinational delays and enhancing frequency performance.

<p align="center">
  <img  src="https://github.com/user-attachments/assets/10a1b4d1-0674-4541-af2c-9529e6cbbe1d" style="width: 80%; height: auto;">
</p>

The above is a RTL generated schematic from my implementation, this clearly shows pipeline registers ```RTL_REG_ASYNC``` inserted between arithmetic operations, notably between multipliers ```RTL_MULT``` and adders ```RTL_ADD```. These registers capture intermediate results, enabling simultaneous execution of multiple computation stages. 

### Reduced-complexity parallel processed (L=2) 
Reduced complexity parallel processing improves the efficiency of FIR filters by splitting the input data stream into parallel paths, allowing multiple filter operations to be processed simultaneously. Parallel processing reduces the computational load per path by half, allowing higher throughput without increasing clock frequency. This approach is particularly useful for high-order filters, where the total number of MAC operations would otherwise create a bottleneck. By processing two paths simultaneously, the overall filter processing rate effectively doubles.

My parallelized FIR filter uses a L=2 structure where the input samples are divided into even (`x_even`) and odd (`x_odd`) indexed samples. The filter coefficients are also split into two sets: `coeffs_even[]` for even-indexed samples and `coeffs_odd[]` for odd-indexed samples. 
Two parallel shift registers store the incoming samples over time, maintaining the history needed for convolution. On each clock cycle, the even and odd samples are shifted down the registers, and a multiply-accumulate (MAC) operation is performed independently for each path. The even path computes the sum of products between even-indexed samples and `coeffs_even[]`, while the odd path computes the sum of products for the odd-indexed samples and `coeffs_odd[]`. 

<p align="center">
  <img  src="https://github.com/user-attachments/assets/ae0c849a-1345-4584-9a7c-c18466abe4d7" style="width: 80%; height: auto;">
</p>

The above is a RTL generated schematic from my implementation, it contains two distinct processing paths, one for even-indexed samples and one for odd-indexed samples, which allows simultaneous computation and effectively doubles the processing rate compared to a single-path filter. Each path has its own set of MAC units, indicated by the ```RTL_MULT``` and ```RTL_ADD``` blocks, confirming that both paths operate independently. The presence of separate shift registers ```RTL_REG_ASYNC``` for the even and odd data streams ensures that the input samples are processed concurrently without interference. 
The independent MAC operations in both paths demonstrate true parallelization, reducing latency and increasing throughput without increasing the clock frequency. This design is scalable, as more paths could be added to further increase processing efficiency.

### Reduced-complexity parallel processed (L=3) 

### Pipelined & Reduced-complexity parallel processed (L=3) 

## Hardware Implementation Results

### Utilization
|  | LUTs     | FFs | DSP Blocks | I/O Pins |
|----------------|-----------------|-----------------|-----------------|-----------------|
| Pipelined      | 2540     | 2540     |173 | 52 |
| L =2 | 34| 2848 | 173 |  98|

### Power Estimation

|  | Dynamic     | Static | Total |
|----------------|-----------------|-----------------|-----------------|
| Pipelined      | 0.306W     | 0.175W     |0.131W |
 | L =2 | 0.131W | 0.140W | 0.271W|

### Timing
|  | Worst Negative Slack     | Worst Hold Slack | Worst Pulse Width Slack |
|----------------|-----------------|-----------------|-----------------|
| Pipelined      | 0.157ns     | 0.085ns |9.500ns |
| L=2      | -     | 0.073ns |9.500ns |
