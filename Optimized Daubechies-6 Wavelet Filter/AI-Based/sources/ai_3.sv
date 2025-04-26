`timescale 1ns / 1ps

module ai_3 #(
  parameter DATA_WIDTH = 16,
  parameter SHIFT = 5  // adjust as needed for normalization
)(
  input  logic clk,
  input  logic rst,
  input  logic signed [DATA_WIDTH-1:0] in,
  output logic signed [DATA_WIDTH-1:0] out0, // h1: low pass branch
  output logic signed [DATA_WIDTH-1:0] out1, // hx: high pass branch (phase 1)
  output logic signed [DATA_WIDTH-1:0] out2  // hy: high pass branch (phase 2)
);
  // 6-tap delay line for input data
  logic signed [15:0] delay_line [5:0];

  // Coefficients for each filter component
  // h1 coefficients [4, 8, 4, 4, 8, 4]
  localparam logic signed [15:0] h1_coeffs [5:0] = '{4, 8, 4, 4, 8, 4};
  
  // hζ1 coefficients [1, 1, -2, -2, 1, 1]
  localparam logic signed [15:0] hz1_coeffs [5:0] = '{1, 1, -2, -2, 1, 1};
  
  // hζ2 coefficients [1, 3, 2, -2, -3, -1]
  localparam logic signed [15:0] hz2_coeffs [5:0] = '{1, 3, 2, -2, -3, -1};

  // Intermediate product arrays (wider to hold the multiplication results)
  logic signed [31:0] h1_products [5:0];
  logic signed [31:0] hz1_products [5:0];
  logic signed [31:0] hz2_products [5:0];

  // Summation registers
  logic signed [31:0] h1_sum;
  logic signed [31:0] hz1_sum;
  logic signed [31:0] hz2_sum;

  // Update delay line on each clock cycle or reset
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      // Clear delay line element-by-element
      integer i;
      for (i = 0; i < 6; i = i + 1) begin
        delay_line[i] <= 0;
      end
    end else begin
      integer i;
      // Shift data through the delay line; newest sample at index 0
      for (i = 5; i > 0; i = i - 1) begin
        delay_line[i] <= delay_line[i-1];
      end
      delay_line[0] <= in;
    end
  end

  // Compute products based on current delay_line values and corresponding coefficients
  always_comb begin
    integer i;
    for (i = 0; i < 6; i = i + 1) begin
      h1_products[i]  = delay_line[i] * h1_coeffs[i];
      hz1_products[i] = delay_line[i] * hz1_coeffs[i];
      hz2_products[i] = delay_line[i] * hz2_coeffs[i];
    end
  end

  // Sum the products on every clock cycle (or reset), using nonblocking assignments
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      h1_sum  <= 0;
      hz1_sum <= 0;
      hz2_sum <= 0;
    end else begin
      h1_sum  <= h1_products[0] + h1_products[1] + h1_products[2] +
                 h1_products[3] + h1_products[4] + h1_products[5];
      hz1_sum <= hz1_products[0] + hz1_products[1] + hz1_products[2] +
                 hz1_products[3] + hz1_products[4] + hz1_products[5];
      hz2_sum <= hz2_products[0] + hz2_products[1] + hz2_products[2] +
                 hz2_products[3] + hz2_products[4] + hz2_products[5];
    end
  end

  // Assign outputs with fixed-point scaling by right shifting the result by 15 bits
  assign out0  = h1_sum[15:0];
  assign out1 = hz1_sum[15:0];
  assign out2 = hz2_sum[15:0];

endmodule
