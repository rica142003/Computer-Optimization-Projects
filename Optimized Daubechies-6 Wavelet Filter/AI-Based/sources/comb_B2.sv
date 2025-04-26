`timescale 1ns / 1ps
// comb_B2.sv
// Combinational Block B2 for Daub-6 filter (Method 1)
// 16 inputs, 4 outputs.
// Uses small "multiplier" functions (shift-add implementations):
module comb_B2 #(
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
  input  logic signed [DATA_WIDTH-1:0] in9,
  input  logic signed [DATA_WIDTH-1:0] in10,
  input  logic signed [DATA_WIDTH-1:0] in11,
  input  logic signed [DATA_WIDTH-1:0] in12,
  input  logic signed [DATA_WIDTH-1:0] in13,
  input  logic signed [DATA_WIDTH-1:0] in14,
  input  logic signed [DATA_WIDTH-1:0] in15,
  output logic signed [DATA_WIDTH-1:0] out0,
  output logic signed [DATA_WIDTH-1:0] out1,
  output logic signed [DATA_WIDTH-1:0] out2,
  output logic signed [DATA_WIDTH-1:0] out3
);

  // Define helper functions:
  function automatic logic signed [DATA_WIDTH-1:0] mul2 (logic signed [DATA_WIDTH-1:0] x);
    mul2 = x <<< 1;
  endfunction

  function automatic logic signed [DATA_WIDTH-1:0] mul6 (logic signed [DATA_WIDTH-1:0] x);
    mul6 = (x <<< 2) + (x <<< 1);
  endfunction

  function automatic logic signed [DATA_WIDTH-1:0] mul8 (logic signed [DATA_WIDTH-1:0] x);
    mul8 = x <<< 3;
  endfunction

  function automatic logic signed [DATA_WIDTH-1:0] mul11 (logic signed [DATA_WIDTH-1:0] x);
    mul11 = (x <<< 3) + (x <<< 1) + x;
  endfunction

  // In this example the outputs are directly computed as:
  always_comb begin
    out0 = mul11(in0) + mul2(in1) + mul8(in2) + mul6(in3);
    out1 = mul11(in4) + mul2(in5) + mul8(in6) + mul6(in7);
    out2 = mul11(in8) + mul2(in9) + mul8(in10) + mul6(in11);
    out3 = mul11(in12) + mul2(in13) + mul8(in14) + mul6(in15);
  end

endmodule
