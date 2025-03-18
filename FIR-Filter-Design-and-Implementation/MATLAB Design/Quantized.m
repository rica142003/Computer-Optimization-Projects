%% Design Unquantized FIR Filter
unquantized_filter = designfilt('lowpassfir', ...
    'PassbandFrequency', 0.2, ...
    'StopbandFrequency', 0.23, ...
    'PassbandRipple', 1, ...
    'StopbandAttenuation', 80);

% Save unquantized filter coefficients to file
fileID = fopen('fir_coefficients.txt', 'w');
fprintf(fileID, '%f\n', unquantized_filter.Coefficients);
fclose(fileID);

%% Quantize the Filter Coefficients (Example using Q15 Format)
scale = 2^(15);  % Define scaling factor for Q15 format
quantizedCoeffs = round(unquantized_filter.Coefficients * scale) / scale;

% Save quantized filter coefficients to file
fileID = fopen('fir_coefficients_quantized.txt', 'w');
fprintf(fileID, '%f\n', quantizedCoeffs);
fclose(fileID);

%% Frequency Response Comparison
N = 1024;  % Number of frequency points for the analysis
[H_unquant, w] = freqz(unquantized_filter.Coefficients, 1, N);
[H_quant, ~] = freqz(quantizedCoeffs, 1, N);

figure;
plot(w/pi, 20*log10(abs(H_unquant)), 'green', 'LineWidth', 0.8); hold on;
plot(w/pi, 20*log10(abs(H_quant)), 'b--', 'LineWidth', 0.9);
xlabel('Normalized Frequency (\times\pi rad/sample)');
ylabel('Magnitude (dB)');
legend('Unquantized', 'Quantized');
title('Frequency Response Comparison');
grid on;
