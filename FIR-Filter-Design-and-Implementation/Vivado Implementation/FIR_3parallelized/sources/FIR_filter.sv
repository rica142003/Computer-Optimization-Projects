module fir_filter_3path #(
    parameter integer NUM_TAPS = 171  // Example: must be multiple of 3
)(
    input  logic                   clk,
    input  logic                   rst_n,
    
    // Three parallel 16-bit sample inputs (Q1.15)
    // x0 = x(3k), x1 = x(3k+1), x2 = x(3k+2)
    input  logic signed [15:0]     x0,
    input  logic signed [15:0]     x1,
    input  logic signed [15:0]     x2,
    
    // Three parallel 32-bit outputs
    // y0 = y(3k), y1 = y(3k+1), y2 = y(3k+2)
    output logic signed [31:0]     y0,
    output logic signed [31:0]     y1,
    output logic signed [31:0]     y2
);

    // ---------------------------------------------------------------
    // 1) Separate the total coefficients into 3 sub-filter arrays.
    //    For L=3, each sub-filter handles one of every 3 coefficients.
    // ---------------------------------------------------------------
    localparam int SUB_TAPS = NUM_TAPS / 3;

    // Example coefficient array in Q1.15 format (16 bits).
    // Replace with your actual 201 (or other multiple-of-3) values.
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

    // Sub-filter coefficient arrays:
    logic signed [15:0] coeffs0 [0:SUB_TAPS-1]; // h0 (indices 0,3,6,9,...)
    logic signed [15:0] coeffs1 [0:SUB_TAPS-1]; // h1 (indices 1,4,7,10,...)
    logic signed [15:0] coeffs2 [0:SUB_TAPS-1]; // h2 (indices 2,5,8,11,...)

    // Distribute COEFFS into the 3 arrays
    initial begin
        for (int i = 0; i < SUB_TAPS; i++) begin
            coeffs0[i] = COEFFS[3*i];
            coeffs1[i] = COEFFS[3*i + 1];
            coeffs2[i] = COEFFS[3*i + 2];
        end
    end

    // ---------------------------------------------------------------
    // 2) Shift-registers for the 3 input streams.
    //    Each sub-filter has SUB_TAPS sample delays.
    //    shift_reg0 -> stores x(3k) samples
    //    shift_reg1 -> stores x(3k+1) samples
    //    shift_reg2 -> stores x(3k+2) samples
    // ---------------------------------------------------------------
    logic signed [15:0] shift_reg0 [0:SUB_TAPS-1];
    logic signed [15:0] shift_reg1 [0:SUB_TAPS-1];
    logic signed [15:0] shift_reg2 [0:SUB_TAPS-1];

    // ---------------------------------------------------------------
    // 3) Shift in new samples each clock, if not in reset.
    //    This replicates the "D" blocks (delays) in your polyphase figure.
    // ---------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < SUB_TAPS; i++) begin
                shift_reg0[i] <= '0;
                shift_reg1[i] <= '0;
                shift_reg2[i] <= '0;
            end
        end
        else begin
            // Shift for sub-filter0 (handles x0 samples)
            for (int i = SUB_TAPS-1; i > 0; i--) begin
                shift_reg0[i] <= shift_reg0[i-1];
            end
            shift_reg0[0] <= x0;

            // Shift for sub-filter1 (handles x1 samples)
            for (int i = SUB_TAPS-1; i > 0; i--) begin
                shift_reg1[i] <= shift_reg1[i-1];
            end
            shift_reg1[0] <= x1;

            // Shift for sub-filter2 (handles x2 samples)
            for (int i = SUB_TAPS-1; i > 0; i--) begin
                shift_reg2[i] <= shift_reg2[i-1];
            end
            shift_reg2[0] <= x2;
        end
    end

    // ---------------------------------------------------------------
    // 4) Multiply-accumulate for each sub-filter path:
    //    - sub-filter0 => sum( shift_reg0[i] * coeffs0[i] )
    //    - sub-filter1 => sum( shift_reg1[i] * coeffs1[i] )
    //    - sub-filter2 => sum( shift_reg2[i] * coeffs2[i] )
    //
    //    The product is up to 32 bits (16 x 16). We sum in 32 bits.
    // ---------------------------------------------------------------
    logic signed [31:0] sum0;
    logic signed [31:0] sum1;
    logic signed [31:0] sum2;

    always_comb begin
        sum0 = 32'sd0;
        sum1 = 32'sd0;
        sum2 = 32'sd0;
        for (int i = 0; i < SUB_TAPS; i++) begin
            sum0 += shift_reg0[i] * coeffs0[i];
            sum1 += shift_reg1[i] * coeffs1[i];
            sum2 += shift_reg2[i] * coeffs2[i];
        end
    end

    // ---------------------------------------------------------------
    // 5) Register outputs. 
    //    - y0 => y(3k)
    //    - y1 => y(3k+1)
    //    - y2 => y(3k+2)
    // ---------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y0 <= 32'sd0;
            y1 <= 32'sd0;
            y2 <= 32'sd0;
        end
        else begin
            y0 <= sum0;
            y1 <= sum1;
            y2 <= sum2;
        end
    end

endmodule
