`timescale 1ns / 1ps
`include "moe_defs.vh"

module moe_combine_engine #(
    parameter NUM_OWNERS = 2,
    parameter OWNER_WIDTH = 8,
    parameter WINDOW_SIZE = 8,
    parameter ENTRY_COUNT = NUM_OWNERS * WINDOW_SIZE,
    parameter ENTRY_ADDR_WIDTH = $clog2(ENTRY_COUNT),
    parameter MICRO_ID_WIDTH = 16,
    parameter GLOBAL_SEQ_WIDTH = 32,
    parameter TOKEN_ID_WIDTH = 32,
    parameter EXPERT_BITMAP_WIDTH = 64,
    parameter EXPERT_ID_WIDTH = 6,
    parameter TOKEN_LEN_WIDTH = 16,
    parameter CHUNK_COUNT_WIDTH = 8,
    parameter CHUNK_ID_WIDTH = 8,
    parameter PAYLOAD_WIDTH = 512,
    parameter AXIS_DATA_WIDTH = 512,
    parameter AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8,
    parameter AXIS_TUSER_WIDTH = 128,
    parameter PORT_MASK_WIDTH = 8,
    parameter ROCE_PAYLOAD_BYTES = 1024,
    parameter USE_EXTERNAL_REDUCE = 0
) (
    input wire clk,
    input wire rst_n,

    input wire init_valid,
    output wire init_ready,
    input wire [OWNER_WIDTH-1:0] init_owner_rank,
    input wire [MICRO_ID_WIDTH-1:0] init_microbatch_id,
    input wire [GLOBAL_SEQ_WIDTH-1:0] init_global_seq,
    input wire [TOKEN_ID_WIDTH-1:0] init_token_id,
    input wire [EXPERT_BITMAP_WIDTH-1:0] init_expected_bitmap,
    input wire [TOKEN_LEN_WIDTH-1:0] init_token_len,
    input wire [CHUNK_COUNT_WIDTH-1:0] init_chunk_count,
    output wire init_accept,
    output wire init_drop_owner,
    output wire init_drop_window,
    output wire init_drop_busy,

    input wire data_valid,
    output wire data_ready,
    input wire [OWNER_WIDTH-1:0] data_owner_rank,
    input wire [MICRO_ID_WIDTH-1:0] data_microbatch_id,
    input wire [GLOBAL_SEQ_WIDTH-1:0] data_global_seq,
    input wire [TOKEN_ID_WIDTH-1:0] data_token_id,
    input wire [EXPERT_ID_WIDTH-1:0] data_expert_id,
    input wire [CHUNK_ID_WIDTH-1:0] data_chunk_id,
    input wire [PAYLOAD_WIDTH-1:0] data_payload,
    output wire data_accept,
    output wire data_drop_owner,
    output wire data_drop_no_entry,
    output wire data_drop_unexpected,
    output wire data_drop_duplicate,

    output wire external_reduce_update_valid,
    input wire external_reduce_update_ready,
    output wire [ENTRY_ADDR_WIDTH-1:0] external_reduce_update_addr,
    output wire [PAYLOAD_WIDTH-1:0] external_reduce_update_data,
    input wire external_reduce_update_done,
    input wire [PAYLOAD_WIDTH-1:0] external_reduce_update_sum,
    output wire external_reduce_query_valid,
    input wire external_reduce_query_ready,
    output wire [ENTRY_ADDR_WIDTH-1:0] external_reduce_query_addr,
    input wire external_reduce_query_done,
    input wire [PAYLOAD_WIDTH-1:0] external_reduce_query_data,
    output wire external_arrival_update_valid,
    input wire external_arrival_update_ready,
    output wire [ENTRY_ADDR_WIDTH-1:0] external_arrival_update_addr,
    output wire [EXPERT_ID_WIDTH-1:0] external_arrival_update_lane_id,
    input wire external_arrival_update_done,

    input wire [47:0] cfg_fpga_mac,
    input wire [31:0] cfg_fpga_ip,
    input wire [15:0] cfg_fpga_udp_port,
    input wire [47:0] cfg_owner0_mac,
    input wire [31:0] cfg_owner0_ip,
    input wire [23:0] cfg_owner0_qp,
    input wire [15:0] cfg_owner0_udp_port,
    input wire [47:0] cfg_owner1_mac,
    input wire [31:0] cfg_owner1_ip,
    input wire [23:0] cfg_owner1_qp,
    input wire [15:0] cfg_owner1_udp_port,
    input wire [NUM_OWNERS*PORT_MASK_WIDTH-1:0] cfg_owner_port_mask_flat,
    input wire [31:0] cfg_result_psn,

    output wire [AXIS_DATA_WIDTH-1:0] m_axis_tdata,
    output wire [AXIS_KEEP_WIDTH-1:0] m_axis_tkeep,
    output wire [AXIS_TUSER_WIDTH-1:0] m_axis_tuser,
    output wire m_axis_tvalid,
    output wire m_axis_tlast,
    input wire m_axis_tready,

    output wire release_accept,
    output wire release_drop_owner,
    output wire release_drop_no_entry,
    output wire release_drop_busy,
    output wire [NUM_OWNERS*GLOBAL_SEQ_WIDTH-1:0] dbg_owner_head_seq_flat
);
    localparam EXT_REDUCE_IDLE = 3'd0;
    localparam EXT_REDUCE_ISSUE = 3'd1;
    localparam EXT_REDUCE_WAIT_DONE = 3'd2;
    localparam EXT_REDUCE_ARRIVAL_ISSUE = 3'd3;
    localparam EXT_REDUCE_WAIT_ARRIVAL = 3'd4;
    localparam EXT_QUERY_IDLE = 2'd0;
    localparam EXT_QUERY_WAIT_DONE = 2'd1;
    localparam EXT_QUERY_HOLD_RESULT = 2'd2;

    wire [ENTRY_ADDR_WIDTH-1:0] init_entry_index;
    wire clear_value_valid;
    wire [ENTRY_ADDR_WIDTH-1:0] clear_value_addr;

    wire [ENTRY_ADDR_WIDTH-1:0] data_entry_index;
    wire aggregate_task_valid;
    wire aggregate_task_ready;
    wire [ENTRY_ADDR_WIDTH-1:0] aggregate_task_entry_index;
    wire [ENTRY_ADDR_WIDTH-1:0] aggregate_task_value_addr;
    wire [OWNER_WIDTH-1:0] aggregate_task_owner_rank;
    wire [GLOBAL_SEQ_WIDTH-1:0] aggregate_task_global_seq;
    wire [TOKEN_ID_WIDTH-1:0] aggregate_task_token_id;
    wire [EXPERT_ID_WIDTH-1:0] aggregate_task_expert_id;
    wire [CHUNK_ID_WIDTH-1:0] aggregate_task_chunk_id;
    wire aggregate_done_valid;
    wire [ENTRY_ADDR_WIDTH-1:0] aggregate_done_entry_index;
    wire [EXPERT_ID_WIDTH-1:0] aggregate_done_expert_id;
    wire [CHUNK_ID_WIDTH-1:0] aggregate_done_chunk_id;
    wire internal_reduce_task_ready;
    wire internal_reduce_done_valid;
    wire [ENTRY_ADDR_WIDTH-1:0] internal_reduce_done_entry_index;
    wire [EXPERT_ID_WIDTH-1:0] internal_reduce_done_expert_id;
    wire [CHUNK_ID_WIDTH-1:0] internal_reduce_done_chunk_id;
    wire [PAYLOAD_WIDTH-1:0] internal_reduce_query_value_data;
    reg [PAYLOAD_WIDTH-1:0] data_payload_r;

    reg [2:0] external_reduce_state;
    reg [ENTRY_ADDR_WIDTH-1:0] external_reduce_entry_index_r;
    reg [ENTRY_ADDR_WIDTH-1:0] external_reduce_value_addr_r;
    reg [EXPERT_ID_WIDTH-1:0] external_reduce_expert_id_r;
    reg [CHUNK_ID_WIDTH-1:0] external_reduce_chunk_id_r;
    reg [PAYLOAD_WIDTH-1:0] external_reduce_payload_r;
    reg [1:0] external_query_state;
    reg [ENTRY_ADDR_WIDTH-1:0] external_query_entry_index_r;
    reg [OWNER_WIDTH-1:0] external_query_owner_rank_r;
    reg [MICRO_ID_WIDTH-1:0] external_query_microbatch_id_r;
    reg [GLOBAL_SEQ_WIDTH-1:0] external_query_global_seq_r;
    reg [TOKEN_ID_WIDTH-1:0] external_query_token_id_r;
    reg [ENTRY_ADDR_WIDTH-1:0] external_query_value_ptr_r;
    reg [NUM_OWNERS-1:0] external_query_owner_mask_r;
    reg [PAYLOAD_WIDTH-1:0] external_query_payload_data_r;
    reg external_task_hold_valid;
    reg [ENTRY_ADDR_WIDTH-1:0] external_task_hold_entry_index;
    reg [ENTRY_ADDR_WIDTH-1:0] external_task_hold_value_addr;
    reg [EXPERT_ID_WIDTH-1:0] external_task_hold_expert_id;
    reg [CHUNK_ID_WIDTH-1:0] external_task_hold_chunk_id;

    wire context_ready_valid;
    wire [ENTRY_ADDR_WIDTH-1:0] context_ready_entry_index;
    wire [OWNER_WIDTH-1:0] context_ready_owner_rank;
    wire [MICRO_ID_WIDTH-1:0] context_ready_microbatch_id;
    wire [GLOBAL_SEQ_WIDTH-1:0] context_ready_global_seq;
    wire [TOKEN_ID_WIDTH-1:0] context_ready_token_id;
    wire [ENTRY_ADDR_WIDTH-1:0] context_ready_value_ptr;

    reg ready_hold_valid;
    reg [ENTRY_ADDR_WIDTH-1:0] ready_hold_entry_index;
    reg [OWNER_WIDTH-1:0] ready_hold_owner_rank;
    reg [MICRO_ID_WIDTH-1:0] ready_hold_microbatch_id;
    reg [GLOBAL_SEQ_WIDTH-1:0] ready_hold_global_seq;
    reg [TOKEN_ID_WIDTH-1:0] ready_hold_token_id;
    reg [ENTRY_ADDR_WIDTH-1:0] ready_hold_value_ptr;

    wire ready_valid = ready_hold_valid;
    wire [ENTRY_ADDR_WIDTH-1:0] ready_entry_index = ready_hold_entry_index;
    wire [OWNER_WIDTH-1:0] ready_owner_rank = ready_hold_owner_rank;
    wire [MICRO_ID_WIDTH-1:0] ready_microbatch_id = ready_hold_microbatch_id;
    wire [GLOBAL_SEQ_WIDTH-1:0] ready_global_seq = ready_hold_global_seq;
    wire [TOKEN_ID_WIDTH-1:0] ready_token_id = ready_hold_token_id;
    wire [ENTRY_ADDR_WIDTH-1:0] ready_value_ptr = ready_hold_value_ptr;

    wire scheduler_ready_in_ready;
    wire scheduler_drop_full;
    wire scheduler_result_valid;
    wire scheduler_result_ready;
    wire [ENTRY_ADDR_WIDTH-1:0] scheduler_result_entry_index;
    wire [OWNER_WIDTH-1:0] scheduler_result_owner_rank;
    wire [MICRO_ID_WIDTH-1:0] scheduler_result_microbatch_id;
    wire [GLOBAL_SEQ_WIDTH-1:0] scheduler_result_global_seq;
    wire [TOKEN_ID_WIDTH-1:0] scheduler_result_token_id;
    wire [ENTRY_ADDR_WIDTH-1:0] scheduler_result_value_ptr;
    wire [NUM_OWNERS-1:0] scheduler_result_owner_mask;
    wire packet_result_valid;
    wire packet_result_ready;
    wire [ENTRY_ADDR_WIDTH-1:0] packet_result_entry_index;
    wire [OWNER_WIDTH-1:0] packet_result_owner_rank;
    wire [MICRO_ID_WIDTH-1:0] packet_result_microbatch_id;
    wire [GLOBAL_SEQ_WIDTH-1:0] packet_result_global_seq;
    wire [TOKEN_ID_WIDTH-1:0] packet_result_token_id;
    wire [ENTRY_ADDR_WIDTH-1:0] packet_result_value_ptr;
    wire [NUM_OWNERS-1:0] packet_result_owner_mask;
    wire [PAYLOAD_WIDTH-1:0] packet_result_payload_data;

    wire reduce_query_valid;
    wire [ENTRY_ADDR_WIDTH-1:0] reduce_query_value_addr;

    wire release_valid = packet_result_valid && packet_result_ready;
    wire [ENTRY_ADDR_WIDTH-1:0] release_entry_index;

    assign reduce_query_valid = (USE_EXTERNAL_REDUCE == 0) && scheduler_result_valid;
    assign reduce_query_value_addr = scheduler_result_value_ptr;
    assign aggregate_task_ready = (USE_EXTERNAL_REDUCE != 0) ?
                                  !external_task_hold_valid :
                                  internal_reduce_task_ready;
    assign aggregate_done_valid = (USE_EXTERNAL_REDUCE != 0) ?
                                  ((external_reduce_state == EXT_REDUCE_WAIT_ARRIVAL) &&
                                   external_arrival_update_done) :
                                  internal_reduce_done_valid;
    assign aggregate_done_entry_index = (USE_EXTERNAL_REDUCE != 0) ?
                                        external_reduce_entry_index_r :
                                        internal_reduce_done_entry_index;
    assign aggregate_done_expert_id = (USE_EXTERNAL_REDUCE != 0) ?
                                      external_reduce_expert_id_r :
                                      internal_reduce_done_expert_id;
    assign aggregate_done_chunk_id = (USE_EXTERNAL_REDUCE != 0) ?
                                     external_reduce_chunk_id_r :
                                     internal_reduce_done_chunk_id;
    assign packet_result_valid = (USE_EXTERNAL_REDUCE != 0) ?
                                 (external_query_state == EXT_QUERY_HOLD_RESULT) :
                                 scheduler_result_valid;
    assign scheduler_result_ready = (USE_EXTERNAL_REDUCE != 0) ?
                                    ((external_query_state == EXT_QUERY_IDLE) &&
                                     external_reduce_query_ready) :
                                    packet_result_ready;
    assign packet_result_entry_index = (USE_EXTERNAL_REDUCE != 0) ?
                                       external_query_entry_index_r :
                                       scheduler_result_entry_index;
    assign packet_result_owner_rank = (USE_EXTERNAL_REDUCE != 0) ?
                                      external_query_owner_rank_r :
                                      scheduler_result_owner_rank;
    assign packet_result_microbatch_id = (USE_EXTERNAL_REDUCE != 0) ?
                                         external_query_microbatch_id_r :
                                         scheduler_result_microbatch_id;
    assign packet_result_global_seq = (USE_EXTERNAL_REDUCE != 0) ?
                                      external_query_global_seq_r :
                                      scheduler_result_global_seq;
    assign packet_result_token_id = (USE_EXTERNAL_REDUCE != 0) ?
                                    external_query_token_id_r :
                                    scheduler_result_token_id;
    assign packet_result_value_ptr = (USE_EXTERNAL_REDUCE != 0) ?
                                     external_query_value_ptr_r :
                                     scheduler_result_value_ptr;
    assign packet_result_owner_mask = (USE_EXTERNAL_REDUCE != 0) ?
                                      external_query_owner_mask_r :
                                      scheduler_result_owner_mask;
    assign packet_result_payload_data = (USE_EXTERNAL_REDUCE != 0) ?
                                        external_query_payload_data_r :
                                        internal_reduce_query_value_data;
    assign external_reduce_update_valid = (USE_EXTERNAL_REDUCE != 0) &&
                                          (external_reduce_state == EXT_REDUCE_ISSUE);
    assign external_reduce_update_addr = external_reduce_value_addr_r;
    assign external_reduce_update_data = external_reduce_payload_r;
    assign external_arrival_update_valid = (USE_EXTERNAL_REDUCE != 0) &&
                                           (external_reduce_state == EXT_REDUCE_ARRIVAL_ISSUE);
    assign external_arrival_update_addr = external_reduce_value_addr_r;
    assign external_arrival_update_lane_id = external_reduce_expert_id_r;
    assign external_reduce_query_valid = (USE_EXTERNAL_REDUCE != 0) &&
                                         (external_query_state == EXT_QUERY_IDLE) &&
                                         scheduler_result_valid;
    assign external_reduce_query_addr = scheduler_result_value_ptr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_payload_r <= {PAYLOAD_WIDTH{1'b0}};
            external_reduce_state <= EXT_REDUCE_IDLE;
            external_reduce_entry_index_r <= {ENTRY_ADDR_WIDTH{1'b0}};
            external_reduce_value_addr_r <= {ENTRY_ADDR_WIDTH{1'b0}};
            external_reduce_expert_id_r <= {EXPERT_ID_WIDTH{1'b0}};
            external_reduce_chunk_id_r <= {CHUNK_ID_WIDTH{1'b0}};
            external_reduce_payload_r <= {PAYLOAD_WIDTH{1'b0}};
            external_query_state <= EXT_QUERY_IDLE;
            external_query_entry_index_r <= {ENTRY_ADDR_WIDTH{1'b0}};
            external_query_owner_rank_r <= {OWNER_WIDTH{1'b0}};
            external_query_microbatch_id_r <= {MICRO_ID_WIDTH{1'b0}};
            external_query_global_seq_r <= {GLOBAL_SEQ_WIDTH{1'b0}};
            external_query_token_id_r <= {TOKEN_ID_WIDTH{1'b0}};
            external_query_value_ptr_r <= {ENTRY_ADDR_WIDTH{1'b0}};
            external_query_owner_mask_r <= {NUM_OWNERS{1'b0}};
            external_query_payload_data_r <= {PAYLOAD_WIDTH{1'b0}};
            external_task_hold_valid <= 1'b0;
            external_task_hold_entry_index <= {ENTRY_ADDR_WIDTH{1'b0}};
            external_task_hold_value_addr <= {ENTRY_ADDR_WIDTH{1'b0}};
            external_task_hold_expert_id <= {EXPERT_ID_WIDTH{1'b0}};
            external_task_hold_chunk_id <= {CHUNK_ID_WIDTH{1'b0}};
            ready_hold_valid <= 1'b0;
            ready_hold_entry_index <= {ENTRY_ADDR_WIDTH{1'b0}};
            ready_hold_owner_rank <= {OWNER_WIDTH{1'b0}};
            ready_hold_microbatch_id <= {MICRO_ID_WIDTH{1'b0}};
            ready_hold_global_seq <= {GLOBAL_SEQ_WIDTH{1'b0}};
            ready_hold_token_id <= {TOKEN_ID_WIDTH{1'b0}};
            ready_hold_value_ptr <= {ENTRY_ADDR_WIDTH{1'b0}};
        end
        else begin
            if (data_valid && data_ready) begin
                data_payload_r <= data_payload;
            end

            if ((USE_EXTERNAL_REDUCE != 0) &&
                aggregate_task_valid &&
                !external_task_hold_valid) begin
                external_task_hold_valid <= 1'b1;
                external_task_hold_entry_index <= aggregate_task_entry_index;
                external_task_hold_value_addr <= aggregate_task_value_addr;
                external_task_hold_expert_id <= aggregate_task_expert_id;
                external_task_hold_chunk_id <= aggregate_task_chunk_id;
            end

            case (external_reduce_state)
                EXT_REDUCE_IDLE: begin
                    if ((USE_EXTERNAL_REDUCE != 0) && external_task_hold_valid) begin
                        external_reduce_entry_index_r <= external_task_hold_entry_index;
                        external_reduce_value_addr_r <= external_task_hold_value_addr;
                        external_reduce_expert_id_r <= external_task_hold_expert_id;
                        external_reduce_chunk_id_r <= external_task_hold_chunk_id;
                        external_reduce_payload_r <= data_payload_r;
                        external_reduce_state <= EXT_REDUCE_ISSUE;
                        external_task_hold_valid <= 1'b0;
                    end
                end

                EXT_REDUCE_ISSUE: begin
                    if (external_reduce_update_ready) begin
                        external_reduce_state <= EXT_REDUCE_WAIT_DONE;
                    end
                end

                EXT_REDUCE_WAIT_DONE: begin
                    if (external_reduce_update_done) begin
                        external_reduce_state <= EXT_REDUCE_ARRIVAL_ISSUE;
                    end
                end

                EXT_REDUCE_ARRIVAL_ISSUE: begin
                    if (external_arrival_update_ready) begin
                        external_reduce_state <= EXT_REDUCE_WAIT_ARRIVAL;
                    end
                end

                EXT_REDUCE_WAIT_ARRIVAL: begin
                    if (external_arrival_update_done) begin
                        external_reduce_state <= EXT_REDUCE_IDLE;
                    end
                end

                default: begin
                    external_reduce_state <= EXT_REDUCE_IDLE;
                end
            endcase

            case (external_query_state)
                EXT_QUERY_IDLE: begin
                    if ((USE_EXTERNAL_REDUCE != 0) &&
                        scheduler_result_valid &&
                        scheduler_result_ready) begin
                        external_query_entry_index_r <= scheduler_result_entry_index;
                        external_query_owner_rank_r <= scheduler_result_owner_rank;
                        external_query_microbatch_id_r <= scheduler_result_microbatch_id;
                        external_query_global_seq_r <= scheduler_result_global_seq;
                        external_query_token_id_r <= scheduler_result_token_id;
                        external_query_value_ptr_r <= scheduler_result_value_ptr;
                        external_query_owner_mask_r <= scheduler_result_owner_mask;
                        external_query_state <= EXT_QUERY_WAIT_DONE;
                    end
                end

                EXT_QUERY_WAIT_DONE: begin
                    if (external_reduce_query_done) begin
                        external_query_payload_data_r <= external_reduce_query_data;
                        external_query_state <= EXT_QUERY_HOLD_RESULT;
                    end
                end

                EXT_QUERY_HOLD_RESULT: begin
                    if (packet_result_ready) begin
                        external_query_state <= EXT_QUERY_IDLE;
                    end
                end

                default: begin
                    external_query_state <= EXT_QUERY_IDLE;
                end
            endcase

            if (!ready_hold_valid && context_ready_valid) begin
                ready_hold_valid <= 1'b1;
                ready_hold_entry_index <= context_ready_entry_index;
                ready_hold_owner_rank <= context_ready_owner_rank;
                ready_hold_microbatch_id <= context_ready_microbatch_id;
                ready_hold_global_seq <= context_ready_global_seq;
                ready_hold_token_id <= context_ready_token_id;
                ready_hold_value_ptr <= context_ready_value_ptr;
            end
            else if (ready_hold_valid && scheduler_ready_in_ready) begin
                ready_hold_valid <= 1'b0;
            end
        end
    end

    moe_context_manager #(
        .NUM_OWNERS(NUM_OWNERS),
        .OWNER_WIDTH(OWNER_WIDTH),
        .WINDOW_SIZE(WINDOW_SIZE),
        .ENTRY_COUNT(ENTRY_COUNT),
        .ENTRY_ADDR_WIDTH(ENTRY_ADDR_WIDTH),
        .GLOBAL_SEQ_WIDTH(GLOBAL_SEQ_WIDTH),
        .MICRO_ID_WIDTH(MICRO_ID_WIDTH),
        .TOKEN_ID_WIDTH(TOKEN_ID_WIDTH),
        .EXPERT_BITMAP_WIDTH(EXPERT_BITMAP_WIDTH),
        .EXPERT_ID_WIDTH(EXPERT_ID_WIDTH),
        .TOKEN_LEN_WIDTH(TOKEN_LEN_WIDTH),
        .CHUNK_COUNT_WIDTH(CHUNK_COUNT_WIDTH),
        .CHUNK_ID_WIDTH(CHUNK_ID_WIDTH),
        .VALUE_ADDR_WIDTH(ENTRY_ADDR_WIDTH)
    ) context_mgr (
        .clk(clk),
        .rst_n(rst_n),

        .init_valid(init_valid),
        .init_ready(init_ready),
        .init_owner_rank(init_owner_rank),
        .init_microbatch_id(init_microbatch_id),
        .init_global_seq(init_global_seq),
        .init_token_id(init_token_id),
        .init_expected_bitmap(init_expected_bitmap),
        .init_token_len(init_token_len),
        .init_chunk_count(init_chunk_count),
        .init_accept(init_accept),
        .init_drop_owner(init_drop_owner),
        .init_drop_window(init_drop_window),
        .init_drop_busy(init_drop_busy),
        .init_entry_index(init_entry_index),
        .clear_value_valid(clear_value_valid),
        .clear_value_addr(clear_value_addr),

        .data_valid(data_valid),
        .data_ready(data_ready),
        .data_owner_rank(data_owner_rank),
        .data_microbatch_id(data_microbatch_id),
        .data_global_seq(data_global_seq),
        .data_token_id(data_token_id),
        .data_expert_id(data_expert_id),
        .data_chunk_id(data_chunk_id),
        .data_accept(data_accept),
        .data_drop_owner(data_drop_owner),
        .data_drop_no_entry(data_drop_no_entry),
        .data_drop_unexpected(data_drop_unexpected),
        .data_drop_duplicate(data_drop_duplicate),
        .data_entry_index(data_entry_index),

        .aggregate_task_valid(aggregate_task_valid),
        .aggregate_task_ready(aggregate_task_ready),
        .aggregate_task_entry_index(aggregate_task_entry_index),
        .aggregate_task_value_addr(aggregate_task_value_addr),
        .aggregate_task_owner_rank(aggregate_task_owner_rank),
        .aggregate_task_global_seq(aggregate_task_global_seq),
        .aggregate_task_token_id(aggregate_task_token_id),
        .aggregate_task_expert_id(aggregate_task_expert_id),
        .aggregate_task_chunk_id(aggregate_task_chunk_id),

        .aggregate_done_valid(aggregate_done_valid),
        .aggregate_done_entry_index(aggregate_done_entry_index),
        .aggregate_done_expert_id(aggregate_done_expert_id),

        .release_valid(release_valid),
        .release_owner_rank(packet_result_owner_rank),
        .release_global_seq(packet_result_global_seq),
        .release_accept(release_accept),
        .release_drop_owner(release_drop_owner),
        .release_drop_no_entry(release_drop_no_entry),
        .release_drop_busy(release_drop_busy),
        .release_entry_index(release_entry_index),

        .ready_valid(context_ready_valid),
        .ready_entry_index(context_ready_entry_index),
        .ready_owner_rank(context_ready_owner_rank),
        .ready_microbatch_id(context_ready_microbatch_id),
        .ready_global_seq(context_ready_global_seq),
        .ready_token_id(context_ready_token_id),
        .ready_value_ptr(context_ready_value_ptr),

        .query_valid(1'b0),
        .query_owner_rank({OWNER_WIDTH{1'b0}}),
        .query_global_seq({GLOBAL_SEQ_WIDTH{1'b0}}),
        .query_hit(),
        .query_entry_index(),
        .query_state(),
        .query_microbatch_id(),
        .query_token_id(),
        .query_expected_bitmap(),
        .query_residual_bitmap(),
        .query_inflight_bitmap(),
        .query_token_len(),
        .query_chunk_count(),
        .query_value_ptr(),
        .dbg_owner_head_seq_flat(dbg_owner_head_seq_flat)
    );

    moe_payload_reduce_lane #(
        .ENTRY_COUNT(ENTRY_COUNT),
        .ENTRY_ADDR_WIDTH(ENTRY_ADDR_WIDTH),
        .PAYLOAD_WIDTH(PAYLOAD_WIDTH),
        .EXPERT_ID_WIDTH(EXPERT_ID_WIDTH),
        .CHUNK_ID_WIDTH(CHUNK_ID_WIDTH)
    ) reduce_lane (
        .clk(clk),
        .rst_n(rst_n),

        .clear_value_valid(clear_value_valid),
        .clear_value_addr(clear_value_addr),

        .task_valid((USE_EXTERNAL_REDUCE == 0) && aggregate_task_valid),
        .task_ready(internal_reduce_task_ready),
        .task_entry_index(aggregate_task_entry_index),
        .task_value_addr(aggregate_task_value_addr),
        .task_expert_id(aggregate_task_expert_id),
        .task_chunk_id(aggregate_task_chunk_id),
        .task_payload_data(data_payload_r),

        .done_valid(internal_reduce_done_valid),
        .done_entry_index(internal_reduce_done_entry_index),
        .done_expert_id(internal_reduce_done_expert_id),
        .done_chunk_id(internal_reduce_done_chunk_id),

        .query_valid(reduce_query_valid),
        .query_value_addr(reduce_query_value_addr),
        .query_value_data(internal_reduce_query_value_data)
    );

    moe_result_scheduler #(
        .NUM_OWNERS(NUM_OWNERS),
        .OWNER_WIDTH(OWNER_WIDTH),
        .ENTRY_COUNT(ENTRY_COUNT),
        .ENTRY_ADDR_WIDTH(ENTRY_ADDR_WIDTH),
        .MICRO_ID_WIDTH(MICRO_ID_WIDTH),
        .GLOBAL_SEQ_WIDTH(GLOBAL_SEQ_WIDTH),
        .TOKEN_ID_WIDTH(TOKEN_ID_WIDTH),
        .VALUE_ADDR_WIDTH(ENTRY_ADDR_WIDTH)
    ) result_scheduler (
        .clk(clk),
        .rst_n(rst_n),

        .ready_in_valid(ready_valid),
        .ready_in_ready(scheduler_ready_in_ready),
        .ready_in_entry_index(ready_entry_index),
        .ready_in_owner_rank(ready_owner_rank),
        .ready_in_microbatch_id(ready_microbatch_id),
        .ready_in_global_seq(ready_global_seq),
        .ready_in_token_id(ready_token_id),
        .ready_in_value_ptr(ready_value_ptr),
        .ready_drop_full(scheduler_drop_full),

        .result_valid(scheduler_result_valid),
        .result_ready(scheduler_result_ready),
        .result_entry_index(scheduler_result_entry_index),
        .result_owner_rank(scheduler_result_owner_rank),
        .result_microbatch_id(scheduler_result_microbatch_id),
        .result_global_seq(scheduler_result_global_seq),
        .result_token_id(scheduler_result_token_id),
        .result_value_ptr(scheduler_result_value_ptr),
        .result_owner_mask(scheduler_result_owner_mask)
    );

    moe_result_roce_packet_builder #(
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
        .AXIS_KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .AXIS_TUSER_WIDTH(AXIS_TUSER_WIDTH),
        .NUM_OWNERS(NUM_OWNERS),
        .OWNER_WIDTH(OWNER_WIDTH),
        .MICRO_ID_WIDTH(MICRO_ID_WIDTH),
        .GLOBAL_SEQ_WIDTH(GLOBAL_SEQ_WIDTH),
        .TOKEN_ID_WIDTH(TOKEN_ID_WIDTH),
        .VALUE_ADDR_WIDTH(ENTRY_ADDR_WIDTH),
        .PAYLOAD_WIDTH(PAYLOAD_WIDTH),
        .ROCE_PAYLOAD_BYTES(ROCE_PAYLOAD_BYTES),
        .PORT_MASK_WIDTH(PORT_MASK_WIDTH)
    ) roce_builder (
        .clk(clk),
        .rst_n(rst_n),

        .result_valid(packet_result_valid),
        .result_ready(packet_result_ready),
        .result_owner_rank(packet_result_owner_rank),
        .result_microbatch_id(packet_result_microbatch_id),
        .result_global_seq(packet_result_global_seq),
        .result_token_id(packet_result_token_id),
        .result_value_ptr(packet_result_value_ptr),
        .result_owner_mask(packet_result_owner_mask),
        .result_payload_data(packet_result_payload_data),

        .cfg_fpga_mac(cfg_fpga_mac),
        .cfg_fpga_ip(cfg_fpga_ip),
        .cfg_fpga_udp_port(cfg_fpga_udp_port),
        .cfg_owner0_mac(cfg_owner0_mac),
        .cfg_owner0_ip(cfg_owner0_ip),
        .cfg_owner0_qp(cfg_owner0_qp),
        .cfg_owner0_udp_port(cfg_owner0_udp_port),
        .cfg_owner1_mac(cfg_owner1_mac),
        .cfg_owner1_ip(cfg_owner1_ip),
        .cfg_owner1_qp(cfg_owner1_qp),
        .cfg_owner1_udp_port(cfg_owner1_udp_port),
        .cfg_owner_port_mask_flat(cfg_owner_port_mask_flat),
        .cfg_result_psn(cfg_result_psn),

        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tuser(m_axis_tuser),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tready(m_axis_tready)
    );
endmodule
