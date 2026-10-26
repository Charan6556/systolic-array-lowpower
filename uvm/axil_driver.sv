// axil_driver.sv - turns axil_item into AXI4-Lite pin activity
class axil_driver extends uvm_driver #(axil_item);
    `uvm_component_utils(axil_driver)

    virtual axil_if vif;

    localparam int TIMEOUT = 100;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual axil_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "axil_driver: virtual interface not set")
    endfunction

    task run_phase(uvm_phase phase);
        reset_signals();
        wait(vif.resetn === 1'b1);

        forever begin
            seq_item_port.get_next_item(req);
            if(req.write)
                drive_write(req);
            else
                drive_read(req);
            seq_item_port.item_done();
        end
    endtask

    // All master outputs idle
    task reset_signals();
    begin
        vif.awaddr  = 0;  vif.awvalid = 0;
        vif.wdata   = 0;  vif.wstrb   = 0;  vif.wvalid = 0;
        vif.bready  = 0;
        vif.araddr  = 0;  vif.arvalid = 0;
        vif.rready  = 0;
    end
    endtask

    // AXI write (drive on negedge, DUT samples on posedge)
    task drive_write(axil_item t);
        bit aw_sent, w_sent, aw_fire, w_fire;
        int cycles;
    begin
        aw_sent = 0;
        w_sent  = 0;
        cycles  = 0;
        @(negedge vif.clk);
        if(t.wr_order != 2) begin vif.awaddr = t.addr; vif.awvalid = 1; end
        if(t.wr_order != 1) begin vif.wdata = t.data; vif.wstrb = t.strb; vif.wvalid = 1; end

        while(!(aw_sent && w_sent)) begin
            aw_fire = vif.awvalid && vif.awready;
            w_fire  = vif.wvalid  && vif.wready;
            @(negedge vif.clk);
            if(aw_fire) begin vif.awvalid = 0; aw_sent = 1; end
            if(w_fire)  begin vif.wvalid  = 0; w_sent  = 1; end
            if(aw_sent && !w_sent && !vif.wvalid)  begin vif.wdata = t.data; vif.wstrb = t.strb; vif.wvalid = 1; end
            if(w_sent && !aw_sent && !vif.awvalid) begin vif.awaddr = t.addr; vif.awvalid = 1; end
            cycles++;
            if(cycles > TIMEOUT) begin
                `uvm_error("TIMEOUT", {"write AW/W stuck: ", t.convert2string()})
                vif.awvalid = 0;
                vif.wvalid  = 0;
                return;
            end
        end

        repeat(t.bp_delay) @(negedge vif.clk);
        vif.bready = 1;
        cycles = 0;
        while(!vif.bvalid) begin
            @(negedge vif.clk);
            cycles++;
            if(cycles > TIMEOUT) begin
                `uvm_error("TIMEOUT", {"no BVALID: ", t.convert2string()})
                vif.bready = 0;
                return;
            end
        end
        t.resp = vif.bresp;
        @(negedge vif.clk);
        vif.bready = 0;
    end
    endtask

    // AXI read
    task drive_read(axil_item t);
        int cycles;
    begin
        cycles = 0;
        @(negedge vif.clk);
        vif.araddr  = t.addr;
        vif.arvalid = 1;
        while(!vif.arready) begin
            @(negedge vif.clk);
            cycles++;
            if(cycles > TIMEOUT) begin
                `uvm_error("TIMEOUT", {"no ARREADY: ", t.convert2string()})
                vif.arvalid = 0;
                return;
            end
        end
        @(negedge vif.clk);
        vif.arvalid = 0;

        repeat(t.bp_delay) @(negedge vif.clk);
        vif.rready = 1;
        cycles = 0;
        while(!vif.rvalid) begin
            @(negedge vif.clk);
            cycles++;
            if(cycles > TIMEOUT) begin
                `uvm_error("TIMEOUT", {"no RVALID: ", t.convert2string()})
                vif.rready = 0;
                return;
            end
        end
        t.data = vif.rdata;
        t.resp = vif.rresp;
        @(negedge vif.clk);
        vif.rready = 0;
    end
    endtask

endclass
