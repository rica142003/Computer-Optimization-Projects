module fir_filter_3path_parallel #(
    parameter integer NUM_TAPS = 171  // Must be multiple of 3
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // Three parallel 16-bit sample inputs (Q1.15):
    // x0 => x(3k), x1 => x(3k+1), x2 => x(3k+2)
    input  logic signed [15:0]     x0,
    input  logic signed [15:0]     x1,
    input  logic signed [15:0]     x2,

    // Three parallel 32-bit outputs:
    // y0 => y(3k), y1 => y(3k+1), y2 => y(3k+2)
    output logic signed [31:0]     y0,
    output logic signed [31:0]     y1,
    output logic signed [31:0]     y2
);

    // -------------------------------------------------------
    // 1) Coefficients (Q1.15). We split them into 3 sets:
    //    coeffs0 => indices 0,3,6,...
    //    coeffs1 => indices 1,4,7,...
    //    coeffs2 => indices 2,5,8,...
    // -------------------------------------------------------
    localparam int SUB_TAPS = NUM_TAPS / 3;
    parameter integer SHIFT_AMT = 8; 

    localparam logic signed [15:0] COEFFS [0:NUM_TAPS-1] = '{
        16'h0005, 16'h000C, 16'h0015, 16'h001D, 16'h001F, 16'h0017, 16'h0001, 16'hFFDB,
        16'hFFAA, 16'hFF76, 16'hFF4B, 16'hFF37, 16'hFF40, 16'hFF69, 16'hFFA9, 16'hFFF0,
        16'h002B, 16'h004B, 16'h0047, 16'h0023, 16'hFFED, 16'hFFBC, 16'hFFA3, 16'hFFAD,
        16'hFFD8, 16'h0013, 16'h0048, 16'h0061, 16'h0052, 16'h001F, 16'hFFDC, 16'hFFA4,
        16'hFF8F, 16'hFFA8, 16'hFFE9, 16'h0038, 16'h0075, 16'h0084, 16'h005C, 16'h0009,
        16'hFFAD, 16'hFF6D, 16'hFF67, 16'hFFA3, 16'h000B, 16'h0077, 16'h00B8, 16'h00AF,
        16'h005A, 16'hFFD7, 16'hFF5B, 16'hFF1C, 16'hFF39, 16'hFFB0, 16'h0053, 16'h00E1,
        16'h011A, 16'h00DD, 16'h003B, 16'hFF70, 16'hFED0, 16'hFEA5, 16'hFF0D, 16'hFFEB,
        16'h00E9, 16'h019D, 16'h01B0, 16'h0106, 16'hFFD4, 16'hFE8F, 16'hFDC3, 16'hFDD9,
        16'hFEEA, 16'h00A2, 16'h0259, 16'h034E, 16'h02EF, 16'h0122, 16'hFE63, 16'hFBB1,
        16'hFA44, 16'hFB28, 16'hFED6, 16'h04FC, 16'h0C7C, 16'h13B1, 16'h18E2, 16'h1AC6,
        16'h18E2, 16'h13B1, 16'h0C7C, 16'h04FC, 16'hFED6, 16'hFB28, 16'hFA44, 16'hFBB1,
        16'hFE63, 16'h0122, 16'h02EF, 16'h034E, 16'h0259, 16'h00A2, 16'hFEEA, 16'hFDD9,
        16'hFDC3, 16'hFE8F, 16'hFFD4, 16'h0106, 16'h01B0, 16'h019D, 16'h00E9, 16'hFFEB,
        16'hFF0D, 16'hFEA5, 16'hFED0, 16'hFF70, 16'h003B, 16'h00DD, 16'h011A, 16'h00E1,
        16'h0053, 16'hFFB0, 16'hFF39, 16'hFF1C, 16'hFF5B, 16'hFFD7, 16'h005A, 16'h00AF,
        16'h00B8, 16'h0077, 16'h000B, 16'hFFA3, 16'hFF67, 16'hFF6D, 16'hFFAD, 16'h0009,
        16'h005C, 16'h0084, 16'h0075, 16'h0038, 16'hFFE9, 16'hFFA8, 16'hFF8F, 16'hFFA4,
        16'hFFDC, 16'h001F, 16'h0052, 16'h0061, 16'h0048, 16'h0013, 16'hFFD8, 16'hFFAD,
        16'hFFA3, 16'hFFBC, 16'hFFED, 16'h0023, 16'h0047, 16'h004B, 16'h002B, 16'hFFF0,
        16'hFFA9, 16'hFF69, 16'hFF40, 16'hFF37, 16'hFF4B, 16'hFF76, 16'hFFAA, 16'hFFDB,
        16'h0001, 16'h0017, 16'h001F
    };

    logic signed [15:0] coeffs0 [0:SUB_TAPS-1];
    logic signed [15:0] coeffs1 [0:SUB_TAPS-1];
    logic signed [15:0] coeffs2 [0:SUB_TAPS-1];

    initial begin
        for (int i = 0; i < SUB_TAPS; i++) begin
            coeffs0[i] = COEFFS[3*i];
            coeffs1[i] = COEFFS[3*i + 1];
            coeffs2[i] = COEFFS[3*i + 2];
        end
    end

    // -------------------------------------------------------
    // 2) Shift registers for each branch:
    //    shift_reg0 => x(3k) path
    //    shift_reg1 => x(3k+1) path
    //    shift_reg2 => x(3k+2) path
    // -------------------------------------------------------
    logic signed [15:0] shift_reg0 [0:SUB_TAPS-1];
    logic signed [15:0] shift_reg1 [0:SUB_TAPS-1];
    logic signed [15:0] shift_reg2 [0:SUB_TAPS-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < SUB_TAPS; i++) begin
                shift_reg0[i] <= '0;
                shift_reg1[i] <= '0;
                shift_reg2[i] <= '0;
            end
        end
        else begin
            // Shift for path 0
            for (int i = SUB_TAPS-1; i > 0; i--) begin
                shift_reg0[i] <= shift_reg0[i-1];
            end
            shift_reg0[0] <= x0;

            // Shift for path 1
            for (int i = SUB_TAPS-1; i > 0; i--) begin
                shift_reg1[i] <= shift_reg1[i-1];
            end
            shift_reg1[0] <= x1;

            // Shift for path 2
            for (int i = SUB_TAPS-1; i > 0; i--) begin
                shift_reg2[i] <= shift_reg2[i-1];
            end
            shift_reg2[0] <= x2;
        end
    end

    // -------------------------------------------------------
    // 3) Parallel multiplications:
    //    product0[i] = shift_reg0[i] * coeffs0[i]
    //    product1[i] = shift_reg1[i] * coeffs1[i]
    //    product2[i] = shift_reg2[i] * coeffs2[i]
    // -------------------------------------------------------
    wire signed [31:0] product0 [0:SUB_TAPS-1];
    wire signed [31:0] product1 [0:SUB_TAPS-1];
    wire signed [31:0] product2 [0:SUB_TAPS-1];

    generate
        for (genvar i = 0; i < SUB_TAPS; i++) begin : gen_mult
            assign product0[i] = shift_reg0[i] * coeffs0[i];
            assign product1[i] = shift_reg1[i] * coeffs1[i];
            assign product2[i] = shift_reg2[i] * coeffs2[i];
        end
    endgenerate

    // -------------------------------------------------------
    // 4) Parallel Adder Tree:
    //    Instead of a function with dynamic arrays, we use
    //    a generate-based approach that creates a "tree" of
    //    adders at compile time. This avoids errors about
    //    non-constant ranges.
    // -------------------------------------------------------

    // Helper module that sums N 32-bit values in a tree.
    wire signed [31:0] sum0, sum1, sum2;

    parallel_adder_tree #(.N(SUB_TAPS)) adder_tree0 (
        .in  (product0),
        .out (sum0)
    );

    parallel_adder_tree #(.N(SUB_TAPS)) adder_tree1 (
        .in  (product1),
        .out (sum1)
    );

    parallel_adder_tree #(.N(SUB_TAPS)) adder_tree2 (
        .in  (product2),
        .out (sum2)
    );

    // -------------------------------------------------------
    // 5) Register outputs:
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y0 <= 32'sd0;
            y1 <= 32'sd0;
            y2 <= 32'sd0;
        end else begin           
            y0 <= sum0;
            y1 <= sum1;
            y2 <= sum2;
        end
    end

endmodule
