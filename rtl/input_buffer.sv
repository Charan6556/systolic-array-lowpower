module input_buffer (
	input logic clk, resetn,
	input logic wr_en_a, wr_en_b,
	input logic [1:0] wr_row_a, wr_row_b,
	input logic [31:0] wr_data_a, wr_data_b,
	input logic [3:0] wr_strb_a, wr_strb_b,
	input logic [3:0] rd_addr_a [0:3],
	input logic [3:0] rd_addr_b [0:3],
	output logic signed [7:0] rd_data_a [0:3],
	output logic signed [7:0] rd_data_b [0:3]
);

logic signed [7:0] mem_a [0:15];
logic signed [7:0] mem_b [0:15];

// Write logic
always_ff @(posedge clk or negedge resetn)
begin
	if(!resetn) begin
		for(int k = 0; k < 16; k++) begin
			mem_a[k] <= 8'sd0;
			mem_b[k] <= 8'sd0;
		end
	end
	else begin
		for(int b = 0; b < 4; b++) begin
			if(wr_en_a && wr_strb_a[b])
				mem_a[4*wr_row_a + b] <= wr_data_a[8*b +: 8];
			if(wr_en_b && wr_strb_b[b])
				mem_b[4*wr_row_b + b] <= wr_data_b[8*b +: 8];
		end
	end
end

// Read logic
genvar i;

generate
  for(i=0; i<4; i++) begin
	  assign rd_data_a[i] = mem_a[rd_addr_a[i]];
	  assign rd_data_b[i] = mem_b[rd_addr_b[i]];
  end
endgenerate

endmodule
