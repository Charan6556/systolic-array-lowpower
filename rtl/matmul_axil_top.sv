module matmul_axil_top (
    input logic clk, resetn,

    // Write address channel
    input logic [7:0] awaddr,
    input logic awvalid,
    output logic awready,

    // Write data channel
    input logic [31:0] wdata,
    input logic [3:0] wstrb,
    input logic wvalid,
    output logic wready,

    // Write response channel
    output logic [1:0] bresp,
    output logic bvalid,
    input logic bready,

    // Read address channel
    input logic [7:0] araddr,
    input logic arvalid,
    output logic arready,

    // Read data channel
    output logic [31:0] rdata,
    output logic [1:0] rresp,
    output logic rvalid,
    input logic rready,

    // Interrupt
    output logic irq
);

localparam logic [1:0]  RESP_OKAY   = 2'b00;
localparam logic [1:0]  RESP_SLVERR = 2'b10;
localparam logic [31:0] ID_VALUE    = 32'h4D4D_0001;

// Write channel registers
logic aw_done, w_done;
logic [7:0] aw_addr_r;
logic [31:0] w_data_r;
logic [3:0] w_strb_r;
logic do_write;
logic [5:0] waddr;

// Write decode
logic wr_ctrl, wr_a, wr_b, wr_err;

// Control registers
logic irq_en_r, accum_r;

// Power control register (0x34) and status
logic wr_pwr;
logic pwr_req_r;
logic pwr_on, pwr_off;

// Start protection
logic start_req, start_blk;

// Read channel
logic [5:0] raddr;

// Core signals
logic core_start;
logic core_wr_en_a, core_wr_en_b;
logic busy, done;
logic signed [31:0] c_out [0:3][0:3];

// Handshake ready signals
assign awready  = !aw_done && !bvalid;
assign wready   = !w_done && !bvalid;
assign arready  = !rvalid;

assign do_write = aw_done && w_done;
assign waddr    = aw_addr_r[7:2];
assign raddr    = araddr[7:2];

// Write address decode
always_comb
begin
    wr_ctrl = 0;
    wr_a = 0;
    wr_b = 0;
    wr_err = 0;
    wr_pwr = 0;

    if(waddr == 6'd0)
        wr_ctrl = 1;                                   // 0x00 CTRL
    else if(waddr == 6'd1 || waddr == 6'd2)
        wr_err = 0;                                    // 0x04 STATUS, 0x08 ID: read-only, ignore
    else if(waddr >= 6'd4 && waddr <= 6'd7)
        wr_a = 1;                                      // 0x10-0x1C A rows
    else if(waddr >= 6'd8 && waddr <= 6'd11)
        wr_b = 1;                                      // 0x20-0x2C B rows
    else if(waddr >= 6'd16 && waddr <= 6'd31)
        wr_err = 0;                                    // 0x40-0x7C C: read-only, ignore
    else if(waddr == 6'd13)
        wr_pwr = 1;                                    // 0x34 PWR_CTRL
    else
        wr_err = 1;                                    // unmapped
end

// Write channel
always_ff @(posedge clk or negedge resetn)
begin
    if(!resetn) begin
        aw_done   <= 1'b0;
        w_done    <= 1'b0;
        aw_addr_r <= 8'd0;
        w_data_r  <= 32'd0;
        w_strb_r  <= 4'd0;
        bvalid    <= 1'b0;
        bresp     <= RESP_OKAY;
    end
    else begin
        // Capture address
        if(awvalid && awready) begin
            aw_addr_r <= awaddr;
            aw_done   <= 1'b1;
        end

        // Capture data
        if(wvalid && wready) begin
            w_data_r <= wdata;
            w_strb_r <= wstrb;
            w_done   <= 1'b1;
        end

        // Perform write and send response
        if(do_write) begin
            aw_done <= 1'b0;
            w_done  <= 1'b0;
            bvalid  <= 1'b1;
            bresp   <= (wr_err || start_blk) ? RESP_SLVERR : RESP_OKAY;
        end
        else if(bvalid && bready)
            bvalid <= 1'b0;
    end
end

// Control register
always_ff @(posedge clk or negedge resetn)
begin
    if(!resetn) begin
        irq_en_r <= 1'b0;
        accum_r  <= 1'b0;
    end
    else if(do_write && wr_ctrl && w_strb_r[0]) begin
        irq_en_r <= w_data_r[1];
        accum_r  <= w_data_r[2];
    end
end

// Power control register: bit0 = 1 power down, 0 power up
always_ff @(posedge clk or negedge resetn)
begin
    if(!resetn)
        pwr_req_r <= 1'b0;
    else if(do_write && wr_pwr && w_strb_r[0])
        pwr_req_r <= w_data_r[0];
end

// Core control
// START is refused (SLVERR) unless the array is fully on and no power-down is requested
assign start_req    = do_write && wr_ctrl && w_strb_r[0] && w_data_r[0];
assign start_blk    = start_req && !(pwr_on && !pwr_req_r);
assign core_start   = start_req;
assign core_wr_en_a = do_write && wr_a;
assign core_wr_en_b = do_write && wr_b;

// Read channel
always_ff @(posedge clk or negedge resetn)
begin
    if(!resetn) begin
        rvalid <= 1'b0;
        rdata  <= 32'd0;
        rresp  <= RESP_OKAY;
    end
    else if(arvalid && arready) begin
        rvalid <= 1'b1;
        rresp  <= RESP_OKAY;

        if(raddr == 6'd0)
            rdata <= {29'd0, accum_r, irq_en_r, 1'b0};             // CTRL (START reads 0)
        else if(raddr == 6'd1)
            rdata <= {30'd0, done, busy};                            // STATUS
        else if(raddr == 6'd2)
            rdata <= ID_VALUE;                                       // ID
        else if(raddr >= 6'd4 && raddr <= 6'd11)
            rdata <= 32'd0;                                          // A/B write-only
        else if(raddr >= 6'd16 && raddr <= 6'd31)
            rdata <= c_out[raddr[3:2]][raddr[1:0]];                  // C[i][j]
        else if(raddr == 6'd13)
            rdata <= {26'd0, pwr_off, pwr_on, 3'd0, pwr_req_r};      // PWR_CTRL
        else begin
            rdata <= 32'd0;
            rresp <= RESP_SLVERR;                                    // unmapped
        end
    end
    else if(rvalid && rready)
        rvalid <= 1'b0;
end

// Interrupt
assign irq = done & irq_en_r;

// Accelerator core
matmul_accelerator U_CORE (
    .clk(clk),
    .resetn(resetn),
    .start(core_start),
    .accumulate(w_data_r[2]),
    .wr_en_a(core_wr_en_a),
    .wr_en_b(core_wr_en_b),
    .wr_row_a(waddr[1:0]),
    .wr_row_b(waddr[1:0]),
    .wr_data_a(w_data_r),
    .wr_data_b(w_data_r),
    .wr_strb_a(w_strb_r),
    .wr_strb_b(w_strb_r),
    .busy(busy),
    .done(done),
    .c_out(c_out),
    .pwr_down_req(pwr_req_r),
    .pwr_on(pwr_on),
    .pwr_off(pwr_off)
);

endmodule
