`timescale 1ns / 1ps

module moe_result_scheduler #(
    parameter NUM_OWNERS = 2,
    parameter OWNER_WIDTH = 8,
    parameter MICRO_ID_WIDTH = 16,
    parameter GLOBAL_SEQ_WIDTH = 32,
    parameter TOKEN_ID_WIDTH = 32,
    parameter ENTRY_COUNT = 16,
    parameter ENTRY_ADDR_WIDTH = $clog2(ENTRY_COUNT),
    parameter VALUE_ADDR_WIDTH = ENTRY_ADDR_WIDTH,
    parameter QUEUE_DEPTH = 4,
    parameter QUEUE_ADDR_WIDTH = $clog2(QUEUE_DEPTH)
) (
    input wire clk,
    input wire rst_n,

    input wire ready_in_valid,
    output wire ready_in_ready,
    input wire [ENTRY_ADDR_WIDTH-1:0] ready_in_entry_index,
    input wire [OWNER_WIDTH-1:0] ready_in_owner_rank,
    input wire [MICRO_ID_WIDTH-1:0] ready_in_microbatch_id,
    input wire [GLOBAL_SEQ_WIDTH-1:0] ready_in_global_seq,
    input wire [TOKEN_ID_WIDTH-1:0] ready_in_token_id,
    input wire [VALUE_ADDR_WIDTH-1:0] ready_in_value_ptr,

    output reg ready_drop_full,

    output wire result_valid,
    input wire result_ready,
    output wire [ENTRY_ADDR_WIDTH-1:0] result_entry_index,
    output wire [OWNER_WIDTH-1:0] result_owner_rank,
    output wire [MICRO_ID_WIDTH-1:0] result_microbatch_id,
    output wire [GLOBAL_SEQ_WIDTH-1:0] result_global_seq,
    output wire [TOKEN_ID_WIDTH-1:0] result_token_id,
    output wire [VALUE_ADDR_WIDTH-1:0] result_value_ptr,
    output wire [NUM_OWNERS-1:0] result_owner_mask
);
    localparam COUNT_WIDTH = $clog2(QUEUE_DEPTH + 1);
    localparam [OWNER_WIDTH-1:0] NUM_OWNERS_CAST = NUM_OWNERS;
    localparam [COUNT_WIDTH-1:0] QUEUE_DEPTH_CAST = QUEUE_DEPTH;

    reg [ENTRY_ADDR_WIDTH-1:0] entry_index_mem [0:QUEUE_DEPTH-1];
    reg [OWNER_WIDTH-1:0] owner_rank_mem [0:QUEUE_DEPTH-1];
    reg [MICRO_ID_WIDTH-1:0] microbatch_id_mem [0:QUEUE_DEPTH-1];
    reg [GLOBAL_SEQ_WIDTH-1:0] global_seq_mem [0:QUEUE_DEPTH-1];
    reg [TOKEN_ID_WIDTH-1:0] token_id_mem [0:QUEUE_DEPTH-1];
    reg [VALUE_ADDR_WIDTH-1:0] value_ptr_mem [0:QUEUE_DEPTH-1];

    reg [QUEUE_ADDR_WIDTH-1:0] wr_ptr;
    reg [QUEUE_ADDR_WIDTH-1:0] rd_ptr;
    reg [COUNT_WIDTH-1:0] count;

    wire queue_empty = (count == {COUNT_WIDTH{1'b0}});
    wire queue_full = (count == QUEUE_DEPTH_CAST);
    wire do_deq = result_valid && result_ready;
    wire do_enq = ready_in_valid && (!queue_full || do_deq);
    wire result_owner_ok = result_owner_rank < NUM_OWNERS_CAST;

    assign ready_in_ready = !queue_full || do_deq;
    assign result_valid = !queue_empty;
    assign result_entry_index = entry_index_mem[rd_ptr];
    assign result_owner_rank = owner_rank_mem[rd_ptr];
    assign result_microbatch_id = microbatch_id_mem[rd_ptr];
    assign result_global_seq = global_seq_mem[rd_ptr];
    assign result_token_id = token_id_mem[rd_ptr];
    assign result_value_ptr = value_ptr_mem[rd_ptr];
    assign result_owner_mask = result_owner_ok ? ({{(NUM_OWNERS-1){1'b0}}, 1'b1} << result_owner_rank) :
                                                 {NUM_OWNERS{1'b0}};

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {QUEUE_ADDR_WIDTH{1'b0}};
            rd_ptr <= {QUEUE_ADDR_WIDTH{1'b0}};
            count <= {COUNT_WIDTH{1'b0}};
            ready_drop_full <= 1'b0;

            for (i = 0; i < QUEUE_DEPTH; i = i + 1) begin
                entry_index_mem[i] <= {ENTRY_ADDR_WIDTH{1'b0}};
                owner_rank_mem[i] <= {OWNER_WIDTH{1'b0}};
                microbatch_id_mem[i] <= {MICRO_ID_WIDTH{1'b0}};
                global_seq_mem[i] <= {GLOBAL_SEQ_WIDTH{1'b0}};
                token_id_mem[i] <= {TOKEN_ID_WIDTH{1'b0}};
                value_ptr_mem[i] <= {VALUE_ADDR_WIDTH{1'b0}};
            end
        end
        else begin
            ready_drop_full <= 1'b0;

            if (ready_in_valid && !ready_in_ready) begin
                ready_drop_full <= 1'b1;
            end

            if (do_enq) begin
                entry_index_mem[wr_ptr] <= ready_in_entry_index;
                owner_rank_mem[wr_ptr] <= ready_in_owner_rank;
                microbatch_id_mem[wr_ptr] <= ready_in_microbatch_id;
                global_seq_mem[wr_ptr] <= ready_in_global_seq;
                token_id_mem[wr_ptr] <= ready_in_token_id;
                value_ptr_mem[wr_ptr] <= ready_in_value_ptr;
                wr_ptr <= wr_ptr + 1'b1;
            end

            if (do_deq) begin
                rd_ptr <= rd_ptr + 1'b1;
            end

            case ({do_enq, do_deq})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule
