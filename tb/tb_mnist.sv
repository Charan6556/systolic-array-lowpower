`timescale 1ns/1ps

// MNIST CNN testbench
// Accelerator: all multiply-accumulates
// Testbench: im2col, tiling, bias, requant, ReLU, pool, argmax
// Every layer checked against the Python answer key present in hex files (exp_*.hex)

module tb_mnist;

`include "mnist_params.svh"          // N_IMG, SHIFT, M1, M2

// Clock and reset
logic clk, resetn;
initial clk = 0;
always #2 clk = ~clk;                // 250 MHz

longint cycle;
always @(posedge clk) cycle++;

// AXI4-Lite signals
logic [7:0]  awaddr;  logic awvalid, awready;
logic [31:0] wdata;   logic [3:0] wstrb;  logic wvalid, wready;
logic [1:0]  bresp;   logic bvalid, bready;
logic [7:0]  araddr;  logic arvalid, arready;
logic [31:0] rdata;   logic [1:0] rresp;  logic rvalid, rready;
logic        irq;

// Accelerator
matmul_axil_top DUT (
    .clk(clk), .resetn(resetn),
    .awaddr(awaddr), .awvalid(awvalid), .awready(awready),
    .wdata(wdata), .wstrb(wstrb), .wvalid(wvalid), .wready(wready),
    .bresp(bresp), .bvalid(bvalid), .bready(bready),
    .araddr(araddr), .arvalid(arvalid), .arready(arready),
    .rdata(rdata), .rresp(rresp), .rvalid(rvalid), .rready(rready),
    .irq(irq)
);

// Memories for hex files
logic [7:0]  img_mem    [0:N_IMG*784-1];    // pixels 0..127
logic [7:0]  label_mem  [0:N_IMG-1];        // true digits
logic [7:0]  w1_mem     [0:12*8-1];         // conv1 weights 12 x 8
logic [31:0] b1_mem     [0:7];
logic [7:0]  w2_mem     [0:72*8-1];         // conv2 weights 72 x 8
logic [31:0] b2_mem     [0:7];
logic [7:0]  w3_mem     [0:200*12-1];       // dense weights 200 x 12
logic [31:0] b3_mem     [0:11];
logic [31:0] exp_acc1   [0:N_IMG*5408-1];   // answer key
logic [7:0]  exp_a1     [0:N_IMG*1352-1];
logic [31:0] exp_acc2   [0:N_IMG*968-1];
logic [7:0]  exp_a2     [0:N_IMG*200-1];
logic [31:0] exp_scores [0:N_IMG*12-1];
logic [7:0]  exp_pred   [0:N_IMG-1];

// Work arrays
int A      [0:8999];     // left matrix  (M x K), row-major
int B      [0:2399];     // right matrix (K x N), row-major
int C      [0:5407];     // result       (M x N), row-major
int a1     [0:1351];     // after conv1 + pool : 13 x 13 x 8
int a2     [0:199];      // after conv2 + pool :  5 x  5 x 8
int scores [0:11];       // dense output (10 real + 2 padding)

int runs, errors;

// AXI write
task automatic axi_write(input logic [7:0] addr, input logic [31:0] data);
    @(negedge clk);
    awaddr = addr;  awvalid = 1;
    wdata  = data;  wstrb   = 4'hF;  wvalid = 1;
    bready = 1;
    while(!(awready && wready)) @(negedge clk);   // wait for ready
    @(negedge clk);                                // accepted
    awvalid = 0;  wvalid = 0;
    while(!bvalid) @(negedge clk);                 // wait for response
    @(negedge clk);
    bready = 0;
endtask

// AXI read
task automatic axi_read(input logic [7:0] addr, output logic [31:0] data);
    @(negedge clk);
    araddr = addr;  arvalid = 1;
    rready = 1;
    while(!arready) @(negedge clk);                // wait for ready
    @(negedge clk);                                // accepted
    arvalid = 0;
    while(!rvalid) @(negedge clk);                 // wait for data
    data = rdata;
    @(negedge clk);
    rready = 0;
endtask

// Matrix multiply C = A x B in 4x4 tiles (M, K, N multiples of 4)
task automatic matmul(input int M, input int K, input int N);
    logic [31:0] word, value;
    for(int ti = 0; ti < M/4; ti++)
    for(int tj = 0; tj < N/4; tj++) begin
        for(int tk = 0; tk < K/4; tk++) begin
            // A tile
            for(int r = 0; r < 4; r++) begin
                for(int c = 0; c < 4; c++)
                    word[8*c +: 8] = 8'(A[(4*ti + r)*K + 4*tk + c]);
                axi_write(8'(8'h10 + 4*r), word);
            end
            // B tile
            for(int r = 0; r < 4; r++) begin
                for(int c = 0; c < 4; c++)
                    word[8*c +: 8] = 8'(B[(4*tk + r)*N + 4*tj + c]);
                axi_write(8'(8'h20 + 4*r), word);
            end
            // Start (accumulate after first k step)
            axi_write(8'h00, (tk == 0) ? 32'h3 : 32'h7);
            while(!irq) @(negedge clk);            // wait for interrupt
            runs++;
        end
        // Read 4x4 result
        for(int i = 0; i < 16; i++) begin
            axi_read(8'(8'h40 + 4*i), value);
            C[(4*ti + i/4)*N + 4*tj + i%4] = value;
        end
    end
endtask

// Requant int32 -> int8, with ReLU
function automatic int requant(input int acc, input longint M);
    longint v;
    v = (longint'(acc) * M + (longint'(1) << (SHIFT-1))) >>> SHIFT;
    if(v < 0)   v = 0;           // ReLU
    if(v > 127) v = 127;         // int8 clamp
    return int'(v);
endfunction

// Compare with answer key
task automatic check(input string name, input int got, input int exp, input int i);
    if(got != exp) begin
        errors++;
        if(errors <= 10)
            $display("  MISMATCH %s[%0d]: got %0d, expected %0d", name, i, got, exp);
    end
endtask

// Draw digit in terminal
task automatic show_digit(input int n);
    string ramp = " .:-=+*#%@";
    string line;
    for(int y = 0; y < 28; y++) begin
        line = "";
        for(int x = 0; x < 28; x++) begin
            int c = img_mem[n*784 + y*28 + x] * 9 / 127;
            line = $sformatf("%s%c%c", line, ramp[c], ramp[c]);
        end
        $display("    %s", line);
    end
endtask

// One image through the CNN
task automatic run_image(input int n, output int pred);
    int best, v, p;

    // Conv1 (im2col: 676 patches x 12)
    for(int y = 0; y < 26; y++)
    for(int x = 0; x < 26; x++)
    for(int k = 0; k < 12; k++)
        A[(y*26 + x)*12 + k] = (k < 9) ? img_mem[n*784 + (y + k/3)*28 + x + k%3] : 0;
    for(int i = 0; i < 96; i++)  B[i] = $signed(w1_mem[i]);
    matmul(676, 12, 8);
    for(int i = 0; i < 5408; i++) check("acc1", C[i], $signed(exp_acc1[n*5408 + i]), i);

    // Bias, requant, ReLU, maxpool -> 13x13x8
    for(int y = 0; y < 13; y++)
    for(int x = 0; x < 13; x++)
    for(int c = 0; c < 8; c++) begin
        best = 0;
        for(int dy = 0; dy < 2; dy++)
        for(int dx = 0; dx < 2; dx++) begin
            v = requant(C[((2*y + dy)*26 + 2*x + dx)*8 + c] + $signed(b1_mem[c]), M1);
            if(v > best) best = v;
        end
        a1[(y*13 + x)*8 + c] = best;
    end
    for(int i = 0; i < 1352; i++) check("a1", a1[i], exp_a1[n*1352 + i], i);

    // Conv2 (im2col: 124 patches x 72)
    for(int i = 0; i < 124*72; i++) A[i] = 0;
    for(int y = 0; y < 11; y++)
    for(int x = 0; x < 11; x++)
    for(int k = 0; k < 72; k++)          // k = (kh*3 + kw)*8 + c
        A[(y*11 + x)*72 + k] = a1[((y + k/24)*13 + x + (k/8)%3)*8 + k%8];
    for(int i = 0; i < 576; i++)  B[i] = $signed(w2_mem[i]);
    matmul(124, 72, 8);
    for(int i = 0; i < 968; i++) check("acc2", C[i], $signed(exp_acc2[n*968 + i]), i);

    // Bias, requant, ReLU, maxpool -> 5x5x8
    for(int y = 0; y < 5; y++)
    for(int x = 0; x < 5; x++)
    for(int c = 0; c < 8; c++) begin
        best = 0;
        for(int dy = 0; dy < 2; dy++)
        for(int dx = 0; dx < 2; dx++) begin
            v = requant(C[((2*y + dy)*11 + 2*x + dx)*8 + c] + $signed(b2_mem[c]), M2);
            if(v > best) best = v;
        end
        a2[(y*5 + x)*8 + c] = best;
    end
    for(int i = 0; i < 200; i++) check("a2", a2[i], exp_a2[n*200 + i], i);

    // Dense (1 x 200, padded to 4 rows)
    for(int i = 0; i < 4*200; i++) A[i] = 0;
    for(int k = 0; k < 200; k++)   A[k] = a2[k];
    for(int i = 0; i < 2400; i++)  B[i] = $signed(w3_mem[i]);
    matmul(4, 200, 12);
    for(int d = 0; d < 12; d++) begin
        scores[d] = C[d] + $signed(b3_mem[d]);
        check("scores", scores[d], $signed(exp_scores[n*12 + d]), d);
    end

    // Argmax
    pred = 0;
    for(int d = 1; d < 10; d++)
        if(scores[d] > scores[pred]) pred = d;
    check("pred", pred, exp_pred[n], 0);
endtask

// Main
string  dir;
int     n_img, pred, n_correct, n_exact, err_before;
longint c0, img_cycles, total_cycles;

initial begin
    $timeformat(-9, 0, " ns", 0);
    awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0;
    awaddr = 0; wdata = 0; wstrb = 0; araddr = 0;

    if(!$value$plusargs("DATA=%s", dir)) dir = "app/mnist_cnn_data";
    if(!$value$plusargs("N_IMG=%d", n_img) || n_img > N_IMG) n_img = N_IMG;

    $readmemh({dir, "/img.hex"},        img_mem);
    $readmemh({dir, "/labels.hex"},     label_mem);
    $readmemh({dir, "/w1.hex"},         w1_mem);
    $readmemh({dir, "/b1.hex"},         b1_mem);
    $readmemh({dir, "/w2.hex"},         w2_mem);
    $readmemh({dir, "/b2.hex"},         b2_mem);
    $readmemh({dir, "/w3.hex"},         w3_mem);
    $readmemh({dir, "/b3.hex"},         b3_mem);
    $readmemh({dir, "/exp_acc1.hex"},   exp_acc1);
    $readmemh({dir, "/exp_a1.hex"},     exp_a1);
    $readmemh({dir, "/exp_acc2.hex"},   exp_acc2);
    $readmemh({dir, "/exp_a2.hex"},     exp_a2);
    $readmemh({dir, "/exp_scores.hex"}, exp_scores);
    $readmemh({dir, "/exp_pred.hex"},   exp_pred);

    resetn = 0;
    repeat(5) @(posedge clk);
    resetn = 1;

    for(int n = 0; n < n_img; n++) begin
        err_before = errors;
        c0 = cycle;
        runs = 0;
        run_image(n, pred);
        img_cycles = cycle - c0;
        total_cycles += img_cycles;
        if(pred == label_mem[n])   n_correct++;
        if(errors == err_before)   n_exact++;

        $display("");
        $display("========== Xcelium RTL simulation : image %0d / %0d ==========", n + 1, n_img);
        show_digit(n);
        $display("    Label %0d   Predicted %0d   %s   Bit-exact vs Python: %s",
                 label_mem[n], pred, (pred == label_mem[n]) ? "[CORRECT]" : "[WRONG]",
                 (errors == err_before) ? "YES" : "NO");
        $display("    Scores: %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                 scores[0], scores[1], scores[2], scores[3], scores[4],
                 scores[5], scores[6], scores[7], scores[8], scores[9]);
        $display("    Accelerator runs: %0d   Cycles: %0d", runs, img_cycles);
    end

    $display("");
    $display("================ SUMMARY ================");
    $display("Images            : %0d", n_img);
    $display("Correct vs label  : %0d / %0d", n_correct, n_img);
    $display("Bit-exact images  : %0d / %0d   (mismatches: %0d)", n_exact, n_img, errors);
    $display("Cycles per image  : %0d (average)", total_cycles / n_img);
    $display("Simulated time    : %0t", $time);
    $display("=========================================");
    $finish;
end

endmodule
