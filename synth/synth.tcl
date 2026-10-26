# Genus synthesis for 4x4 INT8 Systolic Array Accelerator
# Technology: SKY130 HD

set script_dir [file dirname [file normalize [info script]]]
set rtl_dir [file normalize [file join $script_dir ../rtl]]

# Clock period
set clock_period 10
if {[info exists env(CLOCK_PERIOD_NS)]} {
    set clock_period $env(CLOCK_PERIOD_NS)
}

if {![string is double -strict $clock_period] || $clock_period <= 0} {
    error "CLOCK_PERIOD_NS must be a positive number"
}

# Technology library
set library_file [file join $env(HOME) sky130_lib sky130_fd_sc_hd__tt_025C_1v80.lib]

if {[info exists env(SKY130_LIB)]} {
    set library_file $env(SKY130_LIB)
}

if {![file isfile $library_file]} {
    error "SKY130 library not found: $library_file"
}

set_db library [file normalize $library_file]

# RTL files
set rtl_files {
    pe.sv
    pe_array.sv
    input_buffer.sv
    data_feeder.sv
    controller.sv
    output_buffer.sv
    matmul_accelerator.sv
}

set sources {}

foreach name $rtl_files {
    lappend sources [file join $rtl_dir $name]
}

# Read and elaborate
read_hdl -sv $sources

elaborate matmul_accelerator

check_design -unresolved

# Timing constraints
create_clock -name clk -period $clock_period [get_ports clk]

# Apply I/O delays to data and control ports, excluding clock and reset
set input_ports [remove_from_collection [all_inputs] [get_ports {clk resetn}]]

set_input_delay 2 -clock clk $input_ports
set_output_delay 2 -clock clk [all_outputs]

# Synthesis
syn_generic
syn_map
syn_opt

# Output directory
set output_dir [file join $script_dir build "${clock_period}ns"]
file mkdir $output_dir

# Reports
report_area > [file join $output_dir area.rpt]
report_timing > [file join $output_dir timing.rpt]
report_qor > [file join $output_dir qor.rpt]
report_gates > [file join $output_dir gates.rpt]

# Gate-level netlist
write_hdl > [file join $output_dir matmul_netlist.v]

exit
