# synth_simple.tcl - Genus synthesis, 4x4 INT8 systolic accelerator, SKY130 HD

# 1. Library
set_db library $env(HOME)/sky130_lib/sky130_fd_sc_hd__tt_025C_1v80.lib

# 2. Read RTL
read_hdl -sv {
    ../rtl/pe.sv
    ../rtl/pe_array.sv
    ../rtl/input_buffer.sv
    ../rtl/data_feeder.sv
    ../rtl/controller.sv
    ../rtl/output_buffer.sv
    ../rtl/matmul_accelerator.sv
}
elaborate matmul_accelerator
check_design -unresolved

# 3. Constraints: 250 MHz clock (4 ns)
create_clock -name clk -period 4 [get_ports clk]
set_input_delay  1 -clock clk [remove_from_collection [all_inputs] [get_ports {clk resetn}]]
set_output_delay 1 -clock clk [all_outputs]

# 4. Synthesize
syn_generic
syn_map
syn_opt

# 5. Reports
file mkdir reports_lp
report_area   > reports_lp/area.rpt
report_timing > reports_lp/timing.rpt
report_power  > reports_lp/power.rpt
report_qor    > reports_lp/qor.rpt
write_hdl     > reports_lp/matmul_netlist.v
