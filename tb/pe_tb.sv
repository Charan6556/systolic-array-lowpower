module tb_top;

logic clk;
logic resetn;
logic en;
logic clr_acc;
logic signed [7:0]  a_in;
logic signed [7:0]  b_in;
logic signed [31:0] acc;
logic signed [7:0]  a_out;
logic signed [7:0]  b_out;

pe DUT (
	.clk(clk),
	.resetn(resetn),
	.en(en),
	.clr_acc(clr_acc),
	.a_in(a_in),
	.b_in(b_in),
	.acc(acc),
	.a_out(a_out),
	.b_out(b_out)
);
 
initial begin
	clk=0;
end
  
always #5 clk = ~clk;

initial begin
	resetn = 0;
	en = 0;
	clr_acc = 0;
	a_in = 0;
	b_in = 0;

	#12 resetn =1;

        @(negedge clk);
	en = 1;
        a_in = 2;
        b_in = 4;

        @(negedge clk);
	en =1;
        a_in = 4;
        b_in = -5;

	@(negedge clk);
	en=0;

	//clear accumulator
	@(negedge clk);
	clr_acc=1;
	en = 1;
	a_in = 3;
	b_in =4;

	@(negedge clk)
	clr_acc =0;
	a_in =4;
	b_in=5;

	@(negedge clk);
	en=0;

	@(negedge clk);
	clr_acc =1;


	#20; 
	$finish;
end

always @(posedge clk)
begin
	

	$display("time=%0t resetn=%d, en=%d, clr_acc=%d, a_in=%d, b_in=%d, product=%d, sum=%d, acc=%0d, a_out=%d, b_out=%d", $time,resetn, en, clr_acc, a_in, b_in, DUT.product, DUT.sum, acc, a_out, b_out);
 end

endmodule





