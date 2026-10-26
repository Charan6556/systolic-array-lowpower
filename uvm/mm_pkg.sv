// mm_pkg.sv - all UVM classes
package mm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "axil_item.sv"
    `include "axil_driver.sv"
    `include "axil_monitor.sv"
    `include "axil_agent.sv"
    `include "mm_scoreboard.sv"
    `include "mm_env.sv"
    `include "mm_seqs.sv"
    `include "mm_tests.sv"
endpackage
