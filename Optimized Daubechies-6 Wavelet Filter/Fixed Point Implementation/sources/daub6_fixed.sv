`timescale 1ns/1ps
// daub6_fixed.sv
// 4-stage pipelined fixed-point implementation of a Daubechies-6 filter.
// This design uses the same six Q15 coefficients as the original algebraic integer version.
// It is pipelined into 4 stages to match the original timing and latency.
module daub6_fixed #(
    // DATA_WIDTH: bit width of input and output samples (Q15 format)
    // FRACTIONAL_BITS: number of fractional bits used in Q15 fixed-point representation.
    parameter DATA_WIDTH      = 16,
    parameter FRACTIONAL_BITS = 15
)(
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic signed [DATA_WIDTH-1:0] din,   // Input sample in Q15 format
    output logic signed [DATA_WIDTH-1:0] dout   // Filtered output in Q15 format
);

    //--------------------------------------------------------------------------
    // Stage 1: Input Registration (6-tap Shift Register)
    //--------------------------------------------------------------------------
    // tap0 is the most recent sample; tap5 is the oldest.
    logic signed [DATA_WIDTH-1:0] tap0, tap1, tap2, tap3, tap4, tap5;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tap0 <= '0;
            tap1 <= '0;
            tap2 <= '0;
            tap3 <= '0;
            tap4 <= '0;
            tap5 <= '0;
        end else begin
            tap5 <= tap4;
            tap4 <= tap3;
            tap3 <= tap2;
            tap2 <= tap1;
            tap1 <= tap0;
            tap0 <= din;
        end
    end

    //--------------------------------------------------------------------------
    // Fixed-Point Coefficients (Q15 Format)
    //--------------------------------------------------------------------------
    // Coefficients computed as: round(floating_point_value * 32768)
    // The order of coefficients is:
    //   COEFF0 = 0.035226291882, COEFF1 = -0.085441273882,
    //   COEFF2 = -0.135011020010, COEFF3 = 0.459877502118,
    //   COEFF4 = 0.806891509311, COEFF5 = 0.332670552950
    localparam signed [15:0] COEFF0 = 16'sd1155;   // 0.035226291882 * 32768 ≈ 1155
    localparam signed [15:0] COEFF1 = -16'sd2796;  // -0.085441273882 * 32768 ≈ -2796
    localparam signed [15:0] COEFF2 = -16'sd4423;  // -0.135011020010 * 32768 ≈ -4423
    localparam signed [15:0] COEFF3 = 16'sd15058;  // 0.459877502118 * 32768 ≈ 15058
    localparam signed [15:0] COEFF4 = 16'sd26440;  // 0.806891509311 * 32768 ≈ 26440
    localparam signed [15:0] COEFF5 = 16'sd10898;  // 0.332670552950 * 32768 ≈ 10898

    //--------------------------------------------------------------------------
    // Stage 2: Multiplication
    //--------------------------------------------------------------------------
    // Multiply each tap sample by the corresponding coefficient.
    // The multiplication results are registered to form the next pipeline stage.
    // The product of two Q15 numbers is in Q30.
    logic signed [31:0] mult0, mult1, mult2, mult3, mult4, mult5;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mult0 <= '0;
            mult1 <= '0;
            mult2 <= '0;
            mult3 <= '0;
            mult4 <= '0;
            mult5 <= '0;
        end else begin
            mult0 <= tap0 * COEFF0;
            mult1 <= tap1 * COEFF1;
            mult2 <= tap2 * COEFF2;
            mult3 <= tap3 * COEFF3;
            mult4 <= tap4 * COEFF4;
            mult5 <= tap5 * COEFF5;
        end
    end

    //--------------------------------------------------------------------------
    // Stage 3: Accumulation and Rounding
    //--------------------------------------------------------------------------
    // The six multiplication results (in Q30) are added together.
    // A rounding offset of (1 << (FRACTIONAL_BITS-1)) is added before scaling.
    // The accumulator is 35-bit wide to capture any growth.
    logic signed [34:0] sum_stage3;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_stage3 <= '0;
        end else begin
            sum_stage3 <= mult0 + mult1 + mult2 + mult3 + mult4 + mult5 
                          + (1 << (FRACTIONAL_BITS - 1));
        end
    end

    //--------------------------------------------------------------------------
    // Stage 4: Scaling and Output Registration
    //--------------------------------------------------------------------------
    // Shift the accumulated result right by FRACTIONAL_BITS (15 bits) to convert
    // the result from Q30 back to Q15. The 20-bit intermediate result is then
    // truncated to produce the final 16-bit output.
    logic signed [19:0] filt_out_stage4;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout <= '0;
        end else begin
            filt_out_stage4 <= sum_stage3 >>> FRACTIONAL_BITS;
            // Extract the 16 MSBs out of the 20-bit result.
            dout <= filt_out_stage4[19:4];
        end
    end

endmodule
