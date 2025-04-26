# Optimized 2-D Daubechies-6 Wavelet Filter VLSI Implementation
## Overview
This repository contains the VLSI implementation of an optimized Daubechies-6 (Daub-6) Wavelet Filter, designed using Algebraic Integer (AI) encoding to minimize hardware complexity. The implementation compares traditional Fixed-Point arithmetic with Algebraic Integer representation to highlight the benefits of using AI in terms of reduced quantization error, hardware efficiency, and power consumption.

## Motivation
Implementing wavelet transforms in hardware often faces significant challenges due to computational complexity and the use of irrational coefficients, which require intensive arithmetic operations, leading to quantization errors, increased hardware resources, and higher power consumption. To address these challenges, this project aims to utilize Algebraic Integer encoding, which allows exact arithmetic operations and thus significantly reduces hardware complexity, minimizes quantization errors, and optimizes power efficiency.

## Daubechies-6 Wavelet Filter Basics
The Daubechies-6 Wavelet Filter is a popular discrete wavelet transform (DWT) used extensively in image and signal processing, including applications such as compression, denoising, and feature extraction. Originally introduced by Ingrid Daubechies in 1988, the Daub-6 filter is particularly effective at analyzing signals with abrupt changes, spikes, and high levels of noise.

This filter uses two FIR filters, one low-pass and one high-pass, to decompose a signal or image into four frequency sub-bands:
* $A_n$ (Low-Low): Coarse approximation of the original data
* $Dv_n$ (Low-High): Horizontal details
* $Dh_n$ (High-Low): Vertical details
* $Dd_n$ (High-High): Diagonal details

The following diagrams illustrate the decomposition process:

### Single Level Decomposition
<p align="left">
  <img  src="https://github.com/user-attachments/assets/8acc9db4-7050-41c7-9872-22afc5573b22" style="width: 50%; height: auto;">
</p>

### Multi-Level Decomposition
<p align="left">
  <img  src="https://github.com/user-attachments/assets/5140e9c6-01bf-451a-9bfa-b711618bf876" style="width: 50%; height: auto;">
</p>

## Algebraic-Integer (AI) Encoding  
Algebraic Integer (AI) encoding is a mathematical technique used to exactly represent irrational numbers using a set of carefully chosen "building blocks." Rather than immediately approximating irrational values with rounded fixed-point numbers (which introduces small errors at every operation), AI encoding expresses them as combinations of simple, related numbers that are treated exactly during computation.

In this project, the six irrational coefficients of the Daubechies 6-tap filter are broken into sums of integers multiplied by elements of a small "basis" set $(1, \zeta_1, \zeta_2, \zeta_1 \zeta_2) $. These basis elements are specific irrational numbers that satisfy certain polynomial equations, and they allow the irrational filter coefficients to be represented with only integer arithmetic until the very end.

This means all internal operations (filtering, combining, decomposition) are performed exactly with integers, and the only approximation happens once during the final reconstruction back to a real-world number. This method significantly improves accuracy and avoids the accumulation of rounding errors.
For the optimized 4-level design (Method 1), the AI filters use the following integer coefficients:
<p align="left">
  <img  src="https://github.com/user-attachments/assets/ad5e5662-7e5b-45bb-8143-1e317145f2a4" style="width: 50%; height: auto;">
</p>


## Canonical Signed Digit (CSD) Representation
CSD encoding minimizes the number of non-zero bits (-1, 0, +1) in binary constants. Fewer non-zeros translate directly to fewer adders in hardware. Examples:
* $S_{CSD}$ (3) = 1 (2 + 1)
* $S_{CSD}$ (11) = 3 (16 - 4 -1)

We apply CSD to all AI filter coefficients and in the FRS. Sparse CSD encodings are found by brute-force optimization over dyadic scaling parameters to minimize total adder count (see research paper Section IV).





