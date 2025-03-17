module fir_filter_2path #(
    parameter integer NUM_TAPS = 174
)(
    input  logic                   clk,
    input  logic                   rst_n,
    
    // Two parallel 16-bit sample inputs (Q1.15)
    // x_even = x(2k), x_odd = x(2k+1)
    input  logic signed [15:0]     x_even,
    input  logic signed [15:0]     x_odd,
    
    // Two parallel 32-bit outputs
    // y_even = y(2k), y_odd = y(2k+1)
    output logic signed [31:0]     y_even,
    output logic signed [31:0]     y_odd
);

    // ---------------------------------------------------------------
    // 1) Coefficients in Q1.15 format (16 bits). 
    //    Typically, you'd load these from a file or define them in a package.
    //    For illustration, we show a partial list and then the full array.
    // ---------------------------------------------------------------
    localparam int HALF_TAPS = NUM_TAPS / 2;

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
        16'h0001, 16'h0017, 16'h001F, 16'h001D, 16'h0015, 16'h000C
    };

    // ---------------------------------------------------------------
    // 2) Separate the coefficients into even and odd index arrays.
    //    This matches the top and bottom sub-filters in your diagram.
    // ---------------------------------------------------------------
    logic signed [15:0] coeffs_even [0:HALF_TAPS-1];
    logic signed [15:0] coeffs_odd  [0:HALF_TAPS-1];

    initial begin
        for (int i = 0; i < HALF_TAPS; i++) begin
            coeffs_even[i] = COEFFS[2*i];   // Even indices
            coeffs_odd[i]  = COEFFS[2*i+1]; // Odd indices
        end
    end

    // ---------------------------------------------------------------
    // 3) Shift-register storage for incoming samples.
    //    Instead of making reg0, reg1, etc. manually, we use arrays.
    //    - shift_reg_even[k] will store x(2k) samples over time.
    //    - shift_reg_odd[k]  will store x(2k+1) samples over time.
    //
    //    Each sub-filter uses HALF_TAPS samples from its own path.
    //    Each new sample shifts the previous values down the array.
    // ---------------------------------------------------------------
    logic signed [15:0] shift_reg_even [0:HALF_TAPS-1];
    logic signed [15:0] shift_reg_odd  [0:HALF_TAPS-1];

    // ---------------------------------------------------------------
    // Shift in new samples on each clock, if not in reset.
    // shift_reg_even[0] <= x_even
    // shift_reg_even[i] <= shift_reg_even[i-1] for i=1..HALF_TAPS-1
    // Similarly for shift_reg_odd.
    // ---------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < HALF_TAPS; i++) begin
                shift_reg_even[i] <= '0;
                shift_reg_odd[i]  <= '0;
            end
        end
        else begin
            // Shift for "even" sub-filter
            for (int i = HALF_TAPS-1; i > 0; i--) begin
                shift_reg_even[i] <= shift_reg_even[i-1];
            end
            shift_reg_even[0] <= x_even;

            // Shift for "odd" sub-filter
            for (int i = HALF_TAPS-1; i > 0; i--) begin
                shift_reg_odd[i] <= shift_reg_odd[i-1];
            end
            shift_reg_odd[0] <= x_odd;
        end
    end

    // ---------------------------------------------------------------
    // 4) Multiply-accumulate for each path:
    //    - "even path" = sum( shift_reg_even[i] * coeffs_even[i] )
    //    - "odd path"  = sum( shift_reg_odd[i]  * coeffs_odd[i]  )
    //
    //    Because each sample and coefficient is 16-bit, their product 
    //    is up to 32 bits (Q2.30). We sum into a 32-bit accumulator 
    //    for safety.  
    // ---------------------------------------------------------------
    logic signed [31:0] sum_even;
    logic signed [31:0] sum_odd;

    always_comb begin
        sum_even = 32'sd0;
        sum_odd  = 32'sd0;
        for (int i = 0; i < HALF_TAPS; i++) begin
            sum_even += shift_reg_even[i] * coeffs_even[i];
            sum_odd  += shift_reg_odd[i]  * coeffs_odd[i];
        end
    end

    // ---------------------------------------------------------------
    // 5) According to the figure, the final outputs are y(2k) and y(2k+1).
    //    Typically, you might have a small pipeline or do a final add.  
    //    In many polyphase designs, y_even and y_odd might feed 
    //    different stages or be added with delayed partial sums.
    //
    //    For simplicity, we'll directly route them out as the 
    //    partial sums of each path. 
    // ---------------------------------------------------------------
parameter integer SHIFT_AMT = 8; // Experiment with values (e.g., 12, 13, 14)

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        y_even <= 32'sd0;
        y_odd  <= 32'sd0;
    end else begin
        // Add half of 2^SHIFT_AMT for rounding, then shift right by SHIFT_AMT bits.
        y_even <= (sum_even + (32'sd1 << (SHIFT_AMT-1))) >>> SHIFT_AMT;
        y_odd  <= (sum_odd  + (32'sd1 << (SHIFT_AMT-1))) >>> SHIFT_AMT;
    end
end

    

endmodule