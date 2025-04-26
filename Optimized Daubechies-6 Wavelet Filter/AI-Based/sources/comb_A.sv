`timescale 1ns / 1ps
// comb_A.sv
// Combinational Block A for Daub-6 filter (Method 1)
// 9 inputs, 4 outputs. Uses small-integer scaling (6, 11, 2) as in Fig. (a).
// Each of the top three adders is labeled with one of these constants. The
// bottom adder is unlabeled and sums the partial sum from the top-left adder.

module comb_A #(
  parameter DATA_WIDTH = 16
)(
  input  logic signed [DATA_WIDTH-1:0] in0,
  input  logic signed [DATA_WIDTH-1:0] in1,
  input  logic signed [DATA_WIDTH-1:0] in2,
  input  logic signed [DATA_WIDTH-1:0] in3,
  input  logic signed [DATA_WIDTH-1:0] in4,
  input  logic signed [DATA_WIDTH-1:0] in5,
  input  logic signed [DATA_WIDTH-1:0] in6,
  input  logic signed [DATA_WIDTH-1:0] in7,
  input  logic signed [DATA_WIDTH-1:0] in8,

  output logic signed [DATA_WIDTH-1:0] out0,  // top-right adder output (labeled "2" in figure)
  output logic signed [DATA_WIDTH-1:0] out1,  // middle adder output (labeled "11")
  output logic signed [DATA_WIDTH-1:0] out2,  // left adder output (labeled "6")
  output logic signed [DATA_WIDTH-1:0] out3   // bottom adder output (unlabeled)
);

  // Helper functions using only shifts and adds:
  function automatic logic signed [DATA_WIDTH-1:0] mul6(
    input logic signed [DATA_WIDTH-1:0] x
  );
    // 6 = 2 + 4
    return ((x <<< 1) + (x <<< 2));
  endfunction

  function automatic logic signed [DATA_WIDTH-1:0] mul11(
    input logic signed [DATA_WIDTH-1:0] x
  );
    // 11 = 1 + 2 + 8
    return (x + (x <<< 1) + (x <<< 3));
  endfunction

  function automatic logic signed [DATA_WIDTH-1:0] mul2(
    input logic signed [DATA_WIDTH-1:0] x
  );
    // 2 = 1 << 1
    return (x <<< 1);
  endfunction

  // Intermediate adder outputs:
  logic signed [DATA_WIDTH-1:0] a0;  // top-left adder (coefficient 6)
  logic signed [DATA_WIDTH-1:0] a1;  // top-middle adder (coefficient 11)
  logic signed [DATA_WIDTH-1:0] a2;  // top-right adder (coefficient 2)
  logic signed [DATA_WIDTH-1:0] a3;  // bottom adder (unlabeled)

  // Top-left adder: in0 + in1 + 6*in2
  assign a0 = in0 + in1 + mul6(in2);

  // Top-middle adder: a0 + 11*in3
  assign a1 = a0 + mul11(in3);

  // Top-right adder: a1 + 2*in4
  assign a2 = a1 + mul2(in4);

  // Bottom adder: a0 + in5 + in6 + in7 + in8
  assign a3 = a0 + in5 + in6 + in7 + in8;

  // Map the adder outputs to module outputs as shown in the figure:
  assign out2 = a0;  // leftmost top adder
  assign out1 = a1;  // middle top adder
  assign out0 = a2;  // rightmost top adder
  assign out3 = a3;  // bottom adder

endmodule
