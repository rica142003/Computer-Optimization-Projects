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

The Daub-6 filter coefficients are irrational, complicating hardware implementation due to quantization and rounding errors. Therefore, this project emphasizes designing an efficient and accurate hardware solution, implementing a 4-level Daub-6 wavelet decomposition.

