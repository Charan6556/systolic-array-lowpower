module pe_array (
    input logic clk, resetn, en, clr_acc, clr_pipe,
    input logic signed [7:0] a_in [0:3],
    input logic signed [7:0] b_in [0:3],
    output logic signed [31:0] c_out [0:3][0:3]
);

logic signed [7:0] a_wire [0:3][0:3];
logic signed [7:0] b_wire [0:3][0:3];

genvar i, j;

generate
    for(i = 0; i < 4; i++) begin : ROW
        for(j = 0; j < 4; j++) begin : COL

            pe PE (
                .clk(clk),
                .resetn(resetn),
                .en(en),
                .clr_acc(clr_acc),
                .clr_pipe(clr_pipe),
                .a_in(j == 0 ? a_in[i] : a_wire[i][j-1]),
                .b_in(i == 0 ? b_in[j] : b_wire[i-1][j]),
                .a_out(a_wire[i][j]),
                .b_out(b_wire[i][j]),
                .acc(c_out[i][j])
            );

        end
    end
endgenerate

endmodule
