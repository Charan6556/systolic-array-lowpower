
module output_buffer (
    input logic clk, resetn, capture,
    input logic signed [31:0] c_in [0:3][0:3],
    output logic signed [31:0] c_out [0:3][0:3]
);

genvar i, j;

generate
    for(i = 0; i < 4; i++) begin : ROW
        for(j = 0; j < 4; j++) begin : COL

            always_ff @(posedge clk or negedge resetn)
            begin
                if(!resetn)
                    c_out[i][j] <= 32'sd0;
                else if(capture)
                    c_out[i][j] <= c_in[i][j];
            end

        end
    end
endgenerate

endmodule

