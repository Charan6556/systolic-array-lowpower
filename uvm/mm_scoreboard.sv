// mm_scoreboard.sv - reference model + checks (sees only what the monitor reports)
class mm_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(mm_scoreboard)

    uvm_analysis_imp #(axil_item, mm_scoreboard) analysis_export;

    localparam logic [1:0]  RESP_OKAY   = 2'b00;
    localparam logic [1:0]  RESP_SLVERR = 2'b10;
    localparam logic [31:0] ID_VALUE    = 32'h4D4D_0001;

    // Shadow model of the accelerator
    logic signed [7:0]  model_A [0:3][0:3];
    logic signed [7:0]  model_B [0:3][0:3];
    logic signed [31:0] exp_C   [0:3][0:3];
    bit irq_en_m, accum_m;
    bit busy_m;            // run started, done not yet seen on STATUS

    // Power model
    bit pwr_req_m;         // PWR_CTRL bit0 as last written
    bit arr_on_m;          // array known to be fully on (from reset or a PWR_CTRL status read)

    int checks;
    int errors;
    int n_wr, n_rd, n_c_reads, n_runs, n_pwr_wr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        analysis_export = new("analysis_export", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        for(int i = 0; i < 4; i++)
            for(int j = 0; j < 4; j++) begin
                model_A[i][j] = 0;
                model_B[i][j] = 0;
                exp_C[i][j]   = 0;
            end
        irq_en_m = 0; accum_m = 0; busy_m = 0;
        pwr_req_m = 0; arr_on_m = 1;
        checks = 0; errors = 0;
        n_wr = 0; n_rd = 0; n_c_reads = 0; n_runs = 0; n_pwr_wr = 0;
    endfunction

    // Pass/fail bookkeeping
    function void sb_check(bit ok, string msg);
        checks++;
        if(!ok) begin
            errors++;
            `uvm_error("SB", msg)
        end
    endfunction

    // Which addresses are mapped (same map for read and write)
    function bit is_mapped(logic [7:0] addr);
        logic [5:0] w;
        w = addr[7:2];
        return (w <= 2) || (w >= 4 && w <= 11) || (w == 13) || (w >= 16 && w <= 31);
    endfunction

    // Reference model: C = A x B  (or C += A x B in accumulate mode)
    function void compute_expected(bit acc_mode);
        int sum;
        for(int i = 0; i < 4; i++)
            for(int j = 0; j < 4; j++) begin
                sum = 0;
                for(int k = 0; k < 4; k++)
                    sum += int'(model_A[i][k]) * int'(model_B[k][j]);
                if(acc_mode)
                    exp_C[i][j] = exp_C[i][j] + sum;
                else
                    exp_C[i][j] = sum;
            end
    endfunction

    // Called by the monitor for every finished transaction
    function void write(axil_item t);
        logic [5:0] w;
        logic [1:0] exp_resp;
        bit is_start, start_blocked;
        w = t.addr[7:2];

        // START is refused unless the array is fully on and no power-down is requested
        is_start      = t.write && (w == 6'd0) && t.strb[0] && t.data[0];
        start_blocked = is_start && !(arr_on_m && !pwr_req_m);

        // Layer 1: response code
        exp_resp = (is_mapped(t.addr) && !start_blocked) ? RESP_OKAY : RESP_SLVERR;
        sb_check(t.resp === exp_resp,
              $sformatf("bad response: %s (expected %0d)", t.convert2string(), exp_resp));

        if(t.write) begin
            n_wr++;
            if(w == 6'd0 && t.strb[0]) begin                       // CTRL
                irq_en_m = t.data[1];
                accum_m  = t.data[2];
                if(t.data[0] && !busy_m && !start_blocked) begin   // START
                    compute_expected(t.data[2]);
                    busy_m = 1;
                    n_runs++;
                end
            end
            else if(w >= 6'd4 && w <= 6'd7 && !busy_m) begin       // A row
                for(int b = 0; b < 4; b++)
                    if(t.strb[b]) model_A[w[1:0]][b] = t.data[8*b +: 8];
            end
            else if(w >= 6'd8 && w <= 6'd11 && !busy_m) begin      // B row
                for(int b = 0; b < 4; b++)
                    if(t.strb[b]) model_B[w[1:0]][b] = t.data[8*b +: 8];
            end
            else if(w == 6'd13 && t.strb[0]) begin                 // PWR_CTRL
                pwr_req_m = t.data[0];
                if(t.data[0]) arr_on_m = 0;                        // powering down
                n_pwr_wr++;
            end
        end
        else begin
            n_rd++;
            if(w == 6'd0)                                          // CTRL readback
                sb_check(t.data === {29'd0, accum_m, irq_en_m, 1'b0},
                      $sformatf("CTRL readback got 0x%08h", t.data));
            else if(w == 6'd1) begin                               // STATUS
                sb_check(t.data[31:2] === 0, $sformatf("STATUS upper bits 0x%08h", t.data));
                if(t.data[1]) busy_m = 0;                          // done seen
            end
            else if(w == 6'd13) begin                              // PWR_CTRL status
                sb_check(t.data[0] === pwr_req_m,
                         $sformatf("PWR_CTRL req bit got %0b exp %0b", t.data[0], pwr_req_m));
                sb_check(t.data[31:6] === 0 && t.data[3:1] === 0,
                         $sformatf("PWR_CTRL reserved bits 0x%08h", t.data));
                sb_check(!(t.data[4] && t.data[5]),
                         $sformatf("PWR_CTRL on and off both set 0x%08h", t.data));
                arr_on_m = t.data[4];
            end
            else if(w == 6'd2)                                     // ID
                sb_check(t.data === ID_VALUE, $sformatf("ID got 0x%08h", t.data));
            else if(w >= 6'd16 && w <= 6'd31) begin                // C[i][j]
                n_c_reads++;
                sb_check(t.data === exp_C[w[3:2]][w[1:0]],
                      $sformatf("C[%0d][%0d] got=%0d exp=%0d",
                                w[3:2], w[1:0], $signed(t.data), exp_C[w[3:2]][w[1:0]]));
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        $display("----------------------------------------");
        $display("Transactions: %0d writes, %0d reads, %0d runs, %0d C reads, %0d power writes",
                 n_wr, n_rd, n_runs, n_c_reads, n_pwr_wr);
        if(errors == 0)
            $display("ALL %0d CHECKS PASSED", checks);
        else
            $display("%0d ERRORS in %0d CHECKS", errors, checks);
        $display("----------------------------------------");
    endfunction

endclass
