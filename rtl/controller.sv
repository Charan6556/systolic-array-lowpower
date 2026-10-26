module controller (
    input logic clk, resetn, start,
    input logic accumulate,
    output logic pe_en, clr_acc, clr_pipe,
    output logic capture,
    output logic busy, done,
    output logic [3:0] count_o
);

typedef enum logic [1:0] {
    IDLE,
    CLEAR,
    COMPUTE,
    DONE
} state_t;

state_t state, next_state;

logic [3:0] count;
logic done_r;
logic acc_mode;

// State register
always_ff @(posedge clk or negedge resetn)
begin
    if(!resetn) begin
        state <= IDLE;
        count <= 4'd0;
    end
    else begin
        state <= next_state;

        if(state == CLEAR)
            count <= 4'd0;
        else if(state == COMPUTE)
            count <= count + 1'b1;
        else
            count <= 4'd0;
    end
end

// Accumulate mode latch
always_ff @(posedge clk or negedge resetn)
begin
    if(!resetn)
        acc_mode <= 1'b0;
    else if(state == IDLE && start)
        acc_mode <= accumulate;
end

// Sticky done
always_ff @(posedge clk or negedge resetn)
begin
    if(!resetn)
        done_r <= 1'b0;
    else if(state == IDLE && start)
        done_r <= 1'b0;
    else if(state == DONE)
        done_r <= 1'b1;
end

// Next state logic
always_comb
begin
    next_state = state;

    case(state)
        IDLE: begin
            if(start)
                next_state = CLEAR;
        end

        CLEAR: begin
            next_state = COMPUTE;
        end

        COMPUTE: begin
            if(count == 4'd9)
                next_state = DONE;
        end

        DONE: begin
            next_state = IDLE;
        end

        default: next_state = IDLE;
    endcase
end

// Output logic
always_comb
begin
    pe_en = 0;
    clr_acc = 0;
    clr_pipe = 0;
    busy = 0;

    case(state)
        IDLE: begin
            busy = 0;
        end

        CLEAR: begin
            busy = 1;
            clr_acc = !acc_mode;
            clr_pipe = 1;
        end

        COMPUTE: begin
            busy = 1;
            pe_en = 1;
        end

        DONE: begin
            busy = 1;
        end

        default: begin
        end
    endcase
end

// Output assignments
assign capture = (state == DONE);
assign done = done_r;
assign count_o = count;

endmodule
