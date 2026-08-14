`timescale 1ns / 1ps
`include "moe_defs.vh"

module moe_context_manager #(
    parameter NUM_OWNERS = 2,
    parameter OWNER_WIDTH = 8,
    parameter WINDOW_SIZE = 8,
    parameter ENTRY_COUNT = NUM_OWNERS * WINDOW_SIZE,
    parameter ENTRY_ADDR_WIDTH = $clog2(ENTRY_COUNT),
    parameter GLOBAL_SEQ_WIDTH = 32,
    parameter MICRO_ID_WIDTH = 16,
    parameter TOKEN_ID_WIDTH = 32,
    parameter EXPERT_BITMAP_WIDTH = 64,
    parameter EXPERT_ID_WIDTH = 6,
    parameter TOKEN_LEN_WIDTH = 16,
    parameter CHUNK_COUNT_WIDTH = 8,
    parameter CHUNK_ID_WIDTH = 8,
    parameter VALUE_ADDR_WIDTH = ENTRY_ADDR_WIDTH
) (
    input wire clk,
    input wire rst_n,

    // Init sideband. Phase 2 drives this from a testbench / explicit init path;
    // later dispatch will drive the same interface.
    input wire init_valid,
    output wire init_ready,
    input wire [OWNER_WIDTH-1:0] init_owner_rank,
    input wire [MICRO_ID_WIDTH-1:0] init_microbatch_id,
    input wire [GLOBAL_SEQ_WIDTH-1:0] init_global_seq,
    input wire [TOKEN_ID_WIDTH-1:0] init_token_id,
    input wire [EXPERT_BITMAP_WIDTH-1:0] init_expected_bitmap,
    input wire [TOKEN_LEN_WIDTH-1:0] init_token_len,
    input wire [CHUNK_COUNT_WIDTH-1:0] init_chunk_count,

    output reg init_accept,
    output reg init_drop_owner,
    output reg init_drop_window,
    output reg init_drop_busy,
    output reg [ENTRY_ADDR_WIDTH-1:0] init_entry_index,

    // Aggregate value clear request. The data path will later consume this to
    // clear aggregate_bram[value_ptr] before contributions arrive.
    output reg clear_value_valid,
    output reg [VALUE_ADDR_WIDTH-1:0] clear_value_addr,

    // Combine data sideband. This admits one expert contribution into the
    // value pipeline, then aggregate_done_valid retires the contribution.
    input wire data_valid,
    output wire data_ready,
    input wire [OWNER_WIDTH-1:0] data_owner_rank,
    input wire [MICRO_ID_WIDTH-1:0] data_microbatch_id,
    input wire [GLOBAL_SEQ_WIDTH-1:0] data_global_seq,
    input wire [TOKEN_ID_WIDTH-1:0] data_token_id,
    input wire [EXPERT_ID_WIDTH-1:0] data_expert_id,
    input wire [CHUNK_ID_WIDTH-1:0] data_chunk_id,

    output reg data_accept,
    output reg data_drop_owner,
    output reg data_drop_no_entry,
    output reg data_drop_unexpected,
    output reg data_drop_duplicate,
    output reg [ENTRY_ADDR_WIDTH-1:0] data_entry_index,

    output reg aggregate_task_valid,
    input wire aggregate_task_ready,
    output reg [ENTRY_ADDR_WIDTH-1:0] aggregate_task_entry_index,
    output reg [VALUE_ADDR_WIDTH-1:0] aggregate_task_value_addr,
    output reg [OWNER_WIDTH-1:0] aggregate_task_owner_rank,
    output reg [GLOBAL_SEQ_WIDTH-1:0] aggregate_task_global_seq,
    output reg [TOKEN_ID_WIDTH-1:0] aggregate_task_token_id,
    output reg [EXPERT_ID_WIDTH-1:0] aggregate_task_expert_id,
    output reg [CHUNK_ID_WIDTH-1:0] aggregate_task_chunk_id,

    input wire aggregate_done_valid,
    input wire [ENTRY_ADDR_WIDTH-1:0] aggregate_done_entry_index,
    input wire [EXPERT_ID_WIDTH-1:0] aggregate_done_expert_id,

    input wire release_valid,
    input wire [OWNER_WIDTH-1:0] release_owner_rank,
    input wire [GLOBAL_SEQ_WIDTH-1:0] release_global_seq,

    output reg release_accept,
    output reg release_drop_owner,
    output reg release_drop_no_entry,
    output reg release_drop_busy,
    output reg [ENTRY_ADDR_WIDTH-1:0] release_entry_index,

    output reg ready_valid,
    output reg [ENTRY_ADDR_WIDTH-1:0] ready_entry_index,
    output reg [OWNER_WIDTH-1:0] ready_owner_rank,
    output reg [MICRO_ID_WIDTH-1:0] ready_microbatch_id,
    output reg [GLOBAL_SEQ_WIDTH-1:0] ready_global_seq,
    output reg [TOKEN_ID_WIDTH-1:0] ready_token_id,
    output reg [VALUE_ADDR_WIDTH-1:0] ready_value_ptr,

    // Debug/query port for testbench and future ILA observation.
    input wire query_valid,
    input wire [OWNER_WIDTH-1:0] query_owner_rank,
    input wire [GLOBAL_SEQ_WIDTH-1:0] query_global_seq,
    output wire query_hit,
    output wire [ENTRY_ADDR_WIDTH-1:0] query_entry_index,
    output wire [1:0] query_state,
    output wire [MICRO_ID_WIDTH-1:0] query_microbatch_id,
    output wire [TOKEN_ID_WIDTH-1:0] query_token_id,
    output wire [EXPERT_BITMAP_WIDTH-1:0] query_expected_bitmap,
    output wire [EXPERT_BITMAP_WIDTH-1:0] query_residual_bitmap,
    output wire [EXPERT_BITMAP_WIDTH-1:0] query_inflight_bitmap,
    output wire [TOKEN_LEN_WIDTH-1:0] query_token_len,
    output wire [CHUNK_COUNT_WIDTH-1:0] query_chunk_count,
    output wire [VALUE_ADDR_WIDTH-1:0] query_value_ptr,
    output wire [NUM_OWNERS*GLOBAL_SEQ_WIDTH-1:0] dbg_owner_head_seq_flat
);
    localparam [1:0] ENTRY_FREE = 2'd0;
    localparam [1:0] ENTRY_ACTIVE = 2'd1;
    localparam [1:0] ENTRY_READY = 2'd2;
    localparam [OWNER_WIDTH-1:0] NUM_OWNERS_CAST = NUM_OWNERS;
    localparam [GLOBAL_SEQ_WIDTH-1:0] WINDOW_SIZE_SEQ_CAST = WINDOW_SIZE;

    reg entry_valid [0:ENTRY_COUNT-1];
    reg [1:0] entry_state [0:ENTRY_COUNT-1];
    reg [OWNER_WIDTH-1:0] entry_owner_rank [0:ENTRY_COUNT-1];
    reg [MICRO_ID_WIDTH-1:0] entry_microbatch_id [0:ENTRY_COUNT-1];
    reg [GLOBAL_SEQ_WIDTH-1:0] entry_global_seq [0:ENTRY_COUNT-1];
    reg [TOKEN_ID_WIDTH-1:0] entry_token_id [0:ENTRY_COUNT-1];
    reg [EXPERT_BITMAP_WIDTH-1:0] entry_expected_bitmap [0:ENTRY_COUNT-1];
    reg [EXPERT_BITMAP_WIDTH-1:0] entry_residual_bitmap [0:ENTRY_COUNT-1];
    reg [EXPERT_BITMAP_WIDTH-1:0] entry_inflight_bitmap [0:ENTRY_COUNT-1];
    reg [TOKEN_LEN_WIDTH-1:0] entry_token_len [0:ENTRY_COUNT-1];
    reg [CHUNK_COUNT_WIDTH-1:0] entry_chunk_count [0:ENTRY_COUNT-1];
    reg [VALUE_ADDR_WIDTH-1:0] entry_value_ptr [0:ENTRY_COUNT-1];

    reg [GLOBAL_SEQ_WIDTH-1:0] owner_head_seq [0:NUM_OWNERS-1];

    wire init_owner_ok = init_owner_rank < NUM_OWNERS_CAST;
    wire [GLOBAL_SEQ_WIDTH-1:0] init_owner_head =
        init_owner_ok ? owner_head_seq[init_owner_rank] : {GLOBAL_SEQ_WIDTH{1'b0}};
    wire [GLOBAL_SEQ_WIDTH-1:0] init_owner_tail =
        init_owner_head + WINDOW_SIZE_SEQ_CAST;
    wire init_window_ok = init_owner_ok &&
                          (init_global_seq >= init_owner_head) &&
                          (init_global_seq < init_owner_tail);

    wire [ENTRY_ADDR_WIDTH-1:0] init_calc_entry_index =
        (init_owner_rank * WINDOW_SIZE) + (init_global_seq % WINDOW_SIZE);
    wire init_slot_busy = init_window_ok &&
                          entry_valid[init_calc_entry_index] &&
                          (entry_global_seq[init_calc_entry_index] != init_global_seq);

    wire data_owner_ok = data_owner_rank < NUM_OWNERS_CAST;
    wire [ENTRY_ADDR_WIDTH-1:0] data_calc_entry_index =
        (data_owner_rank * WINDOW_SIZE) + (data_global_seq % WINDOW_SIZE);
    wire data_entry_match = data_owner_ok &&
                            entry_valid[data_calc_entry_index] &&
                            (entry_owner_rank[data_calc_entry_index] == data_owner_rank) &&
                            (entry_microbatch_id[data_calc_entry_index] == data_microbatch_id) &&
                            (entry_global_seq[data_calc_entry_index] == data_global_seq) &&
                            (entry_token_id[data_calc_entry_index] == data_token_id) &&
                            (entry_state[data_calc_entry_index] == ENTRY_ACTIVE);
    wire [EXPERT_BITMAP_WIDTH-1:0] data_expert_mask =
        {{(EXPERT_BITMAP_WIDTH-1){1'b0}}, 1'b1} << data_expert_id;
    wire data_expert_expected = data_entry_match &&
                                ((entry_expected_bitmap[data_calc_entry_index] & data_expert_mask) !=
                                 {EXPERT_BITMAP_WIDTH{1'b0}});
    wire data_expert_residual = data_entry_match &&
                                ((entry_residual_bitmap[data_calc_entry_index] & data_expert_mask) !=
                                 {EXPERT_BITMAP_WIDTH{1'b0}});
    wire data_expert_inflight = data_entry_match &&
                                ((entry_inflight_bitmap[data_calc_entry_index] & data_expert_mask) !=
                                 {EXPERT_BITMAP_WIDTH{1'b0}});

    wire aggregate_done_entry_valid =
        entry_valid[aggregate_done_entry_index] &&
        (entry_state[aggregate_done_entry_index] == ENTRY_ACTIVE);
    wire [EXPERT_BITMAP_WIDTH-1:0] aggregate_done_expert_mask =
        {{(EXPERT_BITMAP_WIDTH-1){1'b0}}, 1'b1} << aggregate_done_expert_id;
    wire [EXPERT_BITMAP_WIDTH-1:0] aggregate_done_next_residual =
        entry_residual_bitmap[aggregate_done_entry_index] & ~aggregate_done_expert_mask;

    wire query_owner_ok = query_owner_rank < NUM_OWNERS_CAST;
    wire [ENTRY_ADDR_WIDTH-1:0] query_calc_entry_index =
        (query_owner_rank * WINDOW_SIZE) + (query_global_seq % WINDOW_SIZE);

    wire release_owner_ok = release_owner_rank < NUM_OWNERS_CAST;
    wire [GLOBAL_SEQ_WIDTH-1:0] release_owner_head =
        release_owner_ok ? owner_head_seq[release_owner_rank] : {GLOBAL_SEQ_WIDTH{1'b0}};
    wire [ENTRY_ADDR_WIDTH-1:0] release_calc_entry_index =
        (release_owner_rank * WINDOW_SIZE) + (release_global_seq % WINDOW_SIZE);
    wire release_entry_match = release_owner_ok &&
                               entry_valid[release_calc_entry_index] &&
                               (entry_owner_rank[release_calc_entry_index] == release_owner_rank) &&
                               (entry_global_seq[release_calc_entry_index] == release_global_seq);
    wire release_entry_ready = release_entry_match &&
                               (entry_state[release_calc_entry_index] == ENTRY_READY);
    assign init_ready = 1'b1;
    assign data_ready = aggregate_task_ready;
    assign query_entry_index = query_calc_entry_index;
    assign query_hit = query_valid &&
                       query_owner_ok &&
                       entry_valid[query_calc_entry_index] &&
                       (entry_global_seq[query_calc_entry_index] == query_global_seq);
    assign query_state = query_hit ? entry_state[query_calc_entry_index] : ENTRY_FREE;
    assign query_microbatch_id = query_hit ? entry_microbatch_id[query_calc_entry_index] :
                                            {MICRO_ID_WIDTH{1'b0}};
    assign query_token_id = query_hit ? entry_token_id[query_calc_entry_index] :
                                      {TOKEN_ID_WIDTH{1'b0}};
    assign query_expected_bitmap = query_hit ? entry_expected_bitmap[query_calc_entry_index] :
                                             {EXPERT_BITMAP_WIDTH{1'b0}};
    assign query_residual_bitmap = query_hit ? entry_residual_bitmap[query_calc_entry_index] :
                                             {EXPERT_BITMAP_WIDTH{1'b0}};
    assign query_inflight_bitmap = query_hit ? entry_inflight_bitmap[query_calc_entry_index] :
                                             {EXPERT_BITMAP_WIDTH{1'b0}};
    assign query_token_len = query_hit ? entry_token_len[query_calc_entry_index] :
                                       {TOKEN_LEN_WIDTH{1'b0}};
    assign query_chunk_count = query_hit ? entry_chunk_count[query_calc_entry_index] :
                                         {CHUNK_COUNT_WIDTH{1'b0}};
    assign query_value_ptr = query_hit ? entry_value_ptr[query_calc_entry_index] :
                                       {VALUE_ADDR_WIDTH{1'b0}};

    genvar head_idx;
    generate
        for (head_idx = 0; head_idx < NUM_OWNERS; head_idx = head_idx + 1) begin : gen_dbg_owner_head_seq
            assign dbg_owner_head_seq_flat[(head_idx+1)*GLOBAL_SEQ_WIDTH-1 -: GLOBAL_SEQ_WIDTH] =
                owner_head_seq[head_idx];
        end
    endgenerate

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_accept <= 1'b0;
            init_drop_owner <= 1'b0;
            init_drop_window <= 1'b0;
            init_drop_busy <= 1'b0;
            init_entry_index <= {ENTRY_ADDR_WIDTH{1'b0}};
            clear_value_valid <= 1'b0;
            clear_value_addr <= {VALUE_ADDR_WIDTH{1'b0}};
            data_accept <= 1'b0;
            data_drop_owner <= 1'b0;
            data_drop_no_entry <= 1'b0;
            data_drop_unexpected <= 1'b0;
            data_drop_duplicate <= 1'b0;
            data_entry_index <= {ENTRY_ADDR_WIDTH{1'b0}};
            aggregate_task_valid <= 1'b0;
            aggregate_task_entry_index <= {ENTRY_ADDR_WIDTH{1'b0}};
            aggregate_task_value_addr <= {VALUE_ADDR_WIDTH{1'b0}};
            aggregate_task_owner_rank <= {OWNER_WIDTH{1'b0}};
            aggregate_task_global_seq <= {GLOBAL_SEQ_WIDTH{1'b0}};
            aggregate_task_token_id <= {TOKEN_ID_WIDTH{1'b0}};
            aggregate_task_expert_id <= {EXPERT_ID_WIDTH{1'b0}};
            aggregate_task_chunk_id <= {CHUNK_ID_WIDTH{1'b0}};
            release_accept <= 1'b0;
            release_drop_owner <= 1'b0;
            release_drop_no_entry <= 1'b0;
            release_drop_busy <= 1'b0;
            release_entry_index <= {ENTRY_ADDR_WIDTH{1'b0}};
            ready_valid <= 1'b0;
            ready_entry_index <= {ENTRY_ADDR_WIDTH{1'b0}};
            ready_owner_rank <= {OWNER_WIDTH{1'b0}};
            ready_microbatch_id <= {MICRO_ID_WIDTH{1'b0}};
            ready_global_seq <= {GLOBAL_SEQ_WIDTH{1'b0}};
            ready_token_id <= {TOKEN_ID_WIDTH{1'b0}};
            ready_value_ptr <= {VALUE_ADDR_WIDTH{1'b0}};

            for (i = 0; i < NUM_OWNERS; i = i + 1) begin
                owner_head_seq[i] <= {GLOBAL_SEQ_WIDTH{1'b0}};
            end

            for (i = 0; i < ENTRY_COUNT; i = i + 1) begin
                entry_valid[i] <= 1'b0;
                entry_state[i] <= ENTRY_FREE;
                entry_owner_rank[i] <= {OWNER_WIDTH{1'b0}};
                entry_microbatch_id[i] <= {MICRO_ID_WIDTH{1'b0}};
                entry_global_seq[i] <= {GLOBAL_SEQ_WIDTH{1'b0}};
                entry_token_id[i] <= {TOKEN_ID_WIDTH{1'b0}};
                entry_expected_bitmap[i] <= {EXPERT_BITMAP_WIDTH{1'b0}};
                entry_residual_bitmap[i] <= {EXPERT_BITMAP_WIDTH{1'b0}};
                entry_inflight_bitmap[i] <= {EXPERT_BITMAP_WIDTH{1'b0}};
                entry_token_len[i] <= {TOKEN_LEN_WIDTH{1'b0}};
                entry_chunk_count[i] <= {CHUNK_COUNT_WIDTH{1'b0}};
                entry_value_ptr[i] <= {VALUE_ADDR_WIDTH{1'b0}};
            end
        end
        else begin
            init_accept <= 1'b0;
            init_drop_owner <= 1'b0;
            init_drop_window <= 1'b0;
            init_drop_busy <= 1'b0;
            clear_value_valid <= 1'b0;
            data_accept <= 1'b0;
            data_drop_owner <= 1'b0;
            data_drop_no_entry <= 1'b0;
            data_drop_unexpected <= 1'b0;
            data_drop_duplicate <= 1'b0;
            aggregate_task_valid <= 1'b0;
            release_accept <= 1'b0;
            release_drop_owner <= 1'b0;
            release_drop_no_entry <= 1'b0;
            release_drop_busy <= 1'b0;
            release_entry_index <= {ENTRY_ADDR_WIDTH{1'b0}};
            ready_valid <= 1'b0;

            if (init_valid && init_ready) begin
                init_entry_index <= init_calc_entry_index;

                if (!init_owner_ok) begin
                    init_drop_owner <= 1'b1;
                end
                else if (!init_window_ok) begin
                    init_drop_window <= 1'b1;
                end
                else if (init_slot_busy) begin
                    init_drop_busy <= 1'b1;
                end
                else begin
                    init_accept <= 1'b1;
                    entry_valid[init_calc_entry_index] <= 1'b1;
                    entry_state[init_calc_entry_index] <= ENTRY_ACTIVE;
                    entry_owner_rank[init_calc_entry_index] <= init_owner_rank;
                    entry_microbatch_id[init_calc_entry_index] <= init_microbatch_id;
                    entry_global_seq[init_calc_entry_index] <= init_global_seq;
                    entry_token_id[init_calc_entry_index] <= init_token_id;
                    entry_expected_bitmap[init_calc_entry_index] <= init_expected_bitmap;
                    entry_residual_bitmap[init_calc_entry_index] <= init_expected_bitmap;
                    entry_inflight_bitmap[init_calc_entry_index] <= {EXPERT_BITMAP_WIDTH{1'b0}};
                    entry_token_len[init_calc_entry_index] <= init_token_len;
                    entry_chunk_count[init_calc_entry_index] <= init_chunk_count;
                    entry_value_ptr[init_calc_entry_index] <= init_calc_entry_index[VALUE_ADDR_WIDTH-1:0];
                    clear_value_valid <= 1'b1;
                    clear_value_addr <= init_calc_entry_index[VALUE_ADDR_WIDTH-1:0];
                end
            end

            if (data_valid && data_ready) begin
                data_entry_index <= data_calc_entry_index;

                if (!data_owner_ok) begin
                    data_drop_owner <= 1'b1;
                end
                else if (!data_entry_match) begin
                    data_drop_no_entry <= 1'b1;
                end
                else if (!data_expert_expected) begin
                    data_drop_unexpected <= 1'b1;
                end
                else if (!data_expert_residual || data_expert_inflight) begin
                    data_drop_duplicate <= 1'b1;
                end
                else begin
                    data_accept <= 1'b1;
                    entry_inflight_bitmap[data_calc_entry_index] <=
                        entry_inflight_bitmap[data_calc_entry_index] | data_expert_mask;

                    aggregate_task_valid <= 1'b1;
                    aggregate_task_entry_index <= data_calc_entry_index;
                    aggregate_task_value_addr <= entry_value_ptr[data_calc_entry_index];
                    aggregate_task_owner_rank <= data_owner_rank;
                    aggregate_task_global_seq <= data_global_seq;
                    aggregate_task_token_id <= data_token_id;
                    aggregate_task_expert_id <= data_expert_id;
                    aggregate_task_chunk_id <= data_chunk_id;
                end
            end

            if (aggregate_done_valid && aggregate_done_entry_valid) begin
                entry_inflight_bitmap[aggregate_done_entry_index] <=
                    entry_inflight_bitmap[aggregate_done_entry_index] & ~aggregate_done_expert_mask;
                entry_residual_bitmap[aggregate_done_entry_index] <= aggregate_done_next_residual;

                if ((entry_inflight_bitmap[aggregate_done_entry_index] & aggregate_done_expert_mask) !=
                    {EXPERT_BITMAP_WIDTH{1'b0}}) begin
                    if (aggregate_done_next_residual == {EXPERT_BITMAP_WIDTH{1'b0}}) begin
                        entry_state[aggregate_done_entry_index] <= ENTRY_READY;
                        ready_valid <= 1'b1;
                        ready_entry_index <= aggregate_done_entry_index;
                        ready_owner_rank <= entry_owner_rank[aggregate_done_entry_index];
                        ready_microbatch_id <= entry_microbatch_id[aggregate_done_entry_index];
                        ready_global_seq <= entry_global_seq[aggregate_done_entry_index];
                        ready_token_id <= entry_token_id[aggregate_done_entry_index];
                        ready_value_ptr <= entry_value_ptr[aggregate_done_entry_index];
                    end
                end
            end

            if (release_valid) begin
                release_entry_index <= release_calc_entry_index;

                if (!release_owner_ok) begin
                    release_drop_owner <= 1'b1;
                end
                else if (!release_entry_match) begin
                    release_drop_no_entry <= 1'b1;
                end
                else if (!release_entry_ready) begin
                    release_drop_busy <= 1'b1;
                end
                else begin
                    release_accept <= 1'b1;
                    entry_valid[release_calc_entry_index] <= 1'b0;
                    entry_state[release_calc_entry_index] <= ENTRY_FREE;
                    entry_owner_rank[release_calc_entry_index] <= {OWNER_WIDTH{1'b0}};
                    entry_microbatch_id[release_calc_entry_index] <= {MICRO_ID_WIDTH{1'b0}};
                    entry_global_seq[release_calc_entry_index] <= {GLOBAL_SEQ_WIDTH{1'b0}};
                    entry_token_id[release_calc_entry_index] <= {TOKEN_ID_WIDTH{1'b0}};
                    entry_expected_bitmap[release_calc_entry_index] <= {EXPERT_BITMAP_WIDTH{1'b0}};
                    entry_residual_bitmap[release_calc_entry_index] <= {EXPERT_BITMAP_WIDTH{1'b0}};
                    entry_inflight_bitmap[release_calc_entry_index] <= {EXPERT_BITMAP_WIDTH{1'b0}};
                    entry_token_len[release_calc_entry_index] <= {TOKEN_LEN_WIDTH{1'b0}};
                    entry_chunk_count[release_calc_entry_index] <= {CHUNK_COUNT_WIDTH{1'b0}};
                    entry_value_ptr[release_calc_entry_index] <= {VALUE_ADDR_WIDTH{1'b0}};
                    owner_head_seq[release_owner_rank] <= owner_head_seq[release_owner_rank] + 1'b1;
                end
            end
        end
    end
endmodule
