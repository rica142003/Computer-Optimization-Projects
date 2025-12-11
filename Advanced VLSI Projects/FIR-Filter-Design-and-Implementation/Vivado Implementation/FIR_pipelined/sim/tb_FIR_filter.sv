`timescale 1ns/1ps

module tb_fir_filter;

  //----------------------------------------------------------------
  // Parameters
  //----------------------------------------------------------------
  localparam CLK_PERIOD     = 20;  // 20 ns
  localparam integer TOTAL_SAMPLES = 1000;
  localparam real PI         = 3.14159265358979;

  // Frequency sweep parameters in rad/sample
  localparam real freq_start = 0 * PI;
  localparam real freq_end   =  0.4 * PI;
  localparam real freq_incr  = (freq_end - freq_start) / TOTAL_SAMPLES;

  //----------------------------------------------------------------
  // DUT Signals
  //----------------------------------------------------------------
  logic               clk;
  logic               rst_n;
  logic signed [15:0] x_in;
  logic               x_valid;
  logic signed [31:0] y_out;
  logic               y_valid;

  //----------------------------------------------------------------
  // FIR Filter Instantiation
  //----------------------------------------------------------------
  fir_filter #(
      .TAPS(175)
  ) dut (
      .clk    (clk),
      .rst_n  (rst_n),
      .x_in   (x_in),
      .x_valid(x_valid),
      .y_out  (y_out),
      .y_valid(y_valid)
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
  // Generate a continuous frequency sweep
  //----------------------------------------------------------------
  initial begin
    // Declare local variables here, inside the initial block,
    // so there's no scope issue. 
    automatic real phase   = 0.0;
    automatic real freq    = 0.0;
    real real_sample;
    int  int_sample;

    // Wait for reset
    @(posedge rst_n);

    // Drive x_valid continuously
    x_valid = 1'b0;
    @(posedge clk);

    for (int n = 0; n < TOTAL_SAMPLES; n++) begin
      // Compute instantaneous frequency
      freq = freq_start + (freq_incr * n);
    
      // Accumulate phase
      phase = phase + freq;

      // Sinusoid in Q1.15 format
      real_sample = 0.9 * $sin(phase);
      int_sample  = $floor(real_sample * 32767.0);

      x_in    = int'(int_sample);
      x_valid = 1'b1;
      
      $display("Time=%t, freq=%f (rad/sample), n=%d",$time, freq, n);

      @(posedge clk);
    end

    // After sweep, stop driving valid
    x_valid = 1'b0;
    repeat (20) @(posedge clk);
    
    $stop;
  end

endmodule
