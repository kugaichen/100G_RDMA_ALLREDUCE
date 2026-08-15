`timescale 1ns / 1ps

module moe_payload_reduce_lane #(
    parameter ENTRY_COUNT = 16,
    parameter ENTRY_ADDR_WIDTH = $clog2(ENTRY_COUNT),
    parameter VALUE_ADDR_WIDTH = ENTRY_ADDR_WIDTH,
    parameter EXPERT_ID_WIDTH = 6,
    parameter CHUNK_ID_WIDTH = 8,
    parameter PAYLOAD_WIDTH = 512,
    parameter ADD_WIDTH = 32
) (
    input wire clk,
    input wire rst_n,

    input wire clear_value_valid,
    input wire [VALUE_ADDR_WIDTH-1:0] clear_value_addr,

    input wire task_valid,
    output wire task_ready,
    input wire [ENTRY_ADDR_WIDTH-1:0] task_entry_index,
    input wire [VALUE_ADDR_WIDTH-1:0] task_value_addr,
    input wire [EXPERT_ID_WIDTH-1:0] task_expert_id,
    input wire [CHUNK_ID_WIDTH-1:0] task_chunk_id,
    input wire [PAYLOAD_WIDTH-1:0] task_payload_data,

    output reg done_valid,
    output reg [ENTRY_ADDR_WIDTH-1:0] done_entry_index,
    output reg [EXPERT_ID_WIDTH-1:0] done_expert_id,
    output reg [CHUNK_ID_WIDTH-1:0] done_chunk_id,

    input wire query_valid,
    input wire [VALUE_ADDR_WIDTH-1:0] query_value_addr,
    output wire [PAYLOAD_WIDTH-1:0] query_value_data
);
    localparam CHUNK_COUNT = PAYLOAD_WIDTH / ADD_WIDTH;
    localparam S_IDLE = 3'd0;
    localparam S_READ = 3'd1;
    localparam S_ADD = 3'd2;
    localparam S_WRITE = 3'd3;
    localparam S_DONE = 3'd4;

    reg [PAYLOAD_WIDTH-1:0] value_mem [0:ENTRY_COUNT-1];
    reg [2:0] state;
    reg [ENTRY_ADDR_WIDTH-1:0] task_entry_index_r;
    reg [VALUE_ADDR_WIDTH-1:0] task_value_addr_r;
    reg [EXPERT_ID_WIDTH-1:0] task_expert_id_r;
    reg [CHUNK_ID_WIDTH-1:0] task_chunk_id_r;
    reg [PAYLOAD_WIDTH-1:0] task_payload_data_r;
    reg [PAYLOAD_WIDTH-1:0] aggregate_value_r;
    reg [PAYLOAD_WIDTH-1:0] sum_value_r;
    reg [PAYLOAD_WIDTH-1:0] sum_value_comb;

    assign task_ready = (state == S_IDLE);
    assign query_value_data = query_valid ? value_mem[query_value_addr] : {PAYLOAD_WIDTH{1'b0}};

    integer i;
    integer chunk_idx;
    always @(*) begin
        sum_value_comb = aggregate_value_r;
        for (chunk_idx = 0; chunk_idx < CHUNK_COUNT; chunk_idx = chunk_idx + 1) begin
            sum_value_comb[(chunk_idx+1)*ADD_WIDTH-1 -: ADD_WIDTH] =
                aggregate_value_r[(chunk_idx+1)*ADD_WIDTH-1 -: ADD_WIDTH] +
                task_payload_data_r[(chunk_idx+1)*ADD_WIDTH-1 -: ADD_WIDTH];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done_valid <= 1'b0;
            done_entry_index <= {ENTRY_ADDR_WIDTH{1'b0}};
            done_expert_id <= {EXPERT_ID_WIDTH{1'b0}};
            done_chunk_id <= {CHUNK_ID_WIDTH{1'b0}};
            task_entry_index_r <= {ENTRY_ADDR_WIDTH{1'b0}};
            task_value_addr_r <= {VALUE_ADDR_WIDTH{1'b0}};
            task_expert_id_r <= {EXPERT_ID_WIDTH{1'b0}};
            task_chunk_id_r <= {CHUNK_ID_WIDTH{1'b0}};
            task_payload_data_r <= {PAYLOAD_WIDTH{1'b0}};
            aggregate_value_r <= {PAYLOAD_WIDTH{1'b0}};
            sum_value_r <= {PAYLOAD_WIDTH{1'b0}};

            for (i = 0; i < ENTRY_COUNT; i = i + 1) begin
                value_mem[i] <= {PAYLOAD_WIDTH{1'b0}};
            end
        end
        else begin
            done_valid <= 1'b0;

            if (clear_value_valid) begin
                value_mem[clear_value_addr] <= {PAYLOAD_WIDTH{1'b0}};
            end

            case (state)
                S_IDLE: begin
                    if (task_valid && task_ready) begin
                        task_entry_index_r <= task_entry_index;
                        task_value_addr_r <= task_value_addr;
                        task_expert_id_r <= task_expert_id;
                        task_chunk_id_r <= task_chunk_id;
                        task_payload_data_r <= task_payload_data;
                        state <= S_READ;
                    end
                end

                S_READ: begin
                    aggregate_value_r <= value_mem[task_value_addr_r];
                    state <= S_ADD;
                end

                S_ADD: begin
                    sum_value_r <= sum_value_comb;
                    state <= S_WRITE;
                end

                S_WRITE: begin
                    value_mem[task_value_addr_r] <= sum_value_r;
                    state <= S_DONE;
                end

                S_DONE: begin
                    done_valid <= 1'b1;
                    done_entry_index <= task_entry_index_r;
                    done_expert_id <= task_expert_id_r;
                    done_chunk_id <= task_chunk_id_r;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
