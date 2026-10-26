// mm_tests.sv - tests

// Base test: builds env, runs run_seqs() with an objection
class mm_base_test extends uvm_test;
    `uvm_component_utils(mm_base_test)

    mm_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = mm_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_seqs();
        #100;
        phase.drop_objection(this);
    endtask

    virtual task run_seqs();
    endtask

    // Helper: one matmul with given mode
    task run_matmul(bit acc, bit rand_timing);
        mm_matmul_seq s;
    begin
        s = mm_matmul_seq::type_id::create("s");
        if(!s.randomize()) `uvm_fatal("RAND", "matmul randomize failed")
        s.acc = acc;
        s.rand_timing = rand_timing;
        s.start(env.agt.sqr);
    end
    endtask

    // UVM error count -> PASS/FAIL line
    function void report_phase(uvm_phase phase);
        uvm_report_server rs;
        rs = uvm_report_server::get_server();
        if(rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL) == 0)
            $display("*** TEST PASSED ***");
        else
            $display("*** TEST FAILED ***");
    endfunction

endclass

// Smoke: identity x B
class mm_smoke_test extends mm_base_test;
    `uvm_component_utils(mm_smoke_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_seqs();
        mm_matmul_seq s;
    begin
        s = mm_matmul_seq::type_id::create("s");
        if(!s.randomize()) `uvm_fatal("RAND", "randomize failed")
        for(int i = 0; i < 4; i++)
            for(int j = 0; j < 4; j++)
                s.A[i][j] = (i == j) ? 8'sd1 : 8'sd0;
        s.start(env.agt.sqr);
    end
    endtask

endclass

// Full regression: registers, corners, random with timing, accumulate, WSTRB, busy
class mm_full_test extends mm_base_test;
    `uvm_component_utils(mm_full_test)

    int unsigned n_random = 100;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_seqs();
        mm_reg_seq        rs;
        mm_matmul_seq     s;
        mm_wstrb_seq      ws;
        mm_busy_write_seq bs;
    begin
        void'($value$plusargs("N_RANDOM=%d", n_random));

        // 1. Registers
        rs = mm_reg_seq::type_id::create("rs");
        rs.start(env.agt.sqr);

        // 2. Corner values
        s = mm_matmul_seq::type_id::create("s");
        for(int i = 0; i < 4; i++)
            for(int j = 0; j < 4; j++) begin
                s.A[i][j] = -8'sd128;
                s.B[i][j] = -8'sd128;
            end
        s.start(env.agt.sqr);

        s = mm_matmul_seq::type_id::create("s");
        for(int i = 0; i < 4; i++)
            for(int j = 0; j < 4; j++) begin
                s.A[i][j] = 8'sd127;
                s.B[i][j] = -8'sd128;
            end
        s.start(env.agt.sqr);

        // 3. Random with random AW/W order and backpressure
        repeat(n_random) run_matmul(0, 1);

        // 4. Accumulate: C = A1*B1 + A2*B2
        run_matmul(0, 0);
        run_matmul(1, 0);

        // 5. WSTRB single byte
        ws = mm_wstrb_seq::type_id::create("ws");
        if(!ws.randomize()) `uvm_fatal("RAND", "randomize failed")
        ws.start(env.agt.sqr);

        // 6. Write while busy
        bs = mm_busy_write_seq::type_id::create("bs");
        if(!bs.randomize()) `uvm_fatal("RAND", "randomize failed")
        bs.start(env.agt.sqr);
    end
    endtask

endclass

// Low-power test: power cycles, retention, START protection
class mm_lp_test extends mm_base_test;
    `uvm_component_utils(mm_lp_test)

    int unsigned n_cycles = 20;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_seqs();
        mm_lp_cycle_seq cs;
        mm_lp_accum_seq as;
        mm_lp_busy_seq  bs;
    begin
        void'($value$plusargs("N_CYCLES=%d", n_cycles));

        // 1. Normal run first (power not touched)
        run_matmul(0, 0);

        // 2. Power cycle with START refused while off
        cs = mm_lp_cycle_seq::type_id::create("cs");
        if(!cs.randomize()) `uvm_fatal("RAND", "randomize failed")
        cs.start(env.agt.sqr);

        // 3. Accumulate across a power cycle (retention)
        as = mm_lp_accum_seq::type_id::create("as");
        if(!as.randomize()) `uvm_fatal("RAND", "randomize failed")
        as.start(env.agt.sqr);

        // 4. Power-down request while busy
        bs = mm_lp_busy_seq::type_id::create("bs");
        if(!bs.randomize()) `uvm_fatal("RAND", "randomize failed")
        bs.start(env.agt.sqr);

        // 5. Many random power cycles with random timing
        repeat(n_cycles) begin
            cs = mm_lp_cycle_seq::type_id::create("cs");
            if(!cs.randomize()) `uvm_fatal("RAND", "randomize failed")
            cs.rand_timing = 1;
            cs.start(env.agt.sqr);
        end

        // 6. Normal runs still work at the end
        repeat(5) run_matmul(0, 1);
    end
    endtask

endclass
