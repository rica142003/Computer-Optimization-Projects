`timescale 1ns/1ps

module tb_daub6_top_full;
  // Parameter definition matching the DUT.
  parameter DATA_WIDTH = 16;

  // Declare test bench signals.
  logic clk;
  logic rst;
  logic signed [DATA_WIDTH-1:0] in;
  logic signed [DATA_WIDTH-1:0] out;

  // Instantiate the DUT (Device Under Test) without any import or export ports.
  daub6_top_full #(.DATA_WIDTH(DATA_WIDTH)) uut (
    .clk(clk),
    .rst(rst),
    .in(in),
    .out(out)
  );

  // Generate a clock signal with a period of 10 ns.
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Optionally, create a VCD file for waveform viewing.
  initial begin
    $dumpfile("tb_daub6_top_full.vcd");
    $dumpvars(0, tb_daub6_top_full);
  end

  // Stimulus: apply reset, then drive random input values and display outputs.
  initial begin
    // Start with a reset.
    rst = 1;
    in  = 0;
    #20;  // Hold reset for a few clock cycles.

    rst = 0;  // Release reset.
    $display("Time\t\tInput\tOutput");
    $display("--------------------------------");
    
    // Apply a series of test inputs.
    repeat (20) begin
      // Assign a new random input value.
      in = $urandom_range(-32768, 32767); // Using a range appropriate for 16-bit signed data.
      
      // Wait one clock cycle for processing.
      @(posedge clk);
      // Optionally, wait a little more (if the DUT has pipelined behavior).
      #1;
      
      // Display time, input, and output.
      $display("%0t\t%0d\t%0d", $time, in, out);
    end

    $display("Simulation finished.");
    $finish;
  end

endmodule
