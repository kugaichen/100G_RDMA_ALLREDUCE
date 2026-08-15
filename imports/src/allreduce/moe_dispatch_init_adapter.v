`timescale 1ns / 1ps
`include "moe_defs.vh"
`include "slot_req_defs.vh"

module moe_dispatch_init_adapter #(
    parameter OWNER_WIDTH = 8,
    parameter MICRO_ID_WIDTH = 16,
    parameter GLOBAL_SEQ_WIDTH = 32,
    parameter TOKEN_ID_WIDTH = 32,
    parameter EXPERT_BITMAP_WIDTH = 64,
    parameter TOKEN_LEN_WIDTH = 16,
    parameter CHUNK_COUNT_WIDTH = 8
) (
    input wire clk,
    input wire rst_n,

    input wire enable,
    input wire slot_req_valid,
    input wire [2:0] slot_req_kind,
    input wire [OWNER_WIDTH-1:0] slot_owner_rank,
    input wire [GLOBAL_SEQ_WIDTH-1:0] slot_global_seq,
    input wire [TOKEN_ID_WIDTH-1:0] slot_token_id,
    input wire [EXPERT_BITMAP_WIDTH-1:0] slot_expected_bitmap,

    output wire init_valid,
    input wire init_ready,
    output wire [OWNER_WIDTH-1:0] init_owner_rank,
    output wire [MICRO_ID_WIDTH-1:0] init_microbatch_id,
    output wire [GLOBAL_SEQ_WIDTH-1:0] init_global_seq,
    output wire [TOKEN_ID_WIDTH-1:0] init_token_id,
    output wire [EXPERT_BITMAP_WIDTH-1:0] init_expected_bitmap,
    output wire [TOKEN_LEN_WIDTH-1:0] init_token_len,
    output wire [CHUNK_COUNT_WIDTH-1:0] init_chunk_count,

    output reg dispatch_accept,
    output reg dispatch_drop_busy
);
    reg holding_valid;
    reg [OWNER_WIDTH-1:0] owner_rank_r;
    reg [GLOBAL_SEQ_WIDTH-1:0] global_seq_r;
    reg [TOKEN_ID_WIDTH-1:0] token_id_r;
    reg [EXPERT_BITMAP_WIDTH-1:0] expected_bitmap_r;

    wire slot_req_is_dispatch = enable &&
                                slot_req_valid &&
                                (slot_req_kind == `SLOT_REQ_KIND_DISPATCH);
    wire do_init = init_valid && init_ready;

    assign init_valid = holding_valid;
    assign init_owner_rank = owner_rank_r;
    assign init_microbatch_id = {MICRO_ID_WIDTH{1'b0}};
    assign init_global_seq = global_seq_r;
    assign init_token_id = token_id_r;
    assign init_expected_bitmap = expected_bitmap_r;
    assign init_token_len = 16'd1024;
    assign init_chunk_count = 8'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            holding_valid <= 1'b0;
            owner_rank_r <= {OWNER_WIDTH{1'b0}};
            global_seq_r <= {GLOBAL_SEQ_WIDTH{1'b0}};
            token_id_r <= {TOKEN_ID_WIDTH{1'b0}};
            expected_bitmap_r <= {EXPERT_BITMAP_WIDTH{1'b0}};
            dispatch_accept <= 1'b0;
            dispatch_drop_busy <= 1'b0;
        end
        else begin
            dispatch_accept <= 1'b0;
            dispatch_drop_busy <= 1'b0;

            if (do_init) begin
                holding_valid <= 1'b0;
            end

            if (slot_req_is_dispatch) begin
                if (holding_valid && !do_init) begin
                    dispatch_drop_busy <= 1'b1;
                end
                else begin
                    holding_valid <= 1'b1;
                    owner_rank_r <= slot_owner_rank;
                    global_seq_r <= slot_global_seq;
                    token_id_r <= slot_token_id;
                    expected_bitmap_r <= slot_expected_bitmap;
                    dispatch_accept <= 1'b1;
                end
            end
        end
    end
endmodule
