module parallel_adder_tree #(
    parameter int N = 8
)(
    input  wire signed [31:0] in [0:N-1],
    output wire signed [31:0] out
);

    // We'll have log2(N) levels in the tree (round up).
    localparam int LEVELS = $clog2(N);

    // Create a 2D array: stage[level][index]
    // Each stage is up to N wide. Some positions may go unused if N is not a power of 2.
    wire signed [31:0] stage [0:LEVELS][0:N-1];

    // Stage 0 is just the inputs
    genvar i, l;
    generate
        for (i = 0; i < N; i++) begin : assign_inputs
            assign stage[0][i] = in[i];
        end

        // Build each level
        for (l = 0; l < LEVELS; l++) begin : levels
            // Number of active signals in stage l is (N >> l) or, if not power-of-2, we handle leftover
            localparam int ACTIVE = (N >> l);

            for (i = 0; i < (ACTIVE >> 1); i++) begin : add_pairs
                // Add pairs: stage[l][2*i] + stage[l][2*i+1]
                assign stage[l+1][i] = stage[l][2*i] + stage[l][2*i+1];
            end

            // If there's an odd leftover at this level, pass it straight down
            if ((ACTIVE % 2) == 1) begin : leftover
                assign stage[l+1][(ACTIVE >> 1)] = stage[l][ACTIVE - 1];
            end

            // For indices beyond (ACTIVE >> 1) + leftover, tie off or ignore
            for (i = ((ACTIVE + 1) >> 1); i < N; i++) begin : unused
                assign stage[l+1][i] = 32'sd0; // Not used
            end
        end
    endgenerate

    // The final result is at stage[LEVELS][0].
    assign out = stage[LEVELS][0];

endmodule
