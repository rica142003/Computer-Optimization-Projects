`timescale 1ns/1ps

module tb_fir_filter;

  localparam CLK_PERIOD     = 20;  
  localparam integer TOTAL_GROUPS = 1000;
  // Total number of samples = groups * 3
  localparam integer TOTAL_SAMPLES = TOTAL_GROUPS * 3;
  localparam real PI         = 3.14159265358979;
  
  // Frequency sweep parameters in rad/sample
  localparam real freq_start = 0 * PI;
  localparam real freq_end   = 0.4 * PI;
  // Frequency increment per sample 
  localparam real freq_incr  = (freq_end - freq_start) / TOTAL_SAMPLES;

  //----------------------------------------------------------------
  // DUT Signals
  //----------------------------------------------------------------
  logic               clk;
  logic               rst_n;
  logic signed [15:0] x0, x1, x2;
  logic signed [31:0] y0, y1, y2;

  //----------------------------------------------------------------
  // FIR Filter Instantiation
  //----------------------------------------------------------------
  fir_filter_3path_parallel #(
    .NUM_TAPS(171)
  ) dut (
    .clk   (clk),
    .rst_n (rst_n),
    .x0    (x0),
    .x1    (x1),
    .x2    (x2),
    .y0    (y0),
    .y1    (y1),
    .y2    (y2)
  );

  //----------------------------------------------------------------
  // Clock Generation
  //----------------------------------------------------------------
  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  //----------------------------------------------------------------
  // Reset Logic
  //----------------------------------------------------------------
  initial begin
    rst_n = 1'b0;
    #(5 * CLK_PERIOD);
    rst_n = 1'b1;
  end

  //----------------------------------------------------------------
  // Generate a continuous frequency sweep and split into 3 paths
  //----------------------------------------------------------------
  initial begin
    // Local variables for phase accumulation and sample generation.
    automatic real phase = 0.0;
    automatic real freq;
    real real_sample;
    int  int_sample;
    int  sample_index;

    // Wait for reset release
    @(posedge rst_n);

    // Loop over groups; each group drives one sample on each of x0, x1, and x2.
    for (int group = 0; group < TOTAL_GROUPS; group++) begin
      // First sample for channel x0, sample index = group*3
      sample_index = group * 3;
      freq = freq_start + (freq_incr * sample_index);
      real_sample = 0.9 * $sin(phase);
      int_sample  = $floor(real_sample * 32767.0);
      x0 = int'(int_sample);
      phase = phase + freq;

      // Second sample for channel x1, sample index = group*3 + 1
      sample_index = group * 3 + 1;
      freq = freq_start + (freq_incr * sample_index);
      real_sample = 0.9 * $sin(phase);
      int_sample  = $floor(real_sample * 32767.0);
      x1 = int'(int_sample);
      phase = phase + freq;

      // Third sample for channel x2, sample index = group*3 + 2
      sample_index = group * 3 + 2;
      freq = freq_start + (freq_incr * sample_index);
      real_sample = 0.9 * $sin(phase);
      int_sample  = $floor(real_sample * 32767.0);
      x2 = int'(int_sample);
      phase = phase + freq;
      
      $display("Time=%t: y0=%0d, y1=%0d, y2=%0d, freq=%f", $time, y0, y1, y2, freq);
      
      // Wait one clock cycle before the next group of three samples.
      @(posedge clk);
    end

    $stop;
  end
endmodule
