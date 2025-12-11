`timescale 1ns/1ps
// daub6_top_full.sv
// Fully instantiated top-level Daub-6 design.

module daub6_top_full #(
  parameter DATA_WIDTH = 16
)(
  input  logic                        clk,
  input  logic                        rst,
  input  logic signed [DATA_WIDTH-1:0] in,  // single input signal
  output logic signed [DATA_WIDTH-1:0] out  // final reconstructed output
);

  //===============================================================
  // Stage 1: Initial Decomposition (1 -> 4)
  //===============================================================
  // A0: First ai_3: input to 3 outputs.
  logic signed [DATA_WIDTH-1:0] A0_out0, A0_out1, A0_out2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) A0 (
    .clk(clk), .rst(rst), .in(in),
    .out0(A0_out0), .out1(A0_out1), .out2(A0_out2)
  );
  
  // A1, A2, A3: Each processes one of A0 outputs (each yields 3 outputs).
  logic signed [DATA_WIDTH-1:0] A1_out0, A1_out1, A1_out2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) A1 (
    .clk(clk), .rst(rst), .in(A0_out0),
    .out0(A1_out0), .out1(A1_out1), .out2(A1_out2)
  );
  
  logic signed [DATA_WIDTH-1:0] A2_out0, A2_out1, A2_out2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) A2 (
    .clk(clk), .rst(rst), .in(A0_out1),
    .out0(A2_out0), .out1(A2_out1), .out2(A2_out2)
  );
  
  logic signed [DATA_WIDTH-1:0] A3_out0, A3_out1, A3_out2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) A3 (
    .clk(clk), .rst(rst), .in(A0_out2),
    .out0(A3_out0), .out1(A3_out1), .out2(A3_out2)
  );
  
  // Combine the 9 outputs (from A1, A2, A3) with comb_A to get 4 outputs.
  logic signed [DATA_WIDTH-1:0] S1_0, S1_1, S1_2, S1_3;
  comb_A #(.DATA_WIDTH(DATA_WIDTH)) CombA1 (
    .in0(A1_out0), .in1(A1_out1), .in2(A1_out2),
    .in3(A2_out0), .in4(A2_out1), .in5(A2_out2),
    .in6(A3_out0), .in7(A3_out1), .in8(A3_out2),
    .out0(S1_0), .out1(S1_1), .out2(S1_2), .out3(S1_3)
  );
  // S1_0..S1_3 are the Stage 1 outputs.

  //===============================================================
  // Stage 2: Four Chains, each from one S1 signal (1 -> 4 each)
  //===============================================================
  //--- Chain for S1_0:
  logic signed [DATA_WIDTH-1:0] B0_0, B0_1, B0_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) B0 (
    .clk(clk), .rst(rst), .in(S1_0),
    .out0(B0_0), .out1(B0_1), .out2(B0_2)
  );
  logic signed [DATA_WIDTH-1:0] B1_0, B1_1, B1_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) B1 (
    .clk(clk), .rst(rst), .in(B0_0),
    .out0(B1_0), .out1(B1_1), .out2(B1_2)
  );
  logic signed [DATA_WIDTH-1:0] B2_0, B2_1, B2_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) B2 (
    .clk(clk), .rst(rst), .in(B0_1),
    .out0(B2_0), .out1(B2_1), .out2(B2_2)
  );
  logic signed [DATA_WIDTH-1:0] B3_0, B3_1, B3_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) B3 (
    .clk(clk), .rst(rst), .in(B0_2),
    .out0(B3_0), .out1(B3_1), .out2(B3_2)
  );
  logic signed [DATA_WIDTH-1:0] C0_0, C0_1, C0_2, C0_3;
  comb_A #(.DATA_WIDTH(DATA_WIDTH)) CombA2 (
    .in0(B1_0), .in1(B1_1), .in2(B1_2),
    .in3(B2_0), .in4(B2_1), .in5(B2_2),
    .in6(B3_0), .in7(B3_1), .in8(B3_2),
    .out0(C0_0), .out1(C0_1), .out2(C0_2), .out3(C0_3)
  );
  
  //--- Chain for S1_1:
  logic signed [DATA_WIDTH-1:0] D0_0, D0_1, D0_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) D0 (
    .clk(clk), .rst(rst), .in(S1_1),
    .out0(D0_0), .out1(D0_1), .out2(D0_2)
  );
  logic signed [DATA_WIDTH-1:0] D1_0, D1_1, D1_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) D1 (
    .clk(clk), .rst(rst), .in(D0_0),
    .out0(D1_0), .out1(D1_1), .out2(D1_2)
  );
  logic signed [DATA_WIDTH-1:0] D2_0, D2_1, D2_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) D2 (
    .clk(clk), .rst(rst), .in(D0_1),
    .out0(D2_0), .out1(D2_1), .out2(D2_2)
  );
  logic signed [DATA_WIDTH-1:0] D3_0, D3_1, D3_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) D3 (
    .clk(clk), .rst(rst), .in(D0_2),
    .out0(D3_0), .out1(D3_1), .out2(D3_2)
  );
  logic signed [DATA_WIDTH-1:0] C1_0, C1_1, C1_2, C1_3;
  comb_A #(.DATA_WIDTH(DATA_WIDTH)) CombA3 (
    .in0(D1_0), .in1(D1_1), .in2(D1_2),
    .in3(D2_0), .in4(D2_1), .in5(D2_2),
    .in6(D3_0), .in7(D3_1), .in8(D3_2),
    .out0(C1_0), .out1(C1_1), .out2(C1_2), .out3(C1_3)
  );
  
  //--- Chain for S1_2:
  logic signed [DATA_WIDTH-1:0] E0_0, E0_1, E0_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) E0 (
    .clk(clk), .rst(rst), .in(S1_2),
    .out0(E0_0), .out1(E0_1), .out2(E0_2)
  );
  logic signed [DATA_WIDTH-1:0] E1_0, E1_1, E1_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) E1 (
    .clk(clk), .rst(rst), .in(E0_0),
    .out0(E1_0), .out1(E1_1), .out2(E1_2)
  );
  logic signed [DATA_WIDTH-1:0] E2_0, E2_1, E2_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) E2 (
    .clk(clk), .rst(rst), .in(E0_1),
    .out0(E2_0), .out1(E2_1), .out2(E2_2)
  );
  logic signed [DATA_WIDTH-1:0] E3_0, E3_1, E3_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) E3 (
    .clk(clk), .rst(rst), .in(E0_2),
    .out0(E3_0), .out1(E3_1), .out2(E3_2)
  );
  logic signed [DATA_WIDTH-1:0] C2_0, C2_1, C2_2, C2_3;
  comb_A #(.DATA_WIDTH(DATA_WIDTH)) CombA4 (
    .in0(E1_0), .in1(E1_1), .in2(E1_2),
    .in3(E2_0), .in4(E2_1), .in5(E2_2),
    .in6(E3_0), .in7(E3_1), .in8(E3_2),
    .out0(C2_0), .out1(C2_1), .out2(C2_2), .out3(C2_3)
  );
  
  //--- Chain for S1_3:
  logic signed [DATA_WIDTH-1:0] F0_0, F0_1, F0_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) F0 (
    .clk(clk), .rst(rst), .in(S1_3),
    .out0(F0_0), .out1(F0_1), .out2(F0_2)
  );
  logic signed [DATA_WIDTH-1:0] F1_0, F1_1, F1_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) F1 (
    .clk(clk), .rst(rst), .in(F0_0),
    .out0(F1_0), .out1(F1_1), .out2(F1_2)
  );
  logic signed [DATA_WIDTH-1:0] F2_0, F2_1, F2_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) F2 (
    .clk(clk), .rst(rst), .in(F0_1),
    .out0(F2_0), .out1(F2_1), .out2(F2_2)
  );
  logic signed [DATA_WIDTH-1:0] F3_0, F3_1, F3_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) F3 (
    .clk(clk), .rst(rst), .in(F0_2),
    .out0(F3_0), .out1(F3_1), .out2(F3_2)
  );
  logic signed [DATA_WIDTH-1:0] C3_0, C3_1, C3_2, C3_3;
  comb_A #(.DATA_WIDTH(DATA_WIDTH)) CombA5 (
    .in0(F1_0), .in1(F1_1), .in2(F1_2),
    .in3(F2_0), .in4(F2_1), .in5(F2_2),
    .in6(F3_0), .in7(F3_1), .in8(F3_2),
    .out0(C3_0), .out1(C3_1), .out2(C3_2), .out3(C3_3)
  );
  
  // Now, combine the four chains (each yielding 4 outputs) with comb_B2.
  logic signed [DATA_WIDTH-1:0] S2_0, S2_1, S2_2, S2_3;
  comb_B2 #(.DATA_WIDTH(DATA_WIDTH)) CombB2_1 (
    .in0(C0_0),  .in1(C0_1),  .in2(C0_2),  .in3(C0_3),
    .in4(C1_0),  .in5(C1_1),  .in6(C1_2),  .in7(C1_3),
    .in8(C2_0),  .in9(C2_1),  .in10(C2_2), .in11(C2_3),
    .in12(C3_0), .in13(C3_1), .in14(C3_2), .in15(C3_3),
    .out0(S2_0), .out1(S2_1), .out2(S2_2), .out3(S2_3)
  );
  // S2_0..S2_3 are the outputs after Stage 2.
  
  //===============================================================
  // Stage 3: Four Chains from the four S2 signals (1 -> 4 each)
  //===============================================================
  // --- Chain for S2_0 (replicating the style of Stage 2 chain)
  logic signed [DATA_WIDTH-1:0] G0_0, G0_1, G0_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) G0 (
    .clk(clk), .rst(rst), .in(S2_0),
    .out0(G0_0), .out1(G0_1), .out2(G0_2)
  );
  logic signed [DATA_WIDTH-1:0] G1_0, G1_1, G1_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) G1 (
    .clk(clk), .rst(rst), .in(G0_0),
    .out0(G1_0), .out1(G1_1), .out2(G1_2)
  );
  logic signed [DATA_WIDTH-1:0] G2_0, G2_1, G2_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) G2 (
    .clk(clk), .rst(rst), .in(G0_1),
    .out0(G2_0), .out1(G2_1), .out2(G2_2)
  );
  logic signed [DATA_WIDTH-1:0] G3_0, G3_1, G3_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) G3 (
    .clk(clk), .rst(rst), .in(G0_2),
    .out0(G3_0), .out1(G3_1), .out2(G3_2)
  );
  logic signed [DATA_WIDTH-1:0] H0_0, H0_1, H0_2, H0_3;
  comb_A #(.DATA_WIDTH(DATA_WIDTH)) CombA6 (
    .in0(G1_0), .in1(G1_1), .in2(G1_2),
    .in3(G2_0), .in4(G2_1), .in5(G2_2),
    .in6(G3_0), .in7(G3_1), .in8(G3_2),
    .out0(H0_0), .out1(H0_1), .out2(H0_2), .out3(H0_3)
  );
  
  // --- Chain for S2_1:
  logic signed [DATA_WIDTH-1:0] H1_0, H1_1, H1_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) H1 (
    .clk(clk), .rst(rst), .in(S2_1),
    .out0(H1_0), .out1(H1_1), .out2(H1_2)
  );
  logic signed [DATA_WIDTH-1:0] I0_0, I0_1, I0_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) I0 (
    .clk(clk), .rst(rst), .in(H1_0),
    .out0(I0_0), .out1(I0_1), .out2(I0_2)
  );
  logic signed [DATA_WIDTH-1:0] I1_0, I1_1, I1_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) I1 (
    .clk(clk), .rst(rst), .in(H1_1),
    .out0(I1_0), .out1(I1_1), .out2(I1_2)
  );
  logic signed [DATA_WIDTH-1:0] I2_0, I2_1, I2_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) I2 (
    .clk(clk), .rst(rst), .in(H1_2),
    .out0(I2_0), .out1(I2_1), .out2(I2_2)
  );
  logic signed [DATA_WIDTH-1:0] J0_0, J0_1, J0_2, J0_3;
  comb_A #(.DATA_WIDTH(DATA_WIDTH)) CombA7 (
    .in0(I0_0), .in1(I0_1), .in2(I0_2),
    .in3(I1_0), .in4(I1_1), .in5(I1_2),
    .in6(I2_0), .in7(I2_1), .in8(I2_2),
    .out0(J0_0), .out1(J0_1), .out2(J0_2), .out3(J0_3)
  );
  
  // --- Chain for S2_2:
  logic signed [DATA_WIDTH-1:0] K0_0, K0_1, K0_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) K0 (
    .clk(clk), .rst(rst), .in(S2_2),
    .out0(K0_0), .out1(K0_1), .out2(K0_2)
  );
  logic signed [DATA_WIDTH-1:0] K1_0, K1_1, K1_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) K1 (
    .clk(clk), .rst(rst), .in(K0_0),
    .out0(K1_0), .out1(K1_1), .out2(K1_2)
  );
  logic signed [DATA_WIDTH-1:0] K2_0, K2_1, K2_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) K2 (
    .clk(clk), .rst(rst), .in(K0_1),
    .out0(K2_0), .out1(K2_1), .out2(K2_2)
  );
  logic signed [DATA_WIDTH-1:0] K3_0, K3_1, K3_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) K3 (
    .clk(clk), .rst(rst), .in(K0_2),
    .out0(K3_0), .out1(K3_1), .out2(K3_2)
  );
  logic signed [DATA_WIDTH-1:0] L0_0, L0_1, L0_2, L0_3;
  comb_A #(.DATA_WIDTH(DATA_WIDTH)) CombA8 (
    .in0(K1_0), .in1(K1_1), .in2(K1_2),
    .in3(K2_0), .in4(K2_1), .in5(K2_2),
    .in6(K3_0), .in7(K3_1), .in8(K3_2),
    .out0(L0_0), .out1(L0_1), .out2(L0_2), .out3(L0_3)
  );
  
  // --- Chain for S2_3:
  logic signed [DATA_WIDTH-1:0] M0_0, M0_1, M0_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) M0 (
    .clk(clk), .rst(rst), .in(S2_3),
    .out0(M0_0), .out1(M0_1), .out2(M0_2)
  );
  logic signed [DATA_WIDTH-1:0] M1_0, M1_1, M1_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) M1 (
    .clk(clk), .rst(rst), .in(M0_0),
    .out0(M1_0), .out1(M1_1), .out2(M1_2)
  );
  logic signed [DATA_WIDTH-1:0] M2_0, M2_1, M2_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) M2 (
    .clk(clk), .rst(rst), .in(M0_1),
    .out0(M2_0), .out1(M2_1), .out2(M2_2)
  );
  logic signed [DATA_WIDTH-1:0] M3_0, M3_1, M3_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) M3 (
    .clk(clk), .rst(rst), .in(M0_2),
    .out0(M3_0), .out1(M3_1), .out2(M3_2)
  );
  logic signed [DATA_WIDTH-1:0] L1_0, L1_1, L1_2, L1_3;
  comb_A #(.DATA_WIDTH(DATA_WIDTH)) CombA9 (
    .in0(M1_0), .in1(M1_1), .in2(M1_2),
    .in3(M2_0), .in4(M2_1), .in5(M2_2),
    .in6(M3_0), .in7(M3_1), .in8(M3_2),
    .out0(L1_0), .out1(L1_1), .out2(L1_2), .out3(L1_3)
  );
  
  // Combine the four Stage 3 chain outputs using comb_B2.
  logic signed [DATA_WIDTH-1:0] S3_f_0, S3_f_1, S3_f_2, S3_f_3;
  comb_B2 #(.DATA_WIDTH(DATA_WIDTH)) CombB2_2 (
    .in0(H0_0),  .in1(H0_1),  .in2(H0_2),  .in3(H0_3),
    .in4(J0_0),  .in5(J0_1),  .in6(J0_2),  .in7(J0_3),
    .in8(L0_0),  .in9(L0_1),  .in10(L0_2), .in11(L0_3),
    .in12(L1_0), .in13(L1_1), .in14(L1_2), .in15(L1_3),
    .out0(S3_f_0), .out1(S3_f_1), .out2(S3_f_2), .out3(S3_f_3)
  );
  // S3_f_0..S3_f_3 are the outputs from Stage 3.
  
  //===============================================================
  // Stage 4: Four Chains from the S3_f signals (1 -> 4 each)
  //===============================================================
  // For each S3_f signal, instantiate a chain similar to previous ones.
  // --- Chain for S3_f_0:
  logic signed [DATA_WIDTH-1:0] N0_0, N0_1, N0_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) N0 (
    .clk(clk), .rst(rst), .in(S3_f_0),
    .out0(N0_0), .out1(N0_1), .out2(N0_2)
  );
  logic signed [DATA_WIDTH-1:0] N1_0, N1_1, N1_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) N1 (
    .clk(clk), .rst(rst), .in(N0_0),
    .out0(N1_0), .out1(N1_1), .out2(N1_2)
  );
  logic signed [DATA_WIDTH-1:0] N2_0, N2_1, N2_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) N2 (
    .clk(clk), .rst(rst), .in(N0_1),
    .out0(N2_0), .out1(N2_1), .out2(N2_2)
  );
  logic signed [DATA_WIDTH-1:0] N3_0, N3_1, N3_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) N3 (
    .clk(clk), .rst(rst), .in(N0_2),
    .out0(N3_0), .out1(N3_1), .out2(N3_2)
  );
  logic signed [DATA_WIDTH-1:0] O0_0, O0_1, O0_2, O0_3;
  comb_A #(.DATA_WIDTH(DATA_WIDTH)) CombA10 (
    .in0(N1_0), .in1(N1_1), .in2(N1_2),
    .in3(N2_0), .in4(N2_1), .in5(N2_2),
    .in6(N3_0), .in7(N3_1), .in8(N3_2),
    .out0(O0_0), .out1(O0_1), .out2(O0_2), .out3(O0_3)
  );
  
  // --- Chain for S3_f_1:
  logic signed [DATA_WIDTH-1:0] P0_0, P0_1, P0_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) P0 (
    .clk(clk), .rst(rst), .in(S3_f_1),
    .out0(P0_0), .out1(P0_1), .out2(P0_2)
  );
  logic signed [DATA_WIDTH-1:0] P1_0, P1_1, P1_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) P1 (
    .clk(clk), .rst(rst), .in(P0_0),
    .out0(P1_0), .out1(P1_1), .out2(P1_2)
  );
  logic signed [DATA_WIDTH-1:0] P2_0, P2_1, P2_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) P2 (
    .clk(clk), .rst(rst), .in(P0_1),
    .out0(P2_0), .out1(P2_1), .out2(P2_2)
  );
  logic signed [DATA_WIDTH-1:0] P3_0, P3_1, P3_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) P3 (
    .clk(clk), .rst(rst), .in(P0_2),
    .out0(P3_0), .out1(P3_1), .out2(P3_2)
  );
  logic signed [DATA_WIDTH-1:0] O1_0, O1_1, O1_2, O1_3;
  comb_A #(.DATA_WIDTH(DATA_WIDTH)) CombA11 (
    .in0(P1_0), .in1(P1_1), .in2(P1_2),
    .in3(P2_0), .in4(P2_1), .in5(P2_2),
    .in6(P3_0), .in7(P3_1), .in8(P3_2),
    .out0(O1_0), .out1(O1_1), .out2(O1_2), .out3(O1_3)
  );
  
  // --- Chain for S3_f_2:
  logic signed [DATA_WIDTH-1:0] Q0_0, Q0_1, Q0_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) Q0 (
    .clk(clk), .rst(rst), .in(S3_f_2),
    .out0(Q0_0), .out1(Q0_1), .out2(Q0_2)
  );
  logic signed [DATA_WIDTH-1:0] Q1_0, Q1_1, Q1_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) Q1 (
    .clk(clk), .rst(rst), .in(Q0_0),
    .out0(Q1_0), .out1(Q1_1), .out2(Q1_2)
  );
  logic signed [DATA_WIDTH-1:0] Q2_0, Q2_1, Q2_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) Q2 (
    .clk(clk), .rst(rst), .in(Q0_1),
    .out0(Q2_0), .out1(Q2_1), .out2(Q2_2)
  );
  logic signed [DATA_WIDTH-1:0] Q3_0, Q3_1, Q3_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) Q3 (
    .clk(clk), .rst(rst), .in(Q0_2),
    .out0(Q3_0), .out1(Q3_1), .out2(Q3_2)
  );
  logic signed [DATA_WIDTH-1:0] O2_0, O2_1, O2_2, O2_3;
  comb_A #(.DATA_WIDTH(DATA_WIDTH)) CombA12 (
    .in0(Q1_0), .in1(Q1_1), .in2(Q1_2),
    .in3(Q2_0), .in4(Q2_1), .in5(Q2_2),
    .in6(Q3_0), .in7(Q3_1), .in8(Q3_2),
    .out0(O2_0), .out1(O2_1), .out2(O2_2), .out3(O2_3)
  );
  
  // --- Chain for S3_f_3:
  logic signed [DATA_WIDTH-1:0] R0_0, R0_1, R0_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) R0 (
    .clk(clk), .rst(rst), .in(S3_f_3),
    .out0(R0_0), .out1(R0_1), .out2(R0_2)
  );
  logic signed [DATA_WIDTH-1:0] R1_0, R1_1, R1_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) R1 (
    .clk(clk), .rst(rst), .in(R0_0),
    .out0(R1_0), .out1(R1_1), .out2(R1_2)
  );
  logic signed [DATA_WIDTH-1:0] R2_0, R2_1, R2_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) R2 (
    .clk(clk), .rst(rst), .in(R0_1),
    .out0(R2_0), .out1(R2_1), .out2(R2_2)
  );
  logic signed [DATA_WIDTH-1:0] R3_0, R3_1, R3_2;
  ai_3 #(.DATA_WIDTH(DATA_WIDTH)) R3 (
    .clk(clk), .rst(rst), .in(R0_2),
    .out0(R3_0), .out1(R3_1), .out2(R3_2)
  );
  logic signed [DATA_WIDTH-1:0] O3_0, O3_1, O3_2, O3_3;
  comb_A #(.DATA_WIDTH(DATA_WIDTH)) CombA13 (
    .in0(R1_0), .in1(R1_1), .in2(R1_2),
    .in3(R2_0), .in4(R2_1), .in5(R2_2),
    .in6(R3_0), .in7(R3_1), .in8(R3_2),
    .out0(O3_0), .out1(O3_1), .out2(O3_2), .out3(O3_3)
  );
  
  // Combine the 4 Stage 4 chain outputs via comb_B2.
  logic signed [DATA_WIDTH-1:0] S4_f_0, S4_f_1, S4_f_2, S4_f_3;
  comb_B2 #(.DATA_WIDTH(DATA_WIDTH)) CombB2_3 (
    .in0(O0_0),  .in1(O0_1),  .in2(O0_2),  .in3(O0_3),
    .in4(O1_0),  .in5(O1_1),  .in6(O1_2),  .in7(O1_3),
    .in8(O2_0),  .in9(O2_1),  .in10(O2_2), .in11(O2_3),
    .in12(O3_0), .in13(O3_1), .in14(O3_2), .in15(O3_3),
    .out0(S4_f_0), .out1(S4_f_1), .out2(S4_f_2), .out3(S4_f_3)
  );
  
  //===============================================================
  // Final Reconstruction Step (FRS)
  //===============================================================
  frs #(.DATA_WIDTH(DATA_WIDTH)) FRS_inst (
    .in0(S4_f_0), .in1(S4_f_1), .in2(S4_f_2), .in3(S4_f_3),
    .out(out)
  );

endmodule
