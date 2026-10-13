## CSI-2 byte clock: 100 MHz
create_clock -period 10.000 -name clk_byte [get_ports clk_byte]

## SoC AXI clock: 150 MHz
create_clock -period 6.667  -name clk_axi  [get_ports clk_axi]

## Unrelated clocks: data crosses only through the Gray-pointer async FIFO
## and 2-flop synchronizers, so no timing paths between the domains.
set_clock_groups -asynchronous -group [get_clocks clk_byte] -group [get_clocks clk_axi]

## Keep synchronizer flops together and out of retiming/SRL inference
set_property ASYNC_REG TRUE [get_cells -hierarchical -filter {NAME =~ *sync_ff*sync_2ff_*/q_reg}]
