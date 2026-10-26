module data_feeder (
    input logic en,
    input logic [3:0] count,
    input logic signed [7:0] rd_data_a [0:3],
    input logic signed [7:0] rd_data_b [0:3],
    output logic [3:0] rd_addr_a [0:3],
    output logic [3:0] rd_addr_b [0:3],
    output logic signed [7:0] a_out [0:3],
    output logic signed [7:0] b_out [0:3]
);

logic valid_a [0:3];
logic valid_b [0:3];

// Address generation
always_comb
begin
    for(int i = 0; i < 4; i++) begin
        int k_a;
        k_a = int'(count) - i;

        if(en && k_a >= 0 && k_a < 4) begin
            rd_addr_a[i] = 4'(4*i + k_a);
            valid_a[i] = 1'b1;
        end
        else begin
            rd_addr_a[i] = 4'd0;
            valid_a[i] = 1'b0;
        end
    end

    for(int j = 0; j < 4; j++) begin
        int k_b;
        k_b = int'(count) - j;

        if(en && k_b >= 0 && k_b < 4) begin
            rd_addr_b[j] = 4'(4*k_b + j);
            valid_b[j] = 1'b1;
        end
        else begin
            rd_addr_b[j] = 4'd0;
            valid_b[j] = 1'b0;
        end
    end
end

// Zero padding
always_comb
begin
    for(int m = 0; m < 4; m++) begin

        if(valid_a[m])
            a_out[m] = rd_data_a[m];
        else
            a_out[m] = 8'sd0;

        if(valid_b[m])
            b_out[m] = rd_data_b[m];
        else
            b_out[m] = 8'sd0;
    end
end

endmodule
