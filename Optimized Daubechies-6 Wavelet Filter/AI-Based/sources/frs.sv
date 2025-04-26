`timescale 1ns / 1ps
// frs.sv
// Final Reconstruction Stage (FRS) for Daub-6 Filter
// This module takes 4 inputs and reconstructs the final output signal.
// For demonstration, it adds the four inputs and then normalizes (divides by 4).
module frs #(
  parameter DATA_WIDTH = 16
)(
  input  logic signed [DATA_WIDTH-1:0] in0,
  input  logic signed [DATA_WIDTH-1:0] in1,
  input  logic signed [DATA_WIDTH-1:0] in2,
  input  logic signed [DATA_WIDTH-1:0] in3,
  output logic signed [DATA_WIDTH-1:0] out
);

  // Simple sum and normalization.
  assign out = (in0 + in1 + in2 + in3) >>> 2;

endmodule
