// mm_seqs.sv - sequences (the "programs" the tests run)

// Base: helper tasks for one write / one read
class mm_base_seq extends uvm_sequence #(axil_item);
    `uvm_object_utils(mm_base_seq)

    bit rand_timing = 0;      // 1 = random wr_order / bp_delay on every item

    function new(string name = "mm_base_seq");
        super.new(name);
    endfunction

    task wr(input logic [7:0] addr, input logic [31:0] data,
            input logic [3:0] strb = 4'hF, output logic [1:0] resp);
        axil_item t;
    begin
        t = axil_item::type_id::create("t");
        start_item(t);
        if(!t.randomize() with { write == 1; addr == local::addr;
                                 data == local::data; strb == local::strb; })
            `uvm_fatal("RAND", "write randomize failed")
        if(!rand_timing) begin t.wr_order = 0; t.bp_delay = 0; end
        finish_item(t);
        resp = t.resp;
    end
    endtask

    task rd(input logic [7:0] addr, output logic [31:0] data, output logic [1:0] resp);
        axil_item t;
    begin
        t = axil_item::type_id::create("t");
        start_item(t);
        if(!t.randomize() with { write == 0; addr == local::addr; })
            `uvm_fatal("RAND", "read randomize failed")
        if(!rand_timing) begin t.wr_order = 0; t.bp_delay = 0; end
        finish_item(t);
        data = t.data;
        resp = t.resp;
    end
    endtask

    // Power down the array: write PWR_CTRL=1, poll until OFF (bit5)
    task power_down();
        logic [31:0] st;
        logic [1:0]  r;
        int polls;
    begin
        wr(8'h34, 32'h1, 4'h1, r);
        polls = 0;
        do begin
            rd(8'h34, st, r);
            polls++;
        end while(!st[5] && polls <= 100);
        if(!st[5]) `uvm_error("SEQ", "TIMEOUT waiting for array OFF")
    end
    endtask

    // Power up the array: write PWR_CTRL=0, poll until ON (bit4)
    task power_up();
        logic [31:0] st;
        logic [1:0]  r;
        int polls;
    begin
        wr(8'h34, 32'h0, 4'h1, r);
        polls = 0;
        do begin
            rd(8'h34, st, r);
            polls++;
        end while(!st[4] && polls <= 100);
        if(!st[4]) `uvm_error("SEQ", "TIMEOUT waiting for array ON")
    end
    endtask

endclass

// Register checks: ID, STATUS, SLVERR, read-only, CTRL readback
class mm_reg_seq extends mm_base_seq;
    `uvm_object_utils(mm_reg_seq)

    function new(string name = "mm_reg_seq");
        super.new(name);
    endfunction

    task body();
        logic [31:0] d;
        logic [1:0]  r;
    begin
        rd(8'h08, d, r);                     // ID
        rd(8'h04, d, r);                     // STATUS
        rd(8'h0C, d, r);                     // unmapped -> SLVERR
        rd(8'h30, d, r);
        rd(8'h80, d, r);
        wr(8'h30, 32'hDEADBEEF, 4'hF, r);    // unmapped write -> SLVERR
        wr(8'h04, 32'hFFFFFFFF, 4'hF, r);    // read-only, ignored
        rd(8'h04, d, r);
        wr(8'h00, 32'h6, 4'h1, r);           // IRQ_EN + ACCUM, no START
        rd(8'h00, d, r);                     // readback
        wr(8'h00, 32'h0, 4'h1, r);
    end
    endtask

endclass

// One matrix multiply: load A, B -> START -> poll -> read C
class mm_matmul_seq extends mm_base_seq;
    `uvm_object_utils(mm_matmul_seq)

    rand logic signed [7:0] A [0:3][0:3];
    rand logic signed [7:0] B [0:3][0:3];
    bit acc = 0;
    bit skip_load = 0;          // 1 = keep current A/B in the DUT

    function new(string name = "mm_matmul_seq");
        super.new(name);
    endfunction

    task load_matrices();
        logic [1:0] r;
    begin
        for(int i = 0; i < 4; i++) begin
            wr(8'(8'h10 + 4*i), {A[i][3], A[i][2], A[i][1], A[i][0]}, 4'hF, r);
            wr(8'(8'h20 + 4*i), {B[i][3], B[i][2], B[i][1], B[i][0]}, 4'hF, r);
        end
    end
    endtask

    task start_run();
        logic [1:0] r;
    begin
        wr(8'h00, {29'd0, acc, 1'b0, 1'b1}, 4'h1, r);
    end
    endtask

    task wait_done();
        logic [31:0] st;
        logic [1:0]  r;
        int polls;
    begin
        polls = 0;
        do begin
            rd(8'h04, st, r);
            polls++;
        end while(!st[1] && polls <= 100);
        if(!st[1]) `uvm_error("SEQ", "TIMEOUT waiting for DONE")
    end
    endtask

    task read_results();
        logic [31:0] d;
        logic [1:0]  r;
    begin
        for(int idx = 0; idx < 16; idx++)
            rd(8'(8'h40 + 4*idx), d, r);
    end
    endtask

    task body();
    begin
        if(!skip_load) load_matrices();
        start_run();
        wait_done();
        read_results();
    end
    endtask

endclass

// WSTRB: change one byte of A row 0, then run
class mm_wstrb_seq extends mm_matmul_seq;
    `uvm_object_utils(mm_wstrb_seq)

    function new(string name = "mm_wstrb_seq");
        super.new(name);
    endfunction

    task body();
        logic [1:0] r;
    begin
        load_matrices();
        wr(8'h10, {16'd0, 8'hB3, 8'd0}, 4'b0010, r);    // A[0][1] = -77 only
        start_run();
        wait_done();
        read_results();
    end
    endtask

endclass

// Write while busy must be dropped
class mm_busy_write_seq extends mm_matmul_seq;
    `uvm_object_utils(mm_busy_write_seq)

    function new(string name = "mm_busy_write_seq");
        super.new(name);
    endfunction

    task body();
        logic [1:0] r;
    begin
        load_matrices();
        start_run();
        wr(8'h10, 32'h7F7F7F7F, 4'hF, r);                // during the run: ignored
        wait_done();
        read_results();
    end
    endtask

endclass

// ---------------- Low-power sequences ----------------

// Compute -> power down -> C still readable -> START refused -> power up -> compute again
class mm_lp_cycle_seq extends mm_matmul_seq;
    `uvm_object_utils(mm_lp_cycle_seq)

    function new(string name = "mm_lp_cycle_seq");
        super.new(name);
    endfunction

    task body();
        logic [1:0] r;
    begin
        // 1. Normal run
        load_matrices();
        start_run();
        wait_done();
        read_results();

        // 2. Power down, results must still be readable (output buffer is always on)
        power_down();
        read_results();

        // 3. START while the array is off must be refused (SLVERR), C unchanged
        wr(8'h00, 32'h1, 4'h1, r);
        read_results();

        // 4. Power up, new matrices, run again
        power_up();
        if(!this.randomize()) `uvm_fatal("RAND", "randomize failed")
        load_matrices();
        start_run();
        wait_done();
        read_results();
    end
    endtask

endclass

// Accumulate across a power cycle: C = A1*B1 + A2*B2 needs retention
class mm_lp_accum_seq extends mm_matmul_seq;
    `uvm_object_utils(mm_lp_accum_seq)

    function new(string name = "mm_lp_accum_seq");
        super.new(name);
    endfunction

    task body();
    begin
        // Run 1: normal mode
        acc = 0;
        load_matrices();
        start_run();
        wait_done();
        read_results();

        // Power cycle between the two runs
        power_down();
        power_up();

        // Run 2: accumulate mode, adds onto the retained accumulators
        if(!this.randomize()) `uvm_fatal("RAND", "randomize failed")
        acc = 1;
        load_matrices();
        start_run();
        wait_done();
        read_results();
    end
    endtask

endclass

// Power-down request while busy: must wait for the run to finish
class mm_lp_busy_seq extends mm_matmul_seq;
    `uvm_object_utils(mm_lp_busy_seq)

    function new(string name = "mm_lp_busy_seq");
        super.new(name);
    endfunction

    task body();
    begin
        acc = 0;
        load_matrices();
        start_run();
        power_down();          // requested during the run, completes after it
        wait_done();
        read_results();        // run must have finished correctly
        power_up();
    end
    endtask

endclass
