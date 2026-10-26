module matmul_accelerator (
    input logic clk, resetn, start,
    input logic accumulate,

    input logic wr_en_a, wr_en_b,
    input logic [1:0] wr_row_a, wr_row_b,
    input logic [31:0] wr_data_a, wr_data_b,
    input logic [3:0] wr_strb_a, wr_strb_b,

    output logic busy, done,
    output logic signed [31:0] c_out [0:3][0:3],

    //power control
    input  logic pwr_down_req,
    output logic pwr_on,
    output logic pwr_off
);

// Power states
typedef enum logic [2:0] {
	PWR_ON,
	PWR_SAVE,
	PWR_ISO,
	PWR_OFF,
	PWR_UP,
	PWR_RESTORE,
	PWR_UNISO
} pwr_state_t;

pwr_state_t pwr_state;
logic [1:0] pwr_wait; //3-cycle wait after switching on

//power control signals
logic lp_pwr_en, lp_iso_en, lp_save, lp_restore;

//start protection
logic start_ok, start_gated;

logic pe_en, clr_acc, clr_pipe;
logic capture;
logic [3:0] count;

logic wr_en_a_gated, wr_en_b_gated;

logic [3:0] rd_addr_a [0:3];
logic [3:0] rd_addr_b [0:3];

logic signed [7:0] rd_data_a [0:3];
logic signed [7:0] rd_data_b [0:3];

logic signed [7:0] a_feed [0:3];
logic signed [7:0] b_feed [0:3];

logic signed [31:0] pe_result [0:3][0:3];

// Write gating (block writes while busy)
assign wr_en_a_gated = wr_en_a & !busy;
assign wr_en_b_gated = wr_en_b & !busy;

// Input buffer
input_buffer U_BUFFER (
    .clk(clk),
    .resetn(resetn),
    .wr_en_a(wr_en_a_gated),
    .wr_en_b(wr_en_b_gated),
    .wr_row_a(wr_row_a),
    .wr_row_b(wr_row_b),
    .wr_data_a(wr_data_a),
    .wr_data_b(wr_data_b),
    .wr_strb_a(wr_strb_a),
    .wr_strb_b(wr_strb_b),
    .rd_addr_a(rd_addr_a),
    .rd_addr_b(rd_addr_b),
    .rd_data_a(rd_data_a),
    .rd_data_b(rd_data_b)
);

// Data feeder
data_feeder U_FEEDER (
    .en(pe_en),
    .count(count),
    .rd_data_a(rd_data_a),
    .rd_data_b(rd_data_b),
    .rd_addr_a(rd_addr_a),
    .rd_addr_b(rd_addr_b),
    .a_out(a_feed),
    .b_out(b_feed)
);

// PE array
pe_array U_ARRAY (
    .clk(clk),
    .resetn(resetn),
    .en(pe_en),
    .clr_acc(clr_acc),
    .clr_pipe(clr_pipe),
    .a_in(a_feed),
    .b_in(b_feed),
    .c_out(pe_result)
);

//start only when the array is fully on and no power down is required
assign start_ok = (pwr_state == PWR_ON) && !pwr_down_req;
assign start_gated = start && start_ok;

// Controller
controller U_CONTROLLER (
    .clk(clk),
    .resetn(resetn),
    .start(start_gated),
    .accumulate(accumulate),
    .pe_en(pe_en),
    .clr_acc(clr_acc),
    .clr_pipe(clr_pipe),
    .capture(capture),
    .busy(busy),
    .done(done),
    .count_o(count)
);

// Output buffer
output_buffer U_OUTPUT (
    .clk(clk),
    .resetn(resetn),
    .capture(capture),
    .c_in(pe_result),
    .c_out(c_out)
);

//power controller
//DOWN : ON > SAVE > ISO > OFF
//UP : OFF > UP(WAIT) > RESTORE > UNISO > ON

always_ff@(posedge clk or negedge resetn) begin
	if(!resetn) begin
		pwr_state  <= PWR_ON;
		pwr_wait   <= 2'd0;
		lp_pwr_en  <= 1'b1;
		lp_iso_en  <= 1'b0;
		lp_save    <= 1'b0;
		lp_restore <= 1'b0;
	end
	else begin
		lp_save    <= 1'b0;
		lp_restore <= 1'b0;

		case(pwr_state)
		    PWR_ON: begin
		        if(pwr_down_req && !busy) begin
		            pwr_state <= PWR_SAVE;
		            lp_save   <= 1'b1;            // 1. save
		        end
		    end

		    PWR_SAVE: begin
		        pwr_state <= PWR_ISO;
`ifndef LP_BUG_NO_ISO
		        lp_iso_en <= 1'b1;                // 2. isolate
`endif
		    end

		    PWR_ISO: begin
		        pwr_state <= PWR_OFF;
		        lp_pwr_en <= 1'b0;                // 3. switch off
		    end

		    PWR_OFF: begin
		        if(!pwr_down_req) begin
		            pwr_state <= PWR_UP;
		            lp_pwr_en <= 1'b1;            // 4. switch on
		            pwr_wait  <= 2'd3;
		        end
		    end

		    PWR_UP: begin
		        if(pwr_wait == 2'd0) begin
		            pwr_state  <= PWR_RESTORE;
`ifndef LP_BUG_NO_RESTORE
		            lp_restore <= 1'b1;           // 5. restore
`endif
		        end
		        else
		            pwr_wait <= pwr_wait - 1'b1;
		    end

		    PWR_RESTORE: begin
		        pwr_state <= PWR_UNISO;
		        lp_iso_en <= 1'b0;                // 6. remove isolation
		    end

		    PWR_UNISO: begin
		        pwr_state <= PWR_ON;
		    end

		    default: pwr_state <= PWR_ON;
		endcase
	end
end

// Power status
assign pwr_on  = (pwr_state == PWR_ON);
assign pwr_off = (pwr_state == PWR_OFF);

endmodule
