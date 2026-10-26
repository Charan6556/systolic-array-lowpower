`timescale 1ns/1ps

module tb_matmul_axil;

logic clk, resetn;

// AXI4-Lite signals
logic [7:0]  awaddr;
logic        awvalid, awready;
logic [31:0] wdata;
logic [3:0]  wstrb;
logic        wvalid, wready;
logic [1:0]  bresp;
logic        bvalid, bready;
logic [7:0]  araddr;
logic        arvalid, arready;
logic [31:0] rdata;
logic [1:0]  rresp;
logic        rvalid, rready;
logic        irq;

// Test data
logic signed [7:0]  A [0:3][0:3];
logic signed [7:0]  B [0:3][0:3];
logic signed [31:0] C_exp [0:3][0:3];
logic signed [31:0] C_got [0:3][0:3];

int errors;
int tests;
int wr_order;     // 0 = AW+W together, 1 = AW first, 2 = W first
int bp_delay;     // BREADY/RREADY delay (backpressure)

logic [31:0] data;
logic [1:0]  resp;

// DUT
matmul_axil_top DUT (
    .clk(clk), .resetn(resetn),
    .awaddr(awaddr), .awvalid(awvalid), .awready(awready),
    .wdata(wdata), .wstrb(wstrb), .wvalid(wvalid), .wready(wready),
    .bresp(bresp), .bvalid(bvalid), .bready(bready),
    .araddr(araddr), .arvalid(arvalid), .arready(arready),
    .rdata(rdata), .rresp(rresp), .rvalid(rvalid), .rready(rready),
    .irq(irq)
);

// Clock 250 MHz
initial clk = 0;
always #2 clk = ~clk;

// Result reporting
task automatic result(input string name, input bit ok);
begin
    tests++;
    if(ok)
        $display("PASS %s", name);
    else begin
        $display("FAIL %s", name);
        errors++;
    end
end
endtask

// AXI write (drive on negedge, DUT samples on posedge)
task automatic axi_write(input logic [7:0] addr, input logic [31:0] wd,
                         input logic [3:0] strb, output logic [1:0] r);
bit aw_sent, w_sent, aw_fire, w_fire;
begin
    aw_sent = 0;
    w_sent  = 0;
    @(negedge clk);
    if(wr_order != 2) begin awaddr = addr; awvalid = 1; end
    if(wr_order != 1) begin wdata = wd; wstrb = strb; wvalid = 1; end

    while(!(aw_sent && w_sent)) begin
        aw_fire = awvalid && awready;
        w_fire  = wvalid && wready;
        @(negedge clk);
        if(aw_fire) begin awvalid = 0; aw_sent = 1; end
        if(w_fire)  begin wvalid = 0;  w_sent = 1;  end
        if(aw_sent && !w_sent && !wvalid)  begin wdata = wd; wstrb = strb; wvalid = 1; end
        if(w_sent && !aw_sent && !awvalid) begin awaddr = addr; awvalid = 1; end
    end

    repeat(bp_delay) @(negedge clk);
    bready = 1;
    while(!bvalid) @(negedge clk);
    r = bresp;
    @(negedge clk);
    bready = 0;
end
endtask

// AXI read
task automatic axi_read(input logic [7:0] addr, output logic [31:0] rd,
                        output logic [1:0] r);
begin
    @(negedge clk);
    araddr = addr;
    arvalid = 1;
    while(!arready) @(negedge clk);
    @(negedge clk);
    arvalid = 0;

    repeat(bp_delay) @(negedge clk);
    rready = 1;
    while(!rvalid) @(negedge clk);
    rd = rdata;
    r  = rresp;
    @(negedge clk);
    rready = 0;
end
endtask

// Load A and B rows
task automatic load_matrices();
logic [1:0] r;
begin
    for(int i = 0; i < 4; i++) begin
        axi_write(8'(8'h10 + 4*i), {A[i][3], A[i][2], A[i][1], A[i][0]}, 4'hF, r);
        if(r !== 2'b00) begin $display("  bad BRESP on A row %0d", i); errors++; end
        axi_write(8'(8'h20 + 4*i), {B[i][3], B[i][2], B[i][1], B[i][0]}, 4'hF, r);
        if(r !== 2'b00) begin $display("  bad BRESP on B row %0d", i); errors++; end
    end
end
endtask

// START (bit0), IRQ_EN (bit1), ACCUMULATE (bit2)
task automatic start_run(input bit acc, input bit irq_en);
logic [1:0] r;
begin
    axi_write(8'h00, {29'd0, acc, irq_en, 1'b1}, 4'h1, r);
end
endtask

// Poll STATUS until DONE
task automatic wait_done();
logic [31:0] st;
logic [1:0]  r;
int polls;
begin
    polls = 0;
    do begin
        axi_read(8'h04, st, r);
        polls++;
        if(polls > 100) begin
            $display("  TIMEOUT waiting for DONE");
            errors++;
            break;
        end
    end while(!st[1]);
end
endtask

// Read all 16 results
task automatic read_results();
logic [31:0] rd;
logic [1:0]  r;
begin
    for(int idx = 0; idx < 16; idx++) begin
        axi_read(8'(8'h40 + 4*idx), rd, r);
        C_got[idx/4][idx%4] = rd;
        if(r !== 2'b00) begin $display("  bad RRESP on C[%0d]", idx); errors++; end
    end
end
endtask

// Reference model
task automatic compute_expected(input bit acc_mode);
begin
    for(int i = 0; i < 4; i++)
        for(int j = 0; j < 4; j++) begin
            int sum = 0;
            for(int k = 0; k < 4; k++)
                sum += int'(A[i][k]) * int'(B[k][j]);
            if(acc_mode)
                C_exp[i][j] = C_exp[i][j] + sum;
            else
                C_exp[i][j] = sum;
        end
end
endtask

// Compare C_got against C_exp
function automatic bit results_match(input string name);
int bad;
begin
    bad = 0;
    for(int i = 0; i < 4; i++)
        for(int j = 0; j < 4; j++)
            if(C_got[i][j] !== C_exp[i][j]) begin
                $display("  MISMATCH %s C[%0d][%0d] got=%0d exp=%0d",
                         name, i, j, C_got[i][j], C_exp[i][j]);
                bad++;
            end
    return (bad == 0);
end
endfunction

task automatic fill_random();
begin
    for(int i = 0; i < 4; i++)
        for(int j = 0; j < 4; j++) begin
            A[i][j] = $urandom;
            B[i][j] = $urandom;
        end
end
endtask

// Full matmul through AXI
task automatic run_test(input string name, input bit acc);
begin
    load_matrices();
    compute_expected(acc);
    start_run(acc, 0);
    wait_done();
    read_results();
    result(name, results_match(name));
end
endtask

// Tests
initial begin
    errors = 0; tests = 0;
    wr_order = 0; bp_delay = 0;
    awaddr = 0; awvalid = 0;
    wdata = 0; wstrb = 0; wvalid = 0;
    bready = 0;
    araddr = 0; arvalid = 0;
    rready = 0;

    // Reset
    resetn = 0;
    repeat(5) @(posedge clk);
    @(negedge clk);
    resetn = 1;

    // 1. ID register
    axi_read(8'h08, data, resp);
    result("id_register", data === 32'h4D4D_0001 && resp === 2'b00);

    // 2. STATUS after reset
    axi_read(8'h04, data, resp);
    result("status_reset", data === 32'd0 && resp === 2'b00);

    // 3. SLVERR on unmapped reads
    axi_read(8'h0C, data, resp);
    result("slverr_read_0x0C", resp === 2'b10);
    axi_read(8'h30, data, resp);
    result("slverr_read_0x30", resp === 2'b10);
    axi_read(8'h80, data, resp);
    result("slverr_read_0x80", resp === 2'b10);

    // 4. SLVERR on unmapped write, OKAY on read-only write
    axi_write(8'h30, 32'hDEADBEEF, 4'hF, resp);
    result("slverr_write_0x30", resp === 2'b10);
    axi_write(8'h04, 32'hFFFFFFFF, 4'hF, resp);
    axi_read(8'h04, data, resp);
    result("readonly_status_write", data === 32'd0);

    // 5. CTRL readback (IRQ_EN=1, ACCUMULATE=1, no START)
    axi_write(8'h00, 32'h6, 4'h1, resp);
    axi_read(8'h00, data, resp);
    result("ctrl_readback", data === 32'h6);
    axi_write(8'h00, 32'h0, 4'h1, resp);

    // 6. Identity x B = B
    for(int i = 0; i < 4; i++)
        for(int j = 0; j < 4; j++) begin
            A[i][j] = (i == j) ? 8'sd1 : 8'sd0;
            B[i][j] = $urandom;
        end
    run_test("identity", 0);

    // 7. All -128
    for(int i = 0; i < 4; i++)
        for(int j = 0; j < 4; j++) begin
            A[i][j] = -8'sd128;
            B[i][j] = -8'sd128;
        end
    run_test("all_neg128", 0);

    // 8. 127 x -128
    for(int i = 0; i < 4; i++)
        for(int j = 0; j < 4; j++) begin
            A[i][j] = 8'sd127;
            B[i][j] = -8'sd128;
        end
    run_test("pos127_x_neg128", 0);

    // 9. Random with all AW/W orders and backpressure
    for(int t = 0; t < 100; t++) begin
        wr_order = t % 3;
        bp_delay = $urandom_range(0, 3);
        fill_random();
        run_test($sformatf("random_%0d (order=%0d bp=%0d)", t, wr_order, bp_delay), 0);
    end
    wr_order = 0;
    bp_delay = 0;

    // 10. Accumulate: C = A1*B1 + A2*B2
    fill_random();
    run_test("accum_step1", 0);
    fill_random();
    run_test("accum_step2", 1);

    // 11. WSTRB: update only A[0][1]
    fill_random();
    load_matrices();
    A[0][1] = -8'sd77;
    axi_write(8'h10, {16'd0, A[0][1], 8'd0}, 4'b0010, resp);
    compute_expected(0);
    start_run(0, 0);
    wait_done();
    read_results();
    result("wstrb_single_byte", results_match("wstrb_single_byte"));

    // 12. Write while busy must be dropped
    fill_random();
    load_matrices();
    compute_expected(0);
    start_run(0, 0);
    axi_write(8'h10, 32'h7F7F7F7F, 4'hF, resp);
    wait_done();
    read_results();
    result("write_while_busy", results_match("write_while_busy"));

    // 13. IRQ
    fill_random();
    load_matrices();
    compute_expected(0);
    start_run(0, 1);
    wait_done();
    result("irq_high_when_enabled", irq === 1'b1);
    axi_write(8'h00, 32'h0, 4'h1, resp);
    @(negedge clk);
    result("irq_low_when_disabled", irq === 1'b0);

    // Summary
    $display("----------------------------------------");
    if(errors == 0)
        $display("ALL %0d TESTS PASSED", tests);
    else
        $display("%0d ERRORS in %0d TESTS", errors, tests);
    $display("----------------------------------------");
    $finish;
end

// Timeout
initial begin
    #5000000;
    $display("TIMEOUT");
    $finish;
end

endmodule
