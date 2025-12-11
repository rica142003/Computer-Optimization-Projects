## clk_constraint.xdc
## --------------------------------------------------
## Create a clock on the port "clk" with a 10 ns period (100 MHz)
create_clock -name sys_clk -period 10.0 -waveform {0 5} [get_ports clk]
