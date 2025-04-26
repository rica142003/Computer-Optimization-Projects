# Optimized 2-D Daubechies-6 Wavelet Filter VLSI Implementation
## 1. Overview
This repository contains the VLSI implementation of an optimized Daubechies-6 (Daub-6) Wavelet Filter, designed using Algebraic Integer (AI) encoding to minimize hardware complexity. The implementation compares traditional Fixed-Point arithmetic with Algebraic Integer representation to highlight the benefits of using AI in terms of reduced quantization error, hardware efficiency, and power consumption.

## 2. Motivation
Implementing wavelet transforms in hardware often faces significant challenges due to computational complexity and the use of irrational coefficients, which require intensive arithmetic operations, leading to quantization errors, increased hardware resources, and higher power consumption. To address these challenges, this project aims to utilize Algebraic Integer encoding, which allows exact arithmetic operations and thus significantly reduces hardware complexity, minimizes quantization errors, and optimizes power efficiency.

## 3. Basics
### 3.1 Daubechies-6 Wavelet Filter Basics
The Daubechies-6 Wavelet Filter is a popular discrete wavelet transform (DWT) used extensively in image and signal processing, including applications such as compression, denoising, and feature extraction. Originally introduced by Ingrid Daubechies in 1988, the Daub-6 filter is particularly effective at analyzing signals with abrupt changes, spikes, and high levels of noise.

This filter uses two FIR filters, one low-pass and one high-pass, to decompose a signal or image into four frequency sub-bands:
* $A_n$ (Low-Low): Coarse approximation of the original data
* $Dv_n$ (Low-High): Horizontal details
* $Dh_n$ (High-Low): Vertical details
* $Dd_n$ (High-High): Diagonal details

The following diagrams illustrate the decomposition process:

**Single Level Decomposition**
<p align="left">
  <img  src="https://github.com/user-attachments/assets/8acc9db4-7050-41c7-9872-22afc5573b22" style="width: 50%; height: auto;">
</p>

**Multi-Level Decomposition**
<p align="left">
  <img  src="https://github.com/user-attachments/assets/5140e9c6-01bf-451a-9bfa-b711618bf876" style="width: 50%; height: auto;">
</p>

### 3.2 Algebraic-Integer (AI) Encoding  
Algebraic Integer (AI) encoding is a mathematical technique used to exactly represent irrational numbers using a set of carefully chosen "building blocks." Rather than immediately approximating irrational values with rounded fixed-point numbers (which introduces small errors at every operation), AI encoding expresses them as combinations of simple, related numbers that are treated exactly during computation.

In this project, the six irrational coefficients of the Daubechies 6-tap filter are broken into sums of integers multiplied by elements of a small "basis" set $(1, \zeta_1, \zeta_2, \zeta_1 \zeta_2) $. These basis elements are specific irrational numbers that satisfy certain polynomial equations, and they allow the irrational filter coefficients to be represented with only integer arithmetic until the very end.

This means all internal operations (filtering, combining, decomposition) are performed exactly with integers, and the only approximation happens once during the final reconstruction back to a real-world number. This method significantly improves accuracy and avoids the accumulation of rounding errors.
For the optimized 4-level design (Method 1), the AI filters use the following integer coefficients:
<p align="left">
  <img  src="https://github.com/user-attachments/assets/ad5e5662-7e5b-45bb-8143-1e317145f2a4" style="width: 50%; height: auto;">
</p>

### 3.3 Canonical Signed Digit (CSD) Representation
CSD encoding minimizes the number of non-zero bits (-1, 0, +1) in binary constants. Fewer non-zeros translate directly to fewer adders in hardware. Examples:
* $S_{CSD}$ (3) = 1 (2 + 1)
* $S_{CSD}$ (11) = 3 (16 - 4 -1)

We apply CSD to all AI filter coefficients and in the FRS. Sparse CSD encodings are found by brute-force optimization over dyadic scaling parameters to minimize total adder count (see research paper Section IV).

## 4. Implementation
The full AI-based Daub-6 implementation consists of multiple stages, as illustrated below:
<p align="left">
  <img  src="https://github.com/user-attachments/assets/d6570416-0ef9-42dd-b4ca-c2caf86694e9" style="width: 50%; height: auto;">
</p>

1. The input is passed through an Extended AI (EAI) block, which performs filtering with the AI-decomposed coefficients.
2. The outputs are recombined in a Combinational Block A, forming the first-level coefficients.
3. At each level, a group of four AIC (AI + COMBA) blocks is used, followed by a Combinational Block B2.
4. This process is repeated through four levels of decomposition.
5. The final stage is the FRS (Final Reconstruction Step), which converts the result from the AI domain to fixed-point output.
   
### 4.1 AI Block
Each AI block performs three parallel FIR convolutions using integer coefficients derived from the algebraic integer basis.
<p align="left">
  <img  src="https://github.com/user-attachments/assets/4a5ce6c4-775f-4569-a763-64d008788167" style="width: 20%; height: auto;">
</p>

![image](https://github.com/user-attachments/assets/90931ac8-b43a-4b62-b39d-ddc3d071c5ba)

### 4.2 Combinational Blocks
After each level of AI filtering, four basis-domain outputs must be recombined before the next stage. Two specialized combinational blocks perform these merges using only shifts and adds.

#### Block A
Takes 9 AI-domain inputs and produces 4 combined outputs, corresponding to the four subband signals (LL, HL, LH, HH)

* Inputs: (integer accumulations from AI filters)
* Outputs: $y_{LL}, y_{HL}, y_{LH}, y_{HH}$
* Purpose: Polyphase assembly of column- then row-filtered data.

![image](https://github.com/user-attachments/assets/333f99e5-eb42-4186-af81-27653bfb6a92)

### Block B2: 
Takes 16 AI-domain inputs (from four 1-D recombinations) to produce the 4 outputs for the next level.

* Inputs: $b_0, b_1, ..., b_{15}$
* Outputs: $y_{LL}, y_{HL}, y_{LH}, y_{HH}$
* Purpose: Final merge of horizontal and vertical detail components into the four subbands.

![image](https://github.com/user-attachments/assets/047167e6-bf29-4a6e-ba7f-a4739e0a1430)





