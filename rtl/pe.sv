module pe (
	input  logic clk, resetn, en,
	input  logic clr_acc, clr_pipe,
	input  logic signed [7:0] a_in, b_in,
	output logic signed [7:0] a_out, b_out,
	output logic signed [31:0] acc
);

wire signed [15:0] product;
wire signed [31:0] sum;

assign product = a_in*b_in;
assign sum     = acc + {{16{product[15]}}, product};

// Accumulator
always_ff@(posedge clk or negedge resetn)
begin
	if(!resetn)
		acc <= 32'sd0;
	else if (clr_acc)
		acc <= 32'sd0;
	else if (en)
		acc <= sum;
end

// Pipeline registers
always_ff@(posedge clk or negedge resetn)
begin
	if(!resetn) begin
		a_out <= 8'sd0;
		b_out <= 8'sd0;
	end
	else if(clr_pipe) begin
		a_out <= 8'sd0;
		b_out <= 8'sd0;
	end
	else if(en) begin
		a_out <= a_in;
		b_out <= b_in;
	end
end

endmodule
