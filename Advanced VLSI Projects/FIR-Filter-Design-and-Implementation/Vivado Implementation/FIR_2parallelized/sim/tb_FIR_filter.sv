`timescale 1ns/1ps

module tb_fir_filter_2path;

  //----------------------------------------------------------------
  // Parameters
  //----------------------------------------------------------------
  localparam CLK_PERIOD = 20;           // 20 ns clock period
  localparam integer TOTAL_SAMPLES = 2000; // Total number of chirp samples (must be even)
  localparam real PI = 3.14159265358979;

  // Since the filter processes two samples per clock, the number of clock cycles:
  localparam integer NUM_CLOCKS = TOTAL_SAMPLES / 2;

  // Frequency sweep parameters in rad/sample
  localparam real freq_start = 0 * PI;
  localparam real freq_end   = 0.4 * PI;
  localparam real freq_incr  = (freq_end - freq_start) / TOTAL_SAMPLES;

  //----------------------------------------------------------------
  // DUT Signals
  //----------------------------------------------------------------
  logic                   clk;
  logic                   rst_n;
  logic signed [15:0]     x_even;
  logic signed [15:0]     x_odd;
  logic signed [31:0]     y_even;
  logic signed [31:0]     y_odd;

  //----------------------------------------------------------------
  // DUT Instantiation: Use your two-path FIR filter with NUM_TAPS = 200
  //----------------------------------------------------------------
  fir_filter_2path #(
      .NUM_TAPS(174)
  ) dut (
      .clk    (clk),
      .rst_n  (rst_n),
      .x_even (x_even),
      .x_odd  (x_odd),
      .y_even (y_even),
      .y_odd  (y_odd)
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
  // Generate a "Chirp" (continuous frequency sweep)
  // Produce interleaved even and odd samples on consecutive clock cycles.
  //----------------------------------------------------------------
  initial begin
    automatic real phase = 0.0;
    automatic real freq;
    real real_sample;
    int int_sample;

    // Wait for reset deassertion
    @(posedge rst_n);

    // Generate NUM_CLOCKS cycles, each cycle producing two samples.
    // The overall chirp will consist of TOTAL_SAMPLES points.
    for (int i = 0; i < NUM_CLOCKS; i++) begin
      // Generate even-index sample for x_even (index = 2*i)
      freq = freq_start + (freq_incr * (2*i));
      phase = phase + freq;
      real_sample = 0.9 * $sin(phase);
      int_sample = $floor(real_sample * 32767.0);
      x_even = int'(int_sample);

      // Generate odd-index sample for x_odd (index = 2*i + 1)
      freq = freq_start + (freq_incr * (2*i + 1));
      phase = phase + freq;
      real_sample = 0.9 * $sin(phase);
      int_sample = $floor(real_sample * 32767.0);
      x_odd = int'(int_sample);

      // Optionally, display input and output values at each clock edge.
      $display("Time=%t, freq=%d", 
               $time, freq);

      @(posedge clk);
    end

    // After the chirp, drive inputs to zero and let the filter flush out remaining data.
    x_even = 16'sd0;
    x_odd  = 16'sd0;
    repeat (20) @(posedge clk);

    $stop;
  end

endmodule
