// axil_if.sv - AXI4-Lite interface for matmul_axil_top
interface axil_if (input logic clk);

    logic        resetn;

    // Write address channel
    logic [7:0]  awaddr;
    logic        awvalid;
    logic        awready;

    // Write data channel
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;

    // Write response channel
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;

    // Read address channel
    logic [7:0]  araddr;
    logic        arvalid;
    logic        arready;

    // Read data channel
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;

    // Interrupt
    logic        irq;

endinterface
