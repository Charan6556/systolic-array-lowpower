// axil_monitor.sv - watches the AXI4-Lite pins, sends every finished transaction
class axil_monitor extends uvm_monitor;
    `uvm_component_utils(axil_monitor)

    virtual axil_if vif;
    uvm_analysis_port #(axil_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual axil_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "axil_monitor: virtual interface not set")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            watch_writes();
            watch_reads();
        join
    endtask

    // Write: catch AW and W (any order), send when the B handshake happens
    task watch_writes();
        logic [7:0]  aw_addr;
        logic [31:0] w_data;
        logic [3:0]  w_strb;
        axil_item t;
    begin
        forever begin
            @(posedge vif.clk);
            if(vif.resetn !== 1'b1) continue;

            if(vif.awvalid && vif.awready) aw_addr = vif.awaddr;
            if(vif.wvalid  && vif.wready)  begin w_data = vif.wdata; w_strb = vif.wstrb; end

            if(vif.bvalid && vif.bready) begin
                t = axil_item::type_id::create("wr");
                t.write = 1;
                t.addr  = aw_addr;
                t.data  = w_data;
                t.strb  = w_strb;
                t.resp  = vif.bresp;
                ap.write(t);
            end
        end
    end
    endtask

    // Read: catch AR, send when the R handshake happens
    task watch_reads();
        logic [7:0] ar_addr;
        axil_item t;
    begin
        forever begin
            @(posedge vif.clk);
            if(vif.resetn !== 1'b1) continue;

            if(vif.arvalid && vif.arready) ar_addr = vif.araddr;

            if(vif.rvalid && vif.rready) begin
                t = axil_item::type_id::create("rd");
                t.write = 0;
                t.addr  = ar_addr;
                t.data  = vif.rdata;
                t.strb  = 4'h0;
                t.resp  = vif.rresp;
                ap.write(t);
            end
        end
    end
    endtask

endclass
