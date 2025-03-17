module fir_filter #(
    parameter TAPS = 175  // Number of FIR taps
)(
    input  logic              clk,
    input  logic              rst_n,      // Active-low reset
    input  logic signed [15:0] x_in,       // Q1.15 input sample
    input  logic              x_valid,     // Valid input sample flag
    output logic signed [31:0] y_out,      // Q1.15 result (or Q2.30 in multiply-accumulate form)
    output logic              y_valid      // Valid output flag
);

    // -----------------------------------------------------
    // 1) Coefficients storage
    // -----------------------------------------------------
    logic signed [15:0] coeffs [0:TAPS-1] = '{
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
        16'h0001, 16'h0017, 16'h001F, 16'h001D, 16'h0015, 16'h000C, 16'h0005
    };

    // -----------------------------------------------------
    // 2) Data Shift Register (Delay Line)
    // -----------------------------------------------------
    logic signed [15:0] data_pipe [0:TAPS-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < TAPS; i++)
                data_pipe[i] <= '0;
        end
        else if (x_valid) begin
            data_pipe[0] <= x_in;
            for (int i = 1; i < TAPS; i++)
                data_pipe[i] <= data_pipe[i-1];
        end
    end

    // -----------------------------------------------------
    // 3) Multiply-Accumulate (MAC) Logic
    // -----------------------------------------------------
    logic signed [31:0] mac;

    always_comb begin
        mac = 32'sd0;
        for (int i = 0; i < TAPS; i++) begin
            (* use_dsp = "yes" *) 
            automatic logic signed [31:0] product = data_pipe[i] * coeffs[i];
            mac += product;
        end
    end

    // -----------------------------------------------------
    // 4) Output Pipeline Register
    // -----------------------------------------------------

    parameter integer SHIFT_AMT = 8; 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_out   <= 32'sd0;
            y_valid <= 1'b0;
        end
        else begin
            //y_out   <= mac;
            y_valid <= x_valid;
            y_out <= (mac + (32'sd1 << (SHIFT_AMT-1))) >>> SHIFT_AMT;
        end
    end


endmodule
