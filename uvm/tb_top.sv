// tb_top.sv - clock, reset, interface, DUT, start UVM
`timescale 1ns/1ps

module tb_top;
    import uvm_pkg::*;
    import mm_pkg::*;

    logic clk;

    // Clock 250 MHz
    initial clk = 0;
    always #2 clk = ~clk;

    axil_if vif (clk);

    // DUT
    matmul_axil_top DUT (
        .clk(clk), .resetn(vif.resetn),
        .awaddr(vif.awaddr), .awvalid(vif.awvalid), .awready(vif.awready),
        .wdata(vif.wdata), .wstrb(vif.wstrb), .wvalid(vif.wvalid), .wready(vif.wready),
        .bresp(vif.bresp), .bvalid(vif.bvalid), .bready(vif.bready),
        .araddr(vif.araddr), .arvalid(vif.arvalid), .arready(vif.arready),
        .rdata(vif.rdata), .rresp(vif.rresp), .rvalid(vif.rvalid), .rready(vif.rready),
        .irq(vif.irq)
    );

    // Reset
    initial begin
        vif.resetn = 0;
        repeat(5) @(posedge clk);
        @(negedge clk);
        vif.resetn = 1;
    end

    // Start UVM
    initial begin
        uvm_config_db#(virtual axil_if)::set(null, "*", "vif", vif);
        run_test();
    end

    // Timeout
    initial begin
        #5000000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
