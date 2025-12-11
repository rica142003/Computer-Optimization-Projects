unquantized_filter = designfilt('lowpassfir','PassbandFrequency',0.2,'StopbandFrequency',0.23,'PassbandRipple',1,'StopbandAttenuation',80);

fileID = fopen('fir_coefficients.txt','w');
fprintf(fileID, '%f\n', unquantized_filter.Coefficients);
fclose(fileID);