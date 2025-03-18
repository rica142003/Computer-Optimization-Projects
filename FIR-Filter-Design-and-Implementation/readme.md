# FIR Filter Design and Implementation
## Objective
The objective of this project is to design and test an FIR filter with specific parameters, and implement four different FPGA architectures using parallelization and pipelining. These implementations are analyzed to evaluate their performance and trade-offs.

## MATLAB Filter Design
MATLAB was used to design a digital filter. The DSP System Toolbox provides the ```designfilt``` command, which opens an interactive design window as shown below. The goal was to create a low-pass filter with a transition region from 0.2π to 0.23π radians/sample and a stopband attenuation of 80 dB.

<p align="center">
  <img  src="https://github.com/user-attachments/assets/e8e99d0d-ba5e-44b1-961e-e8209b926b7e" style="width: 40%; height: auto;">
</p>

After designing the filter using designfilt, the ```filterAnalyzer``` tool was used to check the filter's performance, shown below. The filter was designed with the Equiripple method using the smallest possible order, resulting in 175 coefficients. This met all the required specifications.

<p align="center">
  <img  src="https://github.com/user-attachments/assets/2756113b-0c8a-4d0d-94e6-a6d0e1ef1862" style="width: 80%; height: auto;">
</p>

### Quantization Effect
Quantization converts filter coefficients from a continuous form into discrete values which can introduce small rounding errors. These errors can alter the filter’s magnitude response which can lead to increased ripple in the passband or reduced attenuation in the stopband. 

However, one key benefit of FIR filters is that quantization does not affect their stability as they only use current and past input values. So even if the coefficients are slightly off due to quantization, the filter's output remains bounded and stable.

I used a MATLAB script that designs the unquantized FIR filter, creates a quantized version of its coefficients (using a Q15 format as an example), and then compares the two via a frequency response:

<p align="center">
  <img  src="https://github.com/user-attachments/assets/f6db570b-2d07-4800-b2d0-b23980e8d0ff" style="width: 60%; height: auto;">
</p>

The quantized version shows slight ripples due to coefficient rounding. In the transition band (0.2 to 0.23), it has minor deviations in slope. In the stopband (above 0.23), it has some fluctuations because rounding changes the precise filter zeros. These differences can be terrible if coefficient or accumulator word lengths are insufficient, leading to overflows during arithmetic operations. Such overflows can degrade performance by introducing large errors and distorting the filter response.

### Dealing with Overflows
I decided to use Q1.15 format so each filter coefficient lies within the range `[−1,1)`, but it does not guarantee the prevention of overflows by itself as the intermediate sum of products can still overflow. An example of how I prevented overflows is as follows:

```
parameter integer SHIFTAMT = 8; // can be different (eg. 12, 13, 14, ...)
y_out <= (sum_out + (32'sd1 << (SHIFT_AMT-1))) >>> SHIFT_AMT;
```

This code adds half of the divisor (i.e., $2^{SHIFTAMT-1}$) to the sum before performing an arithmetic right shift, which effectively divides by  $2^{SHIFTAMT-1}$ with proper rounding rather than truncation. This rounding minimizes accumulated rounding errors and helps prevent values from overflowing.

### Exporting coefficents to Q1.15 format
Coefficients were easily extracted from the filter using ```.Coefficients```. However, converting these floating-point values (e.g., -0.001121) into a format suitable for FPGA design required additional steps. A Python script was used to convert these values to a 16-bit Q1.15 fixed-point format. The script multiplies each coefficient by $2^{15}$ and formats the result into 16-bit two's complement. This conversion was done for all 175 coefficients, allowing them to be easily used in FPGA implementation as shown: ```16'h0005, 16'h000C, 16'h0015, 16'h001D, 16'h001F, ...```.

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

The above is a generated schematic from my architecture, this clearly shows pipeline registers ```RTL_REG_ASYNC``` inserted between arithmetic operations, notably between multipliers ```RTL_MULT``` and adders ```RTL_ADD```. These registers capture intermediate results, enabling simultaneous execution of multiple computation stages. 

### <ins>Reduced-complexity parallel processed (L=2) </ins>
Reduced complexity parallel processing splits the input data stream into parallel paths which allows multiple filter operations to be processed simultaneously. It reduces the computational load per path by half, allowing higher throughput without increasing clock frequency. This approach is useful for high-order filters, where the total number of MAC operations would otherwise create a bottleneck. By processing two paths simultaneously, the overall filter processing rate effectively doubles.

My parallelized FIR filter uses a L=2 structure where the input samples are divided into even (`x_even`) and odd (`x_odd`) indexed samples. The filter coefficients are also split into two sets: `coeffs_even[]` for even-indexed samples and `coeffs_odd[]` for odd-indexed samples. 
Two parallel shift registers store the incoming samples over time which maintains the history needed for convolution. On each clock cycle, the even and odd samples are shifted down the registers, and a MAC operation is performed independently for each path. 

<p align="center">
  <img  src="https://github.com/user-attachments/assets/ae0c849a-1345-4584-9a7c-c18466abe4d7" style="width: 60%; height: auto;">
</p>

The above is a generated schematic from my architecture, it contains two distinct processing paths, one for even-indexed samples and one for odd-indexed samples. Each path has its own set of MAC units, indicated by the ```RTL_MULT``` and ```RTL_ADD``` blocks, confirming that both paths operate independently. 
The presence of separate shift registers ```RTL_REG_ASYNC``` for the even and odd data streams ensures that the input samples are processed concurrently without interference. 
The independent MAC operations in both paths shows true parallelization.

### <ins>Reduced-complexity parallel processed (L=3) </ins>

Similar to L=2, L=3 has 3 parallel branches instead of 2.

<p align="center">
  <img  src="https://github.com/user-attachments/assets/865947c2-e3b1-4a59-bc23-1596e14f40d7" style="width: 60%; height: auto;">
</p>

The above is a generated schematic from my architecture, this demonstrates an L=3 parallelized FIR filter because it splits the input stream into three distinct data paths (`x0`, `x1`, `x2`) that process every third sample in parallel. 
Each path goes through the same filter structure (the `fir_filter_3path` module), and their outputs (`y0`, `y1`, `y2`) correspond to the filtered results of those three interleaved input streams. By handling three samples per clock cycle (one on each path) rather than a single sample, the filter is effectively operating in parallel with a factor of three.

### <ins> Pipelined & Reduced-complexity parallel processed (L=3) </ins>

The architecture implements three separate FIR branches—one for each of the inputs $x(3k)$, $x(3k+1)$, and $x(3k+2)$. By dividing the overall filter coefficients into three distinct sets (coeffs0, coeffs1, coeffs2), each branch processes its own subset of samples and coefficients in parallel. 
Furthermore, each branch has its own shift register, multiplier array, and final adder tree, allowing all three paths to operate simultaneously. The outputs of these three branches are then each registered (stored in flip-flops) before being sent out, which provides a pipeline stage that helps increase the maximum operating frequency by splitting the computation across multiple clock cycles.

<p align="center">
  <img  src="https://github.com/user-attachments/assets/683ffa3c-7e28-4c99-b57a-a866e7ac753d" style="width: 80%; height: auto;">
</p>

The above is (part of) a generated schematic from my architecture, you can observe three distinct “chains” or “ladders” of multipliers and adders, one chain per path. Each ladder corresponds to one set of shift registers (for one of the parallel inputs) feeding into multipliers and then into an adder tree. 
The diagonal or stepped structure in the schematic visually illustrates the shifting of data through each path over time, and the separate multiplier-accumulator blocks confirm that multiple data samples are being processed in parallel. 
Additionally, the final registers at the outputs demonstrate the pipeline stage, as they store the computed results before the next set of inputs is processed, confirming pipelining.

### <ins> Testbench </ins>
Four different testbenches are used to test the four different implemententation, however the essense of it reamins the same. A frequency sweep is achieved by incrementally increasing the phase of a sine wave on every sample. Specifically, the instantaneous frequency starts at 0 and steps up to 0.4π in small increments, so the sine wave’s phase (phase) keeps accumulating and moving the signal’s frequency from near DC (0 rad/sample) to higher frequencies. The resulting sinusoid is scaled to 0.9 (to avoid overflow) and then converted into a 16-bit Q1.15 fixed-point value (x_in). 
This input makes sense because a sweeping sine wave exercises the filter across a broad frequency range, revealing how well the filter passes or attenuates signals at different frequencies. By observing the output ```y_out``` as the input frequency varies, you can clearly see the filter’s passband, transition region, and stopband behavior in one test.

## Hardware Implementation Results

###  <ins> Behavioral Simulation Results

| Pipelined             |  Parallelized L = 2 | 
:-------------------------:|:-------------------------:
![](https://github.com/user-attachments/assets/87bb12c7-12fa-437c-a603-2b23dea74306)  |  ![](https://github.com/user-attachments/assets/a4770471-7e5e-4391-a1b8-f252234e2432) |  

| Parallelized L = 3           |  Pipelined & Parallelized L = 3 |
:-------------------------:|:-------------------------:
![](https://github.com/user-attachments/assets/92a6ccf9-594c-47b8-94ee-da1408b6619c)  |  ![](https://github.com/user-attachments/assets/7f13af68-131a-4525-84f3-a0b49e71d006) | 

The table confirms that the filters operate as designed. Although the cutoff frequency isn’t explicitly shown in the figure, a separate printed table confirms that the filters function as intended, with a measured cutoff frequency around `0.722147` (approximately 0.23 π), which aligns well with the originally targeted transition region.

### <ins> Area Utilization </ins>

|  | LUTs     | FFs | DSP Blocks | I/O Pins |
|----------------|-----------------|-----------------|-----------------|-----------------|
| Pipelined      | 2540     | 2540     |173 | 52 |
| Parallelized L = 2 | 34| 2848 | 173 |  98|
| Parallelized L = 3 | 49| 2739 | 170 |  146|
| Pipelined & Parallelized L = 3 | 1743| 1632 | 90 |  146|

Across the four FIR filter implementations, the primary resources to compare are LUTs, flip-flops, DSP48E1 blocks, and I/O pins. 
- The pipelined filter uses 2540 LUTs, 2540 FFs, and 173 DSP blocks, which means it relies heavily on DSP slices for arithmetic and a moderate number of LUTs/registers for pipelining logic.
- The L = 2 and L = 3 parallelized designs each also consume around 170+ DSPs but need very few LUTs (34 and 49, respectively). This shows that most of the arithmetic is being performed directly in DSP blocks, but they use more registers for parallel data paths.
- The pipelined + parallel design has balance, with 1743 LUTs and only 90 DSP blocks, which shows that more logic is implemented in LUTs, and fewer DSP blocks are shared across pipeline stages.

### <ins> Power Estimation</ins> 

| Pipelined             |  Parallelized L = 2 | 
:-------------------------:|:-------------------------:
![](https://github.com/user-attachments/assets/bd9b0bd7-709a-417a-822d-b0a52cb13fdd)  |  ![](https://github.com/user-attachments/assets/59a1f6ed-cf5e-4c5c-8132-280de96f9017) |  

|Parallelized L = 3             |  Pipelined & Parallelized L = 3 |
:-------------------------:|:-------------------------:
![](https://github.com/user-attachments/assets/c4a38b3d-6996-4e35-8d02-7e3e4abef679)  |  ![](https://github.com/user-attachments/assets/bdf61b1a-52aa-4e26-ad5c-5ed054b4b553) | 

These results show how both pipelining and parallelization can change the power profile of a FIR filter. 
Pipelining divides the filter’s arithmetic into smaller stages, improving performance by shortening the critical path, but it adds overhead for extra registers. 
Parallelization processes multiple inputs simultaneously, reducing the clock rate needed for a given throughput but slightly increasing the hardware area. 
From the table, the design that combines pipelining and parallelization (Pipelined & Parallelized L=3) achieves the lowest overall power consumption (0.138 W). This shows that, although parallelization and pipelining both introduce some additional logic, the combined effect optimizes the trade-offs between clock speed, throughput, and dynamic power.

### <ins> Timing Report: Metrics

|  | Worst Negative Slack     | Total Negative Slack (TNS) | Failing Endpoints |Timing Met? |
|----------------|-----------------|-----------------|-----------------|-----------------|
| Pipelined      | 	2.324 ns     | 0 ns |0 | Yes|
| Parallelized L = 2      | –112.87 ns    | –7165.55 ns|64 | No|
| Parallelized L = 3      | 	–65.51 ns     | –9359.27 ns | 144 | No |
| Pipelined & Parallelized L = 3   | 10.03 ns     |0ns |0 | Yes|

Both the original pipelined filter and the combined pipelined/L = 3 design meet the timing constraints, with the latter providing an even better slack margin (10.03 ns vs. 2.324 ns).
The pure L = 2 and L = 3 parallelized filters have significant timing violations. Their negative slacks and high total negative slack values indicate that without additional pipelining or restructuring, the parallel paths introduce too much delay for the 20 ns clock period.
The combined approach (pipelining together with parallelism) seems to be an effective strategy to maintain the benefits of parallel processing while ensuring timing closure.The additional pipelining appears to have reduced the critical path delays significantly, providing a much larger margin than even the original pipelined filter.

## Further Insights

### Retiming

Retiming is a method used to improve timing by shifting registers. This breaks down long paths of combinational logic into shorter ones.
In the combined pipelined + L = 3 filter, the timing report shows a major improvement in the critical path. For example, the path from `shift_reg2_reg[10][15]/C` to `y2_reg[29]/D` has a short delay of only 9.852 ns and a positive slack of +10.03 ns. This indicates retiming was effective: registers were moved to split the longer logic paths found in pure parallel designs into shorter segments.
As a result, logic delays are reduced, helping the design meet the required 20 ns clock period. Additionally, retiming improves how logic elements are placed, which reduces wiring congestion. These combined benefits allow the design to satisfy timing constraints. This contrasts with the standalone L = 2 and L = 3 filters, where retiming was not applied as effectively.

### Routing

Routing delay is the delay caused by the wires connecting logic elements in a design.
In the timing reports for the parallel filters with L = 2 and L = 3, a large part of the delay is due to routing. For example, in the L = 3 filter, the critical path from `shift_reg1_reg[56][15]/C` to `y10__54/PCIN[0]` has a total delay of 84.158 ns. This path has a large negative slack of –65.51 ns, indicating severe timing issues. This clearly shows that delays from wires and connections significantly affect overall performance, not just the logic elements.
Routing delays often result from crowded wiring areas, long wires, or poor placement of components. These issues make it hard for the design to meet timing constraints. Other designs have less routing delay, but pure parallel designs consistently face this bottleneck.

### Throughput

The throughput of FIR filters depends on two primary factors: parallelism, which is how many samples can be processed simultaneously per clock cycle, and pipelining, which determines how quickly the clock can run. A pipelined filter improves performance by dividing computations into multiple stages, thereby shortening the critical path and allowing higher clock frequencies.
Designs with parallelization levels of L = 2 and L = 3 naturally increase throughput by processing two or three samples simultaneously. However, purely parallel designs tend to create longer critical paths, limiting their maximum operating frequency. As shown in the reports, these purely parallel architectures heavily use DSP blocks but struggle to meet timing constraints due to extensive combinational logic and increased routing complexity.
In contrast, the pipelined and parallel (L = 3) approach merges multiple data paths with additional pipeline stages. This combination effectively shortens critical paths, enabling a higher operating frequency. Despite using fewer DSP blocks (around 90 compared to over 170 in purely parallel implementations), this hybrid design achieves high throughput by balancing parallel processing, pipelining, and retiming techniques.

## Conclusion

This project aimed to design, implement, and evaluate an FIR filter with specific parameters using different FPGA architectures involving pipelining and parallelization. Initially, MATLAB was used to design a low-pass filter that met all the required specifications, although quantization introduced slight deviations in the frequency response.

Four FPGA implementations were tested: pipelined, parallelized (L=2), parallelized (L=3), and a combined pipelined-parallelized (L=3) structure. Among these, the combined pipelined-parallelized design provided the best results, achieving the lowest power consumption (0.138 W) and significantly better timing performance (10.03 ns positive slack). This approach efficiently balanced hardware resources like LUTs, flip-flops, and DSP blocks by using retiming techniques to reduce critical path delays.

On the other hand, purely parallel designs (L=2 and L=3) faced significant timing issues due to increased routing complexity and longer logic paths, making them impractical without additional optimization. The pipelined-only architecture met timing constraints but consumed more power and resources compared to the combined approach.

Quantization effects were also studied, showing that FIR filters remain stable despite minor rounding errors. Overflow issues were effectively managed using arithmetic shifts and rounding techniques.

Overall, combining pipelining with parallel processing proved most effective for achieving good performance, balancing throughput, resource use, timing, and power. Future studies could focus on further optimization strategies to improve purely parallel architectures, particularly addressing their routing delays and timing challenges.



