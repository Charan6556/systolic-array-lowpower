// axil_item.sv - one AXI4-Lite read or write
class axil_item extends uvm_sequence_item;

    // Request
    rand bit          write;      // 1 = write, 0 = read
    rand logic [7:0]  addr;
    rand logic [31:0] data;       // write data, or read data filled in after the read
    rand logic [3:0]  strb;

    // Timing knobs
    rand int unsigned wr_order;   // 0 = AW+W together, 1 = AW first, 2 = W first
    rand int unsigned bp_delay;   // BREADY/RREADY delay

    // Response
    logic [1:0] resp;

    constraint c_align { addr[1:0] == 2'b00; }
    constraint c_order { wr_order inside {[0:2]}; }
    constraint c_delay { bp_delay inside {[0:3]}; }
    constraint c_strb  { soft strb == 4'hF; }

    `uvm_object_utils(axil_item)

    function new(string name = "axil_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("%s addr=0x%02h data=0x%08h strb=%b resp=%0d",
                         write ? "WR" : "RD", addr, data, strb, resp);
    endfunction

endclass
