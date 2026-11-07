# Timing constraints for every core (rabbit_cpu wrapper), same for all so the
# comparison is fair. CLOCK_PERIOD (ns) comes from the environment (run.sh).
#
# I/O: the memory interface is synchronous SRAM-like. We give the memory 20 %
# of the clock period to produce data after the clock edge (input delay) and
# 20 % to accept an address before the next edge (output delay). A path that
# goes straight from a memory input to a memory output inside the core (only
# rabbit3 has one: instruction word -> decode -> register file -> ALU -> data
# address) therefore gets 60 % of the period. This is an assumption; the real
# number comes later with SRAM macros.
current_design rabbit_cpu

set clk_period $::env(CLOCK_PERIOD)
set clk_io_pct 0.2

create_clock -name clk -period $clk_period [get_ports clk_i]

set non_clock_inputs [lsearch -inline -all -not -exact [all_inputs] [get_ports clk_i]]
set_input_delay  [expr {$clk_period * $clk_io_pct}] -clock clk $non_clock_inputs
set_output_delay [expr {$clk_period * $clk_io_pct}] -clock clk [all_outputs]

# asynchronous reset: not a timing path
set_false_path -from [get_ports rst_ni]
