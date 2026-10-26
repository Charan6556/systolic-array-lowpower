`include "uvm_macros.svh"
// power_sva.sv - assertions for the power sequence, bound to matmul_accelerator
module power_sva
    import uvm_pkg::*;
(
    input logic clk, resetn,
    input logic lp_pwr_en, lp_iso_en, lp_save, lp_restore,
    input logic busy
);

default clocking cb @(posedge clk); endclocking
default disable iff (!resetn);

// 1. Array off -> isolation must be on
a_iso_when_off: assert property (!lp_pwr_en |-> lp_iso_en)
    else `uvm_error("SVA", "SVA: array powered off without isolation");

// 2. Save happens right before isolation turns on
a_save_before_iso: assert property ($rose(lp_iso_en) |-> $past(lp_save))
    else `uvm_error("SVA", "SVA: isolation turned on without a save");

// 3. Isolation is already on when power turns off
a_iso_before_off: assert property ($fell(lp_pwr_en) |-> $past(lp_iso_en))
    else `uvm_error("SVA", "SVA: power turned off before isolation");

// 4. Restore only while the array is powered
a_restore_when_on: assert property (lp_restore |-> lp_pwr_en)
    else `uvm_error("SVA", "SVA: restore while the array is off");

// 5. Isolation removed only right after a restore
a_restore_before_uniso: assert property ($fell(lp_iso_en) |-> $past(lp_restore))
    else `uvm_error("SVA", "SVA: isolation removed without a restore");

// 6. Never power down in the middle of a run
a_no_save_while_busy: assert property (lp_save |-> !busy)
    else `uvm_error("SVA", "SVA: power-down started while busy");

// Coverage: full power-down and power-up sequences happened
c_power_down: cover property (lp_save ##1 $rose(lp_iso_en) ##1 $fell(lp_pwr_en));
c_power_up:   cover property ($rose(lp_pwr_en) ##[1:$] lp_restore ##1 $fell(lp_iso_en));

endmodule

// Attach to every matmul_accelerator instance
bind matmul_accelerator power_sva u_power_sva (
    .clk(clk),
    .resetn(resetn),
    .lp_pwr_en(lp_pwr_en),
    .lp_iso_en(lp_iso_en),
    .lp_save(lp_save),
    .lp_restore(lp_restore),
    .busy(busy)
);
