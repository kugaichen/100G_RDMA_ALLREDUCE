`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/03 21:36:06
// Design Name: 
// Module Name: aggregator_core_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module aggregator_core_top #(
    parameter METADATA_LEN                  = 2*8+3+5,
    parameter PAYLOAD_ITEM_WIDTH            = 512,
    parameter INGRESS_PROT_NUM              = 2,
    parameter RING_SLOT_WIDTH               = 8,
    parameter WINDOWSIZE                    = RING_SLOT_WIDTH,
    parameter ADDR_WIDTH                    = 8,
    parameter DATA_WIDTH                    = 32,
    parameter OPCODE_WIDTH                  = 8,
    parameter OPCODE_ACK                    = 8'h11,
    parameter OPCODE_FIRST                  = 8'h0,
    parameter OPCODE_MIDDLE                 = 8'h1,
    parameter OPCODE_LAST                   = 8'h2,
    parameter OPCODE_SEND_ONLY              = 8'h4,

    parameter PAYLOAD_ITEM_NUM              = 2 * WINDOWSIZE,
    parameter PAYLOAD_ITEM_COUNT_WIDTH      = $clog2(PAYLOAD_ITEM_NUM),
    parameter BUFFER_SLOTS                  = 2 * WINDOWSIZE,
    parameter BUFFER_SLOTS_WIDTH            = $clog2(BUFFER_SLOTS),
    parameter FAN_IN                        = INGRESS_PROT_NUM,
    parameter FAN_IN_WIDTH                  = $clog2(FAN_IN),

    parameter BUFFER_GIVE_WAIT_CYCLE        = 2

)(
    input wire                      clk,
    input wire                      rst_n,

    // =================================================================
    // INPUTS from Parser
    // =================================================================
    input wire [METADATA_LEN-1:0]                               parser_agg_metadata,
    input wire [OPCODE_WIDTH-1:0]                               parser_agg_opcode,
    input wire                                                  parser_agg_payload_fire_en,
    input wire [RING_SLOT_WIDTH+PAYLOAD_ITEM_COUNT_WIDTH-1:0]   parser_payload_wr_addr,
    input wire [PAYLOAD_ITEM_WIDTH-1:0]                         parser_payload_wr_data,
    input wire                                                  parser_payload_wr_en,
    input wire [METADATA_LEN-1:0]                               parser_payload_wr_metadata,
    output wire                                                 parser_out_ready, // Backpressure to Parser

    // MoE slot-plane init path. This reuses the original AllReduce
    // new_slot_creater and its arrival/degree/aggregate BRAM arbiters.
    input wire                                                  moe_slot_init_valid,
    input wire [ADDR_WIDTH-1:0]                                 moe_slot_init_addr,
    output wire                                                 moe_slot_init_ready,
    output wire                                                 moe_slot_init_fire,

    // MoE aggregate update path. This path uses the original aggregate BRAM
    // read/write arbiters and updates one 512-bit payload item in place.
    input wire                                                  moe_aggregate_update_valid,
    input wire [ADDR_WIDTH-1:0]                                 moe_aggregate_update_addr,
    input wire [PAYLOAD_ITEM_WIDTH-1:0]                         moe_aggregate_update_data,
    output wire                                                 moe_aggregate_update_ready,
    output reg                                                  moe_aggregate_update_done,
    output reg [PAYLOAD_ITEM_WIDTH-1:0]                         moe_aggregate_update_sum_dbg,
    input wire                                                  moe_aggregate_query_valid,
    input wire [ADDR_WIDTH-1:0]                                 moe_aggregate_query_addr,
    output wire                                                 moe_aggregate_query_ready,
    output reg                                                  moe_aggregate_query_done,
    output reg [PAYLOAD_ITEM_WIDTH-1:0]                         moe_aggregate_query_data,
    input wire                                                  moe_arrival_update_valid,
    input wire [ADDR_WIDTH-1:0]                                 moe_arrival_update_addr,
    input wire [5:0]                                            moe_arrival_update_lane_id,
    output wire                                                 moe_arrival_update_ready,
    output reg                                                  moe_arrival_update_done,
    output reg [DATA_WIDTH-1:0]                                 moe_arrival_update_bitmap_dbg,

    // =================================================================
    // OUTPUTS to Deparser
    // =================================================================
    input  wire                                                 deparser_in_ready,
    output wire [METADATA_LEN-1:0]                              metadata_with_type_out_to_deparser,                 // 输出头部信息
    output wire                                                 Typer_ack_build_en_out_to_deparser,                 // up_ack类型
    output wire                                                 Typer_ack_down_en_out_to_deparser,                  // ack_down，实际不存在

    output wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]       aggregate_bram_payload_out_to_deparser,             // 输出payload信息
    output wire                                                 aggregator_FAN_retrans_en_out_to_deparser,          // no_root_up_data，重传给父节点
    output wire                                                 aggregator_FAN_first_trans_en_out_to_deparser,      // no_root_up_data，转发给父节点
    output wire                                                 aggregator_down_broadcast_en_out_to_deparser,       // root_up_data转down_data/或down_data，广播给子节点
    output wire                                                 aggregator_port_retrans_en_out_to_deparser          // up_data类型，特定port重传

);

    // =============================================================================
    // SECTION 1: INTERNAL WIRE DECLARATIONS
    // =============================================================================

    localparam ADD_CHUNK_WIDTH = 32;
    localparam CHUNKS_ITEM     = PAYLOAD_ITEM_WIDTH / ADD_CHUNK_WIDTH;

    localparam MOE_AGG_IDLE      = 3'd0;
    localparam MOE_AGG_READ_REQ  = 3'd1;
    localparam MOE_AGG_WAIT_READ = 3'd2;
    localparam MOE_AGG_WRITE_REQ = 3'd3;
    localparam MOE_AGG_DONE       = 3'd4;
    localparam MOE_AGG_QUERY_DONE = 3'd5;

    localparam MOE_ARR_IDLE      = 3'd0;
    localparam MOE_ARR_READ_REQ  = 3'd1;
    localparam MOE_ARR_WAIT_READ = 3'd2;
    localparam MOE_ARR_WRITE_REQ = 3'd3;
    localparam MOE_ARR_DONE      = 3'd4;

    genvar moe_sum_idx;

    // 1.1 --- Typer ---
    wire [METADATA_LEN-1:0]                                     metadata_with_type; 
    wire                                                        typer_data_root_up_en;
    wire                                                        typer_data_down_en;
    wire                                                        typer_ack_up_en;
    wire                                                        typer_data_noroot_up_en;
    wire                                                        typer_ack_down_en;

    wire                                                        typer_to_up_retrans_valid;
    wire                                                        typer_to_down_broadcast_valid;
    wire                                                        typer_to_deparser_valid;

    // Pipeline registers: Typer → retrans/down_broadcast 跨模块路径
    // 原理同 deparser 改动：用流水寄存器替代 LUT1 holdfix，
    // 让跨模块路径变成两段独立的 FF→FF 路径，每段有完整 4ns 周期。
    // valid 和 metadata 一起打一拍，下游 S1 正常采样，时序关系不变。
    reg [METADATA_LEN-1:0]                                      typer_metadata_to_retrans_r;
    reg                                                         typer_to_up_retrans_valid_r;
    reg [METADATA_LEN-1:0]                                      typer_metadata_to_down_broadcast_r;
    reg                                                         typer_to_down_broadcast_valid_r;

    wire                                                        typer_to_parser_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            typer_metadata_to_retrans_r         <= {METADATA_LEN{1'b0}};
            typer_to_up_retrans_valid_r         <= 1'b0;
            typer_metadata_to_down_broadcast_r  <= {METADATA_LEN{1'b0}};
            typer_to_down_broadcast_valid_r     <= 1'b0;
        end else begin
            typer_metadata_to_retrans_r         <= metadata_with_type;
            typer_to_up_retrans_valid_r         <= typer_to_up_retrans_valid;
            typer_metadata_to_down_broadcast_r  <= metadata_with_type;
            typer_to_down_broadcast_valid_r     <= typer_to_down_broadcast_valid;
        end
    end

    // 1.2 --- payload_bram and bram_write_demux ---
    // wire [PAYLOAD_ITEM_NUM-1:0]                                 parser_to_payload_bram_wr_en_demux;
    // wire [RING_SLOT_WIDTH-1:0]                                  parser_to_payload_bram_wr_addr_bus;
    // wire [PAYLOAD_ITEM_WIDTH-1:0]                               parser_to_payload_bram_wr_data_bus;
    // wire [PAYLOAD_ITEM_WIDTH-1:0]                               payload_bram_to_buffer_rd_data_demux [0:PAYLOAD_ITEM_NUM-1];

    wire [INGRESS_PROT_NUM:0]                                   payload_bram_bank_wr_en;
    wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]              payload_bram_bank_to_buffer_rd_data_pack [0:INGRESS_PROT_NUM];
    wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]              payload_bram_rd_pack;
    // Distributed per-item bank mux output (built inside parallel_aggregate_bram
    // generate block, uses bank_payload_item_j_r per-bank registers). Replaces
    // the centralized 8192-bit bank mux that used to span SLRs. Data is 1 cycle
    // later than a direct BRAM read (buffer_controller compensates by routing
    // retrans path through S_PIPE/S_PIPE2 like the other paths).
    wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]              payload_bram_rd_pack_distributed;
    reg                                                          parser_payload_wr_en_r;
    reg [METADATA_LEN-1:0]                                       parser_payload_wr_metadata_r;
    reg [RING_SLOT_WIDTH+PAYLOAD_ITEM_COUNT_WIDTH-1:0]           parser_payload_wr_addr_r;
    reg [PAYLOAD_ITEM_WIDTH-1:0]                                 parser_payload_wr_data_r;
    (* max_fanout = 12 *) reg [INGRESS_PROT_NUM:0]               payload_bram_bank_wr_en_r2;
    reg [RING_SLOT_WIDTH+PAYLOAD_ITEM_COUNT_WIDTH-1:0]           parser_payload_wr_addr_r2;
    reg [PAYLOAD_ITEM_WIDTH-1:0]                                 parser_payload_wr_data_r2;


    // 1.3 --- aggregate_bram ---
    wire [PAYLOAD_ITEM_WIDTH-1:0]                               aggregate_bram_rd_data_unpack [0:PAYLOAD_ITEM_NUM-1];
    wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]              aggregate_bram_rd_data_pack;
    // Distributed per-item registered version. 1 cycle later than
    // aggregate_bram_rd_data_pack. Used only by skid mux to deparser, and
    // matched by 1-cycle delay on up_broadcast's output signals so data and
    // valid arrive at skid in phase.
    wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]              aggregate_bram_rd_data_pack_distributed;

    wire [PAYLOAD_ITEM_WIDTH-1:0]                               updated_aggregate_bram_wr_vector_unpack [PAYLOAD_ITEM_NUM-1:0];
    

    // 1.4 --- retrans_checkor_arrival_updater --- 
    wire                                                        up_data_en;
    assign   up_data_en = typer_data_root_up_en || typer_data_noroot_up_en;
                               

    wire                                                        up_retrans_to_typer_in_ready;       // out to typer for ready in 

    wire                                                        up_retrans_to_arrival_arb_rd_en;    // arrival_rd
    wire [ADDR_WIDTH-1:0]                                       up_retrans_to_arrival_arb_rd_addr;

    wire [ADDR_WIDTH-1:0]                                       up_retrans_to_arrival_arb_wr_addr;  // arrival_wr
    wire                                                        up_retrans_to_arrival_arb_wr_en;
    wire [DATA_WIDTH-1:0]                                       up_retrans_to_arrival_arb_wr_data;

    wire [ADDR_WIDTH-1:0]                                       up_retrans_to_degree_arb_rd_addr;   // degree_rd
    wire                                                        up_retrans_to_degree_arb_rd_en;

    wire                                                        up_retrans_to_degree_arb_wr_en;     // degree_wr
    wire [ADDR_WIDTH-1:0]                                       up_retrans_to_degree_arb_wr_addr;
    wire [DATA_WIDTH-1:0]                                       up_retrans_to_degree_arb_wr_data;

    //out_to_buffer
    wire [METADATA_LEN-1:0]                                     up_retrans_to_buffer_metadata_out;
    wire                                                        up_retrans_to_buffer_valid;
    // wire                                                        up_retrans_to_buffer_ready;
    wire                                                        up_retrans_to_buffer_aggregate_payload_en;
    wire                                                        up_retrans_to_buffer_read_buffer_en;

    //out_to_up_broadcast
    wire [METADATA_LEN-1:0]                                     up_retrans_to_up_broadcast_metadata_out;
    wire                                                        up_retrans_to_up_broadcast_valid;
    // wire                                                        up_retrans_to_up_broadcast_ready;
    wire                                                        up_retrans_to_up_broadcast_FAN_retrans_check_en;

        //forwarding
    wire                                                        real_to_buffer_need_aggregator_for_port_retrans;
    wire                                                        real_to_broadcast_for_FAN_retrans_check_en;


    // 1.5 --- aggregate_buffer_controller ---
    wire                                                        buffer_to_merged_in_ready;

    wire [ADDR_WIDTH-1:0]                                       buffer_to_payload_bram_rd_addr;
    wire [PAYLOAD_ITEM_NUM-1:0]                                 buffer_to_payload_bram_rd_en_pack;
    wire [7:0]                                                  buffer_to_payload_bram_rd_idx;

    wire [ADDR_WIDTH-1:0]                                       buffer_to_aggregate_bram_arb_rd_addr;
    wire [PAYLOAD_ITEM_NUM-1:0]                                 buffer_to_aggregate_bram_arb_rd_en_pack;

    
    wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]              buffer_to_aggregate_bram_arb_wr_vector_pack;
    wire [PAYLOAD_ITEM_NUM-1:0]                                 buffer_to_aggregate_bram_arb_wr_en_pack;
    wire [ADDR_WIDTH-1:0]                                       buffer_to_aggregate_bram_arb_wr_addr;

    // Selects sum vs payload-passthrough at each per-BRAM adder mux
    wire                                                        buffer_task_is_aggregate_to_up_broadcast;

    // buffer_controller 不再驱动宽数据总线（每个 BRAM 在本地计算 wr_data）。
    // 把仲裁器 req1 输入 tie 到 0，避免 floating wire；仲裁器输出
    // aggregate_bram_wr_data_pack 现在也不再被 BRAM 使用，会被综合优化掉。
    assign buffer_to_aggregate_bram_arb_wr_vector_pack = {(PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH){1'b0}};

    wire [METADATA_LEN-1:0]                                     buffer_to_deparser_metadata_out;
    wire                                                        buffer_to_deparser_valid;
    wire                                                        buffer_to_deparser_up_port_retrans_ok_en;
    wire                                                        buffer_to_deparser_down_down_broadcast_ok_en;

    wire [METADATA_LEN-1:0]                                     buffer_to_up_broadcast_metadata_out;
    wire                                                        buffer_to_up_broadcast_valid;
    wire                                                        buffer_to_up_broadcast_check_en;

    wire                                                        buffer_to_up_retrans_ready;
    wire                                                        buffer_to_down_broadcast_ready;
    wire                                                        up_broadcast_to_buffer_ready;


    // 1.6 --- up_broadcast_checkor_arrival_update ---
    wire                                                        up_broadcast_to_arrival_arb_rd_en;
    wire [ADDR_WIDTH-1:0]                                       up_broadcast_to_arrival_arb_rd_addr;

    wire                                                        up_broadcast_to_arrival_arb_wr_en;
    wire [ADDR_WIDTH-1:0]                                       up_broadcast_to_arrival_arb_wr_addr;
    wire [DATA_WIDTH-1:0]                                       up_broadcast_to_arrival_arb_wr_data;

    wire                                                        up_broadcast_to_degree_arb_rd_en;
    wire [ADDR_WIDTH-1:0]                                       up_broadcast_to_degree_arb_rd_addr;

    wire [ADDR_WIDTH-1:0]                                       up_broadcast_to_aggregate_bram_arb_rd_addr;
    wire [PAYLOAD_ITEM_NUM-1:0]                                 up_broadcast_to_aggregate_bram_arb_rd_en_pack;

    wire                                                        up_broadcast_to_sloter_valid;
    // wire                                                        up_broadcast_to_sloter_ready;
    wire                                                        up_broadcast_to_sloter_new_slot_en;
    wire [METADATA_LEN-1:0]                                     up_broadcast_to_sloter_metadata_out;                                                 

    wire                                                        up_broadcast_to_deparser_valid;
    // wire                                                        up_broadcast_to_deparser_ready;
    wire                                                        up_broadcast_to_deparser_FAN_retrans_en;
    wire                                                        up_broadcast_to_deparser_down_broadcast_en;
    wire                                                        up_broadcast_to_deparser_FAN_trans_en;
    wire [METADATA_LEN-1:0]                                     up_broadcast_to_deparser_metadata_out;

    wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]              up_broadcast_to_deparser_aggregate_bram_out;
    wire                                                        in_ready;

    wire                                                        up_broadcast_to_up_retrans_ready;


    // 1.7 --- new_slot_creater ---
    wire                                                        sloter_out_ready;

    wire                                                        sloter_to_arrival_arb_wr_en;
    wire [ADDR_WIDTH-1:0]                                       sloter_to_arrival_arb_wr_addr;
    wire [DATA_WIDTH-1:0]                                       sloter_to_arrival_arb_wr_data;

    wire                                                        sloter_to_degree_arb_wr_en;
    wire [ADDR_WIDTH-1:0]                                       sloter_to_degree_arb_wr_addr;
    wire [DATA_WIDTH-1:0]                                       sloter_to_degree_arb_wr_data;

    wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]              sloter_to_aggregate_bram_arb_wr_vector_pack;
    wire [ADDR_WIDTH-1:0]                                       sloter_to_aggregate_bram_arb_wr_addr;
    wire [PAYLOAD_ITEM_NUM-1:0]                                 sloter_to_aggregate_bram_arb_wr_en_pack;

    wire                                                        sloter_to_up_broadcast_ready;
    wire                                                        sloter_new_slot_en;
    wire [METADATA_LEN-1:0]                                     sloter_metadata_in;
    wire [ADDR_WIDTH-1:0]                                       sloter_addr_override;
    wire                                                        sloter_addr_override_en;

    assign sloter_out_ready = 1'b1;
    assign moe_slot_init_ready = sloter_to_up_broadcast_ready &&
                                 !up_broadcast_to_sloter_new_slot_en;
    assign moe_slot_init_fire = moe_slot_init_valid && moe_slot_init_ready;
    assign sloter_new_slot_en = up_broadcast_to_sloter_new_slot_en ||
                                moe_slot_init_fire;
    assign sloter_metadata_in = up_broadcast_to_sloter_new_slot_en ?
                                up_broadcast_to_sloter_metadata_out :
                                {METADATA_LEN{1'b0}};
    assign sloter_addr_override = moe_slot_init_addr;
    assign sloter_addr_override_en = moe_slot_init_fire;

    // 1.8 --- down_broadcast_checkor_arrival_updater ---
    wire                                                        down_broadcast_to_typer_in_ready;
    // wire                                                        merge_to_down_broadcast_out_ready;

    wire                                                        down_broadcast_to_arrival_arb_rd_en;
    wire [ADDR_WIDTH-1:0]                                       down_broadcast_to_arrival_arb_rd_addr;

    wire                                                        down_broadcast_to_arrival_arb_wr_en;
    wire [ADDR_WIDTH-1:0]                                       down_broadcast_to_arrival_arb_wr_addr;
    wire [DATA_WIDTH-1:0]                                       down_broadcast_to_arrival_arb_wr_data;

    wire                                                        down_broadcast_to_buffer_valid;
    wire [METADATA_LEN-1:0]                                     down_broadcast_to_buffer_metadata_out;
    wire                                                        down_broadcast_to_buffer_copy_buffer_en;

    wire                                                        down_broadcast_to_degree_arb_rd_en;
    wire [ADDR_WIDTH-1:0]                                       down_broadcast_to_degree_arb_rd_addr;

    wire                                                        down_broadcast_to_deparser_valid;
    wire [METADATA_LEN-1:0]                                     down_broadcast_to_deparser_metadata_out;
    wire                                                        down_broadcast_to_deparser_down_broadcast_en;

    
    // 1.9 --- aggregate_bram_rd_arbiter ---
    wire                                                        aggregate_bram_arb_to_up_broadcast_rd_grant;
    wire                                                        aggregate_bram_arb_to_buffer_rd_grant;
    wire                                                        aggregate_bram_arb_to_moe_rd_grant;
    wire [PAYLOAD_ITEM_NUM-1:0]                                 aggregate_bram_rd_en_pack;
    wire [ADDR_WIDTH-1:0]                                       aggregate_bram_rd_addr_pack;   


    // 1.10 --- aggregate_bram_wr_arbiter ---
    wire                                                        aggregate_bram_arb_to_buffer_wr_grant;
    wire                                                        aggregate_bram_arb_to_sloter_wr_grant;
    wire                                                        aggregate_bram_arb_to_moe_wr_grant;
    wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]              aggregate_bram_wr_data_pack;
    wire [ADDR_WIDTH-1:0]                                       aggregate_bram_wr_addr_pack;
    wire [PAYLOAD_ITEM_NUM-1:0]                                 aggregate_bram_wr_en_pack;

    wire [PAYLOAD_ITEM_NUM-1:0]                                 moe_to_aggregate_bram_arb_rd_en_pack;
    wire [ADDR_WIDTH-1:0]                                       moe_to_aggregate_bram_arb_rd_addr;
    wire [PAYLOAD_ITEM_NUM-1:0]                                 moe_to_aggregate_bram_arb_wr_en_pack;
    wire [ADDR_WIDTH-1:0]                                       moe_to_aggregate_bram_arb_wr_addr;
    wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]              moe_to_aggregate_bram_arb_wr_vector_pack;

    reg [2:0]                                                    moe_aggregate_state;
    reg [ADDR_WIDTH-1:0]                                         moe_aggregate_addr_r;
    reg [PAYLOAD_ITEM_WIDTH-1:0]                                 moe_aggregate_payload_r;
    reg [PAYLOAD_ITEM_WIDTH-1:0]                                 moe_aggregate_old_r;
    reg                                                          moe_aggregate_query_active_r;
    wire [PAYLOAD_ITEM_WIDTH-1:0]                                moe_aggregate_sum_comb;
    wire [PAYLOAD_ITEM_WIDTH-1:0]                                moe_aggregate_rd_item0;

    // 1.11 --- arrival_state_rd_arbiter ---
    wire                                                        arrival_arb_to_down_broadcast_rd_grant0;
    wire                                                        arrival_arb_to_up_broadcast_rd_grant1;
    wire                                                        arrival_arb_to_up_retrans_rd_grant2;
    wire                                                        arrival_arb_to_moe_rd_grant3;
    wire                                                        allreduce_arrival_state_rd_en;
    wire [ADDR_WIDTH-1:0]                                       allreduce_arrival_state_rd_addr;

    // 1.12 --- arrival_state_wr_arbiter ---
    wire                                                        arrival_arb_to_down_broadcast_wr_grant0;
    wire                                                        arrival_arb_to_sloter_wr_grant1;
    wire                                                        arrival_arb_to_up_broadcast_wr_grant2;
    wire                                                        arrival_arb_to_up_retrans_wr_grant3;
    wire                                                        arrival_arb_to_moe_wr_grant4;
    wire                                                        allreduce_arrival_state_wr_en;
    wire [ADDR_WIDTH-1:0]                                       allreduce_arrival_state_wr_addr;
    wire [DATA_WIDTH-1:0]                                       allreduce_arrival_state_wr_data;
    wire                                                        moe_to_arrival_arb_rd_en;
    wire [ADDR_WIDTH-1:0]                                       moe_to_arrival_arb_rd_addr;
    wire                                                        moe_to_arrival_arb_wr_en;
    wire [ADDR_WIDTH-1:0]                                       moe_to_arrival_arb_wr_addr;
    wire [DATA_WIDTH-1:0]                                       moe_to_arrival_arb_wr_data;
    reg [2:0]                                                   moe_arrival_state;
    reg [ADDR_WIDTH-1:0]                                        moe_arrival_addr_r;
    reg [5:0]                                                   moe_arrival_lane_id_r;
    reg [DATA_WIDTH-1:0]                                        moe_arrival_old_bitmap_r;
    wire [DATA_WIDTH-1:0]                                       moe_arrival_lane_mask;
    wire [DATA_WIDTH-1:0]                                       moe_arrival_next_bitmap;

    // 1.13 --- arrival_state_bram --- 
    wire [DATA_WIDTH-1:0]                                       allreduce_arrival_state_rd_data;


    // 1.14 --- degree_state_rd_arbiter ---
    wire                                                        degree_arb_to_down_broadcast_rd_grant0;
    wire                                                        degree_arb_to_up_broadcast_rd_grant0;
    wire                                                        degree_arb_to_up_retrans_rd_grant1;
    wire                                                        allreduce_degree_state_rd_en;
    wire [ADDR_WIDTH-1:0]                                       allreduce_degree_state_rd_addr;

    // 1.15 --- degree_state_wr_arbiter ---
    wire                                                        degree_arb_to_down_broadcast_wr_grant0;
    wire                                                        degree_arb_to_sloter_wr_grant1;
    wire                                                        degree_arb_to_up_broadcast_wr_grant2;
    wire                                                        degree_arb_to_up_retrans_wr_grant3;
    wire                                                        allreduce_degree_state_wr_en;
    wire [ADDR_WIDTH-1:0]                                       allreduce_degree_state_wr_addr;
    wire [DATA_WIDTH-1:0]                                       allreduce_degree_state_wr_data;


    // 1.16 --- degree_state_bram ---
    wire [DATA_WIDTH-1:0]                                       allreduce_degree_state_rd_data;

    // 1.17 --- deparser ---
    wire deparser_to_typer_ready;
    wire deparser_to_buffer_ready;
    wire deparser_to_down_broadcast_ready;
    wire deparser_to_up_broadcast_ready;
    wire pipe_can_accept;


    // =============================================================================
    // UPDATE: Add a payload write monitor for parser-aggregator top
    // =============================================================================
    reg payload_write_done;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            payload_write_done <= 1'b0;
        end
        else begin
            // Track the registered wr_en/wr_addr so payload_write_done stays
            // aligned with actual BRAM writes after the 2-cycle pipeline stage.
            if ((|payload_bram_bank_wr_en_r2) && parser_payload_wr_addr_r2[PAYLOAD_ITEM_COUNT_WIDTH-1:0] == (PAYLOAD_ITEM_NUM - 1) - BUFFER_GIVE_WAIT_CYCLE) begin
                payload_write_done <= 1'b1;
            end

            // 监测写结束 (Address 15) -> 变绿灯
            else begin
               payload_write_done <= 1'b0;
            end
        end
    end

    // =============================================================================
    // SECTION 2: MODULE INSTANTIATION
    // =============================================================================

    // 2.1 --- Typer ---
    Typer #(
        .FAN_IN(FAN_IN),
        .OPCODE_ACK(OPCODE_ACK),
        .OPCODE_FIRST(OPCODE_FIRST),
        .OPCODE_MIDDLE(OPCODE_MIDDLE),
        .OPCODE_LAST(OPCODE_LAST),
        .OPCODE_SEND_ONLY(OPCODE_SEND_ONLY)
    ) allreduce_typer (
        .clk(clk),
        .rst_n(rst_n),
        .metadata_without_type(parser_agg_metadata),
        .aggregate_en(parser_agg_payload_fire_en),
        .opcode(parser_agg_opcode),

        .metadata_with_type(metadata_with_type),

        .data_root_up_en(typer_data_root_up_en),
        .data_down_en(typer_data_down_en),
        .ack_up_en(typer_ack_up_en),
        .data_noroot_up_en(typer_data_noroot_up_en),
        .ack_down_en(typer_ack_down_en),

        .to_up_retrans_valid(typer_to_up_retrans_valid),
        .to_down_broadcast_valid(typer_to_down_broadcast_valid),
        .to_deparser_valid(typer_to_deparser_valid),

        .to_up_retrans_ready(up_retrans_to_typer_in_ready),
        .to_down_broadcast_ready(down_broadcast_to_typer_in_ready),
        .to_deparser_ready(deparser_to_typer_ready),

        .in_ready(typer_to_parser_ready)
    );

    // 2.2 --- payload_bram and bram_write_demux ---

    // Pipeline registers: break parser → payload BRAM control path
    // (parser is in SLR1, BRAMs span SLR0+SLR1, the bank decode + demux
    //  combinational path was the worst setup violator at 250MHz)
    // Stage 2: bank-decoded wr_en and forwarded addr/data. Splits the
    // long fanout-47 LUT chain to the demux into two cycles. max_fanout
    // on the per-bank wr_en reg lets each replica be placed near its
    // own ~16 BRAMs (12 chosen so the synthesizer makes ~2 replicas).
    integer pi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            parser_payload_wr_en_r       <= 1'b0;
            parser_payload_wr_metadata_r <= {METADATA_LEN{1'b0}};
            parser_payload_wr_addr_r     <= 0;
            parser_payload_wr_data_r     <= 0;
            payload_bram_bank_wr_en_r2   <= 0;
            parser_payload_wr_addr_r2    <= 0;
            parser_payload_wr_data_r2    <= 0;
        end
        else begin
            parser_payload_wr_en_r       <= parser_payload_wr_en;
            parser_payload_wr_metadata_r <= parser_payload_wr_metadata;
            parser_payload_wr_addr_r     <= parser_payload_wr_addr;
            parser_payload_wr_data_r     <= parser_payload_wr_data;
            for (pi = 0; pi <= INGRESS_PROT_NUM; pi = pi + 1) begin
                payload_bram_bank_wr_en_r2[pi] <= parser_payload_wr_en_r && (parser_payload_wr_metadata_r[7:0] == pi);
            end
            parser_payload_wr_addr_r2    <= parser_payload_wr_addr_r;
            parser_payload_wr_data_r2    <= parser_payload_wr_data_r;
        end
    end

    genvar port_idx;
    generate
        for (port_idx = 0; port_idx <= INGRESS_PROT_NUM; port_idx = port_idx + 1) begin: PAYLAOD_BRAM_BANK

            // bank wr_en now comes from the registered payload_bram_bank_wr_en_r2
            assign payload_bram_bank_wr_en[port_idx] = payload_bram_bank_wr_en_r2[port_idx];

            // --- Demux and BRAM array for each bank ---
            // Note: Each bank has its own demux and its own array of 16 BRAMs
            wire [PAYLOAD_ITEM_NUM-1:0]                         parser_to_payload_bram_wr_en_demux;
            wire [ADDR_WIDTH-1:0]                                parser_to_payload_bram_wr_addr_bus;
            wire [PAYLOAD_ITEM_WIDTH-1:0]                       parser_to_payload_bram_wr_data_bus;

            bram_write_demux #(
                .PARALLEL_NUM(PAYLOAD_ITEM_NUM),
                .SLOT_ADDR_WIDTH(ADDR_WIDTH),
                .ITEM_ADDR_WIDTH(PAYLOAD_ITEM_COUNT_WIDTH),
                .PAYLOAD_ITEM_WIDTH(PAYLOAD_ITEM_WIDTH)
            ) parser_payload_demux(
                .parser_wr_en(payload_bram_bank_wr_en[port_idx]),
                .parser_wr_addr(parser_payload_wr_addr_r2[ADDR_WIDTH+PAYLOAD_ITEM_COUNT_WIDTH-1:0]),
                .parser_wr_data(parser_payload_wr_data_r2),
                .parallel_wr_addr(parser_to_payload_bram_wr_addr_bus),
                .parallel_wr_en(parser_to_payload_bram_wr_en_demux),
                .parallel_wr_data(parser_to_payload_bram_wr_data_bus)
            );

            wire [PAYLOAD_ITEM_WIDTH-1:0]                       payload_bram_to_buffer_rd_data_demux[0:PAYLOAD_ITEM_NUM-1];

            // SLR-friendly per-bank decode: register rd_idx and rd_en_pack
            // locally inside each bank so the (rd_idx==port_idx) compare and
            // rd_en gating LUT live in the same SLR as this bank's BRAM
            // array. Otherwise the controller's rd_idx FF (placed in one
            // SLR) drives bank-decode LUTs that route across SLRs to BRAM
            // EN, dominating WNS. Bank-side read is shifted by 1 cycle;
            // aggregate_buffer_controller's FSM adds a matching S_WAIT_READ2.
            (* DONT_TOUCH = "TRUE" *) reg [7:0]                  rd_idx_local_r;
            (* DONT_TOUCH = "TRUE" *) reg [PAYLOAD_ITEM_NUM-1:0] rd_en_pack_local_r;
            always @(posedge clk) begin
                rd_idx_local_r     <= buffer_to_payload_bram_rd_idx;
                rd_en_pack_local_r <= buffer_to_payload_bram_rd_en_pack;
            end
            wire bank_selected_for_read = (rd_idx_local_r == port_idx);
            genvar i;
            for (i = 0; i < PAYLOAD_ITEM_NUM; i = i + 1) begin: parallel_payload_bram
                payload_bram #(
                    .USE_LUTRAM(0),
                    .BUFFER_SLOTS(BUFFER_SLOTS),
                    .DATA_WIDTH(PAYLOAD_ITEM_WIDTH),
                    .ADDR_WIDTH(ADDR_WIDTH)
                ) payload_bram_inst (
                    .clk(clk),
                    .wr_en(parser_to_payload_bram_wr_en_demux[i]),
                    .wr_addr(parser_to_payload_bram_wr_addr_bus),
                    .wr_data(parser_to_payload_bram_wr_data_bus),
                    .rd_en(rd_en_pack_local_r[i] && bank_selected_for_read),
                    .rd_addr(buffer_to_payload_bram_rd_addr),
                    .rd_data(payload_bram_to_buffer_rd_data_demux[i])
                );
            
                assign payload_bram_bank_to_buffer_rd_data_pack[port_idx][(i+1)*PAYLOAD_ITEM_WIDTH-1 -: PAYLOAD_ITEM_WIDTH] = payload_bram_to_buffer_rd_data_demux[i];
            end
        end
    endgenerate

    
    // --- Read Data Multiplexer ---
    // The centralized 8192-bit bank mux used to live here:
    //     payload_bram_rd_pack = payload_bram_bank_to_buffer_rd_data_pack[idx];
    // It produced a wide bus that had to cross SLRs to reach the distributed
    // adders, dominating the worst setup path. The mux is now distributed into
    // each parallel_aggregate_bram[j] generate iter (each iter selects only its
    // own 512-bit slice from each bank), so this signal is no longer needed.
    // Kept driven for legacy taps below the generate block (deparser pass-through).
    // Now uses the distributed per-item bank mux (via bank_payload_item_j_r) instead
    // of the centralized mux that spanned SLRs. Data is 1 cycle later than direct
    // BRAM Q, but buffer_controller compensates by routing retrans through S_PIPE.
    assign payload_bram_rd_pack = payload_bram_rd_pack_distributed;


    // ----------------------------------------------
    // bram_write_demux #(
    //     .PARALLEL_NUM(PAYLOAD_ITEM_NUM),
    //     .SLOT_ADDR_WIDTH(RING_SLOT_WIDTH),
    //     .ITEM_ADDR_WIDTH(PAYLOAD_ITEM_COUNT_WIDTH),
    //     .PAYLOAD_ITEM_WIDTH(PAYLOAD_ITEM_WIDTH)
    // ) parser_payload_demux(
    //     .parser_wr_en(parser_payload_wr_en),
    //     .parser_wr_addr(parser_payload_wr_addr),
    //     .parser_wr_data(parser_payload_wr_data),
    //     .parallel_wr_addr(parser_to_payload_bram_wr_addr_bus),
    //     .parallel_wr_en(parser_to_payload_bram_wr_en_demux),
    //     .parallel_wr_data(parser_to_payload_bram_wr_data_bus)
    // );

    // genvar i;
    // generate
    //     for (i = 0; i < PAYLOAD_ITEM_NUM; i = i + 1) begin: parallel_payload_bram
    //         payload_bram #(
    //             .BUFFER_SLOTS(BUFFER_SLOTS), 
    //             .DATA_WIDTH(PAYLOAD_ITEM_WIDTH), 
    //             .ADDR_WIDTH(RING_SLOT_WIDTH)
    //         ) payload_bram_inst (
    //             .clk(clk),
    //             .wr_en(parser_to_payload_bram_wr_en_demux[i]), 
    //             .wr_addr(parser_to_payload_bram_wr_addr_bus), 
    //             .wr_data(parser_to_payload_bram_wr_data_bus),
    //             .rd_en(buffer_to_payload_bram_rd_en),
    //             .rd_addr(buffer_to_payload_bram_rd_addr), 
    //             .rd_data(payload_bram_to_buffer_rd_data_demux[i])
    //         );

    //         assign payload_bram_to_buffer_rd_data_pack[(i+1)*PAYLOAD_ITEM_WIDTH-1 -: PAYLOAD_ITEM_WIDTH] = payload_bram_to_buffer_rd_data_demux[i];
    //     end
    // endgenerate

    // 2.3 --- aggregate_bram ---
    // aggregate_bram #(
    //     .BUFFER_SLOTS(BUFFER_SLOTS),
    //     .DATA_WIDTH(PAYLOAD_ITEM_WWIDTH),
    //     .ADDR_WIDTH(ADDR_WIDTH)
    // ) aggregate_bram_init (
    //     .clk(clk),
    //     .wr_en(buffer_to_aggregate_bram_wr_en),
    //     .wr_data(buffer_to_aggregate_bram_wr_pack),
    //     .rd_data(aggregate_bram_to_buffer_rd_pack)
    // );

    // 2.3 --- aggregate_bram ---
    // Distributed adders: each aggregate BRAM has its own 512-bit adder + write mux
    // placed alongside it (instead of one centralized 8192-bit adder in
    // aggregate_buffer_controller). This eliminates the wide cross-SLR data
    // bus that was the worst setup violator at 250MHz.
    //
    // Write data sources for each aggregate BRAM:
    //   - sloter wins arbiter (new slot init)         -> sloter slice
    //   - buffer wins, task is aggregate              -> chunk-wise sum (a + b)
    //   - buffer wins, task is download/copy          -> payload pass-through
    //
    // The adder operands come from BRAM rd_data registered outputs (sticky
    // until next rd_en), so no extra latches are needed.
    assign moe_aggregate_update_ready = (moe_aggregate_state == MOE_AGG_IDLE);
    assign moe_aggregate_query_ready = (moe_aggregate_state == MOE_AGG_IDLE) &&
                                       (!moe_aggregate_update_valid);
    assign moe_aggregate_rd_item0 = aggregate_bram_rd_data_pack[PAYLOAD_ITEM_WIDTH-1:0];
    assign moe_to_aggregate_bram_arb_rd_en_pack =
        (moe_aggregate_state == MOE_AGG_READ_REQ) ?
        {{(PAYLOAD_ITEM_NUM-1){1'b0}}, 1'b1} :
        {PAYLOAD_ITEM_NUM{1'b0}};
    assign moe_to_aggregate_bram_arb_rd_addr = moe_aggregate_addr_r;
    assign moe_to_aggregate_bram_arb_wr_en_pack =
        (moe_aggregate_state == MOE_AGG_WRITE_REQ) ?
        {{(PAYLOAD_ITEM_NUM-1){1'b0}}, 1'b1} :
        {PAYLOAD_ITEM_NUM{1'b0}};
    assign moe_to_aggregate_bram_arb_wr_addr = moe_aggregate_addr_r;
    assign moe_to_aggregate_bram_arb_wr_vector_pack = {
        {(PAYLOAD_ITEM_NUM-1)*PAYLOAD_ITEM_WIDTH{1'b0}},
        moe_aggregate_sum_comb
    };

    generate
        for (moe_sum_idx = 0; moe_sum_idx < CHUNKS_ITEM; moe_sum_idx = moe_sum_idx + 1) begin : moe_agg_add_chunks
            assign moe_aggregate_sum_comb[(moe_sum_idx+1)*ADD_CHUNK_WIDTH-1 -: ADD_CHUNK_WIDTH] =
                moe_aggregate_old_r[(moe_sum_idx+1)*ADD_CHUNK_WIDTH-1 -: ADD_CHUNK_WIDTH] +
                moe_aggregate_payload_r[(moe_sum_idx+1)*ADD_CHUNK_WIDTH-1 -: ADD_CHUNK_WIDTH];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            moe_aggregate_state <= MOE_AGG_IDLE;
            moe_aggregate_addr_r <= {ADDR_WIDTH{1'b0}};
            moe_aggregate_payload_r <= {PAYLOAD_ITEM_WIDTH{1'b0}};
            moe_aggregate_old_r <= {PAYLOAD_ITEM_WIDTH{1'b0}};
            moe_aggregate_query_active_r <= 1'b0;
            moe_aggregate_update_done <= 1'b0;
            moe_aggregate_update_sum_dbg <= {PAYLOAD_ITEM_WIDTH{1'b0}};
            moe_aggregate_query_done <= 1'b0;
            moe_aggregate_query_data <= {PAYLOAD_ITEM_WIDTH{1'b0}};
        end
        else begin
            moe_aggregate_update_done <= 1'b0;
            moe_aggregate_query_done <= 1'b0;

            case (moe_aggregate_state)
                MOE_AGG_IDLE: begin
                    if (moe_aggregate_update_valid && moe_aggregate_update_ready) begin
                        moe_aggregate_addr_r <= moe_aggregate_update_addr;
                        moe_aggregate_payload_r <= moe_aggregate_update_data;
                        moe_aggregate_query_active_r <= 1'b0;
                        moe_aggregate_state <= MOE_AGG_READ_REQ;
                    end
                    else if (moe_aggregate_query_valid && moe_aggregate_query_ready) begin
                        moe_aggregate_addr_r <= moe_aggregate_query_addr;
                        moe_aggregate_payload_r <= {PAYLOAD_ITEM_WIDTH{1'b0}};
                        moe_aggregate_query_active_r <= 1'b1;
                        moe_aggregate_state <= MOE_AGG_READ_REQ;
                    end
                end

                MOE_AGG_READ_REQ: begin
                    if (aggregate_bram_arb_to_moe_rd_grant) begin
                        moe_aggregate_state <= MOE_AGG_WAIT_READ;
                    end
                end

                MOE_AGG_WAIT_READ: begin
                    if (moe_aggregate_query_active_r) begin
                        moe_aggregate_query_data <= moe_aggregate_rd_item0;
                        moe_aggregate_state <= MOE_AGG_QUERY_DONE;
                    end
                    else begin
                        moe_aggregate_old_r <= moe_aggregate_rd_item0;
                        moe_aggregate_state <= MOE_AGG_WRITE_REQ;
                    end
                end

                MOE_AGG_WRITE_REQ: begin
                    if (aggregate_bram_arb_to_moe_wr_grant) begin
                        moe_aggregate_update_sum_dbg <= moe_aggregate_sum_comb;
                        moe_aggregate_state <= MOE_AGG_DONE;
                    end
                end

                MOE_AGG_DONE: begin
                    moe_aggregate_update_done <= 1'b1;
                    moe_aggregate_state <= MOE_AGG_IDLE;
                end

                MOE_AGG_QUERY_DONE: begin
                    moe_aggregate_query_done <= 1'b1;
                    moe_aggregate_query_active_r <= 1'b0;
                    moe_aggregate_state <= MOE_AGG_IDLE;
                end

                default: begin
                    moe_aggregate_query_active_r <= 1'b0;
                    moe_aggregate_state <= MOE_AGG_IDLE;
                end
            endcase
        end
    end

    assign moe_arrival_update_ready = (moe_arrival_state == MOE_ARR_IDLE);
    assign moe_arrival_lane_mask =
        (moe_arrival_lane_id_r < DATA_WIDTH) ?
        ({ {(DATA_WIDTH-1){1'b0}}, 1'b1 } << moe_arrival_lane_id_r) :
        {DATA_WIDTH{1'b0}};
    assign moe_arrival_next_bitmap = moe_arrival_old_bitmap_r | moe_arrival_lane_mask;
    assign moe_to_arrival_arb_rd_en = (moe_arrival_state == MOE_ARR_READ_REQ);
    assign moe_to_arrival_arb_rd_addr = moe_arrival_addr_r;
    assign moe_to_arrival_arb_wr_en = (moe_arrival_state == MOE_ARR_WRITE_REQ);
    assign moe_to_arrival_arb_wr_addr = moe_arrival_addr_r;
    assign moe_to_arrival_arb_wr_data = moe_arrival_next_bitmap;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            moe_arrival_state <= MOE_ARR_IDLE;
            moe_arrival_addr_r <= {ADDR_WIDTH{1'b0}};
            moe_arrival_lane_id_r <= 6'd0;
            moe_arrival_old_bitmap_r <= {DATA_WIDTH{1'b0}};
            moe_arrival_update_done <= 1'b0;
            moe_arrival_update_bitmap_dbg <= {DATA_WIDTH{1'b0}};
        end
        else begin
            moe_arrival_update_done <= 1'b0;

            case (moe_arrival_state)
                MOE_ARR_IDLE: begin
                    if (moe_arrival_update_valid && moe_arrival_update_ready) begin
                        moe_arrival_addr_r <= moe_arrival_update_addr;
                        moe_arrival_lane_id_r <= moe_arrival_update_lane_id;
                        moe_arrival_state <= MOE_ARR_READ_REQ;
                    end
                end

                MOE_ARR_READ_REQ: begin
                    if (arrival_arb_to_moe_rd_grant3) begin
                        moe_arrival_state <= MOE_ARR_WAIT_READ;
                    end
                end

                MOE_ARR_WAIT_READ: begin
                    moe_arrival_old_bitmap_r <= allreduce_arrival_state_rd_data;
                    moe_arrival_state <= MOE_ARR_WRITE_REQ;
                end

                MOE_ARR_WRITE_REQ: begin
                    if (arrival_arb_to_moe_wr_grant4) begin
                        moe_arrival_update_bitmap_dbg <= moe_arrival_next_bitmap;
                        moe_arrival_state <= MOE_ARR_DONE;
                    end
                end

                MOE_ARR_DONE: begin
                    moe_arrival_update_done <= 1'b1;
                    moe_arrival_state <= MOE_ARR_IDLE;
                end

                default: begin
                    moe_arrival_state <= MOE_ARR_IDLE;
                end
            endcase
        end
    end

    genvar j;
    generate
        for (j = 0; j < PAYLOAD_ITEM_NUM; j = j + 1) begin : parallel_aggregate_bram

            // Distributed bank mux: select only this iter's 512-bit slice from
            // each bank. Each bank slice is registered right at the BRAM
            // output (bank_payload_item_j_r) so the FF can be placed in the
            // same SLR as the source BRAM. Without this, Vivado was placing
            // the mux LUT in SLR0 while source BRAM and dest FF were in SLR1,
            // forcing two SLR crossings on a single combinational path.
            wire [PAYLOAD_ITEM_WIDTH-1:0] bank_payload_item_j   [0:INGRESS_PROT_NUM];
            reg  [PAYLOAD_ITEM_WIDTH-1:0] bank_payload_item_j_r [0:INGRESS_PROT_NUM];
            genvar bidx;
            for (bidx = 0; bidx <= INGRESS_PROT_NUM; bidx = bidx + 1) begin : bank_slice
                assign bank_payload_item_j[bidx] =
                    payload_bram_bank_to_buffer_rd_data_pack[bidx][PAYLOAD_ITEM_WIDTH*(j+1)-1 -: PAYLOAD_ITEM_WIDTH];
                always @(posedge clk) bank_payload_item_j_r[bidx] <= bank_payload_item_j[bidx];
            end

            // Pipeline reg #2 on the bank-mux output. Combined with the
            // per-bank reg above, the payload path becomes 2 cycles:
            //   cycle N  : BRAM_Q -> bank_payload_item_j_r   (per-bank FF, in SLR1)
            //   cycle N+1: mux    -> payload_item_j_r        (after-mux FF)
            //   cycle N+2: adder  -> BRAM_wr
            // The state machine adds S_PIPE + S_PIPE2 (2-cycle bubble)
            // between S_WAIT_READ and S_COMPUTE_WRITE accordingly.
            // Local replica of bank-select index. Without this, the single
            // source FF in the buffer_controller has to drive 16x bank-mux
            // LUTs scattered across SLRs. The replica is per-iter and gets
            // placed beside its own mux, cutting select-pin route delay.
            (* keep = "true" *) reg [7:0] buffer_to_payload_bram_rd_idx_local;
            always @(posedge clk) buffer_to_payload_bram_rd_idx_local <= buffer_to_payload_bram_rd_idx;

            wire [PAYLOAD_ITEM_WIDTH-1:0] payload_item_j_comb;
            assign payload_item_j_comb = bank_payload_item_j_r[buffer_to_payload_bram_rd_idx_local];

            // Expose this iter's slice to the distributed payload_bram_rd_pack.
            // Each iter's slice uses its own per-bank regs + local mux LUT, so
            // the mux LUT lives near its own BRAMs (same SLR) rather than the
            // centralized mux which was forced to SLR boundary.
            assign payload_bram_rd_pack_distributed[(j+1)*PAYLOAD_ITEM_WIDTH-1 -: PAYLOAD_ITEM_WIDTH] = payload_item_j_comb;

            reg  [PAYLOAD_ITEM_WIDTH-1:0] payload_item_j_r;
            always @(posedge clk) payload_item_j_r <= payload_item_j_comb;

            wire [PAYLOAD_ITEM_WIDTH-1:0] payload_item_j;
            assign payload_item_j = payload_item_j_r;

            // Slice for the sloter write path
            wire [PAYLOAD_ITEM_WIDTH-1:0] sloter_item_j;
            assign sloter_item_j = sloter_to_aggregate_bram_arb_wr_vector_pack[PAYLOAD_ITEM_WIDTH*(j+1)-1 -: PAYLOAD_ITEM_WIDTH];

            wire [PAYLOAD_ITEM_WIDTH-1:0] moe_item_j;
            assign moe_item_j = moe_to_aggregate_bram_arb_wr_vector_pack[PAYLOAD_ITEM_WIDTH*(j+1)-1 -: PAYLOAD_ITEM_WIDTH];

            // chunk_a (aggregate_bram rd_data) is double-registered to match
            // the 2-cycle payload pipeline above, so chunk_a and chunk_b
            // arrive at the adder in the same cycle.
            reg [PAYLOAD_ITEM_WIDTH-1:0] aggregate_rd_data_j_r;
            reg [PAYLOAD_ITEM_WIDTH-1:0] aggregate_rd_data_j_r2;
            always @(posedge clk) begin
                aggregate_rd_data_j_r  <= aggregate_bram_rd_data_unpack[j];
                aggregate_rd_data_j_r2 <= aggregate_rd_data_j_r;
            end

            // Expose per-iter registered aggregate rd_data. 1 cycle later than
            // aggregate_bram_rd_data_pack direct wire. Used by skid mux to
            // deparser, with up_broadcast's valid/metadata delayed 1 cycle to
            // match phase.
            assign aggregate_bram_rd_data_pack_distributed[(j+1)*PAYLOAD_ITEM_WIDTH-1 -: PAYLOAD_ITEM_WIDTH] = aggregate_rd_data_j_r;

            wire [PAYLOAD_ITEM_WIDTH-1:0] calculated_sum_vector;
            genvar k;
            for (k = 0; k < CHUNKS_ITEM; k = k + 1) begin : add_chunks
                wire [ADD_CHUNK_WIDTH-1:0] chunk_a = aggregate_rd_data_j_r2[ADD_CHUNK_WIDTH*(k+1)-1 -: ADD_CHUNK_WIDTH];
                wire [ADD_CHUNK_WIDTH-1:0] chunk_b = payload_item_j[ADD_CHUNK_WIDTH*(k+1)-1 -: ADD_CHUNK_WIDTH];
                assign calculated_sum_vector[ADD_CHUNK_WIDTH*(k+1)-1 -: ADD_CHUNK_WIDTH] = chunk_a + chunk_b;
            end

            // Buffer-controller-side write data: sum (aggregation) or payload pass-through
            wire [PAYLOAD_ITEM_WIDTH-1:0] buffer_wr_data_local;
            assign buffer_wr_data_local = buffer_task_is_aggregate_to_up_broadcast
                                          ? calculated_sum_vector
                                          : payload_item_j;

            // Final BRAM write data: choose sloter or buffer based on which won the arbiter.
            // grant signals are 1-bit, so this mux has tiny fanout per BRAM.
            wire [PAYLOAD_ITEM_WIDTH-1:0] aggregate_bram_wr_data_local;
            assign aggregate_bram_wr_data_local = aggregate_bram_arb_to_sloter_wr_grant
                                                  ? sloter_item_j :
                                                  aggregate_bram_arb_to_moe_wr_grant
                                                  ? moe_item_j :
                                                  buffer_wr_data_local;

            payload_bram #(
                .USE_LUTRAM(0),
                .BUFFER_SLOTS(BUFFER_SLOTS),
                .DATA_WIDTH(PAYLOAD_ITEM_WIDTH),
                .ADDR_WIDTH(ADDR_WIDTH)
            ) aggregate_bram_init (
                .clk(clk),
                .wr_en(aggregate_bram_wr_en_pack[j]),
                .wr_addr(aggregate_bram_wr_addr_pack),
                .wr_data(aggregate_bram_wr_data_local),

                .rd_en(aggregate_bram_rd_en_pack[j]),
                .rd_addr(aggregate_bram_rd_addr_pack),
                .rd_data(aggregate_bram_rd_data_unpack[j])
            );

            assign aggregate_bram_rd_data_pack[(j+1)*PAYLOAD_ITEM_WIDTH-1 -: PAYLOAD_ITEM_WIDTH] = aggregate_bram_rd_data_unpack[j];
        end
    endgenerate


    // 2.4 --- retrans_checkor_arrival_updater ---
    retrans_checkor_arrival_updater #(
        .FAN_IN(FAN_IN),
        .BUFFER_SLOTS(BUFFER_SLOTS),
        .BUFFER_SLOTS_WIDTH(BUFFER_SLOTS_WIDTH),
        .FAN_IN_WIDTH(FAN_IN_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) allreduce_retrans_checkor_arrival_updater (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(typer_to_up_retrans_valid_r),
        .in_metadata(typer_metadata_to_retrans_r),

        .arrival_state_rd_addr(up_retrans_to_arrival_arb_rd_addr),
        .arrival_state_rd_en(up_retrans_to_arrival_arb_rd_en),
        .arrival_state_rd_grant(arrival_arb_to_up_retrans_rd_grant2),
        .arrival_state_bitmap_in(allreduce_arrival_state_rd_data),

        .arrival_state_wr_addr(up_retrans_to_arrival_arb_wr_addr),
        .arrival_state_wr_en(up_retrans_to_arrival_arb_wr_en),
        .arrival_state_wr_data(up_retrans_to_arrival_arb_wr_data),
        .arrival_state_wr_grant(arrival_arb_to_up_retrans_wr_grant3),

        .degree_state_in(allreduce_degree_state_rd_data),
        .degree_state_rd_en(up_retrans_to_degree_arb_rd_en),
        .degree_state_rd_addr(up_retrans_to_degree_arb_rd_addr),
        .degree_state_rd_grant(degree_arb_to_up_retrans_rd_grant1),

        .degree_state_wr_addr(up_retrans_to_degree_arb_wr_addr),
        .degree_state_wr_data(up_retrans_to_degree_arb_wr_data),
        .degree_state_wr_en(up_retrans_to_degree_arb_wr_en),
        .degree_state_wr_grant(degree_arb_to_up_retrans_wr_grant3),

        .to_buffer_metadata_out(up_retrans_to_buffer_metadata_out),
        .to_buffer_valid(up_retrans_to_buffer_valid),
        .to_buffer_ready(buffer_to_up_retrans_ready),
        .to_buffer_for_aggregate_payload_en(up_retrans_to_buffer_aggregate_payload_en),
        .to_buffer_need_aggregator_for_port_retrans(up_retrans_to_buffer_read_buffer_en),
    
        .to_up_broadcast_metadata_out(up_retrans_to_up_broadcast_metadata_out),
        .to_up_broadcast_valid(up_retrans_to_up_broadcast_valid),
        .to_up_broadcast_ready(up_broadcast_to_up_retrans_ready),
        .to_broadcast_for_FAN_retrans_check_en(up_retrans_to_up_broadcast_FAN_retrans_check_en),

        .in_ready(up_retrans_to_typer_in_ready),// ok

        // forwarding
        .real_to_buffer_need_aggregator_for_port_retrans(real_to_buffer_need_aggregator_for_port_retrans),
        .real_to_broadcast_for_FAN_retrans_check_en(real_to_broadcast_for_FAN_retrans_check_en)

        );

    // 2.5.x BUFFER_CONTROLLER INPUT ARBITER

    wire [METADATA_LEN-1:0]                                 merged_buffer_metadata_in;
    wire                                                    merged_buffer_aggregate_payload_en;
    wire                                                    merged_buffer_read_buffer_en;
    wire                                                    merged_buffer_copy_buffer_en;

    reg [METADATA_LEN-1:0]                                  store_merged_buffer_metadata_in;
    reg                                                     store_merged_buffer_aggregate_payload_en;
    reg                                                     store_merged_buffer_read_buffer_en;
    reg                                                     store_merged_buffer_copy_buffer_en;
    reg                                                     store_real_to_buffer_need_aggregator_for_port_retrans;

    // valid store
    reg                                                     from_up_retrans_to_buffer_valid;
    reg                                                     from_down_broadcast_to_buffer_valid;

    localparam BUFFER_IDLE = 2'b00;
    localparam BUFFER_WAIT = 2'b01; // 只需要两个状态
    localparam BUFFER_FOWARDING = 2'b10;

    reg [1:0]   arb_current_state, arb_next_state;
    wire                        forwarding_in_valid;
    wire [ADDR_WIDTH-1:0]       forwarding_in_addr;
    wire [DATA_WIDTH-1:0]       forwarding_in_data;

    localparam DOWN_BUFFER_REQ_BUS_WIDTH = METADATA_LEN + 1;
    localparam UP_BUFFER_REQ_BUS_WIDTH = METADATA_LEN + 3;
    localparam FORWARDING_CAPTURE_BUS_WIDTH = ADDR_WIDTH + DATA_WIDTH;

    wire [DOWN_BUFFER_REQ_BUS_WIDTH-1:0] down_buffer_req_bus;
    wire [DOWN_BUFFER_REQ_BUS_WIDTH-1:0] down_buffer_req_bus_holdfix;
    wire [METADATA_LEN-1:0] down_buffer_metadata_holdfix;
    wire down_buffer_copy_holdfix;

    wire [UP_BUFFER_REQ_BUS_WIDTH-1:0] up_buffer_req_bus;
    wire [UP_BUFFER_REQ_BUS_WIDTH-1:0] up_buffer_req_bus_holdfix;
    wire [METADATA_LEN-1:0] up_buffer_metadata_holdfix;
    wire up_buffer_aggregate_holdfix;
    wire up_buffer_read_holdfix;
    wire up_buffer_need_aggregator_holdfix;

    wire [FORWARDING_CAPTURE_BUS_WIDTH-1:0] forwarding_capture_bus;
    wire [FORWARDING_CAPTURE_BUS_WIDTH-1:0] forwarding_capture_bus_holdfix;
    wire [ADDR_WIDTH-1:0] forwarding_capture_addr_holdfix;
    wire [DATA_WIDTH-1:0] forwarding_capture_data_holdfix;
    wire forwarding_capture_valid_holdfix;

    reg                         store_forwarding_in_valid;
    reg [ADDR_WIDTH-1:0]        store_forwarding_in_addr;
    reg [DATA_WIDTH-1:0]        store_forwarding_in_data;

    wire forwarding_release_hit;
    wire buffer_wait_release;
    wire buffer_forward_release;
    wire buffer_release_to_controller;
//--------------------------------------------------------------------------------
    // 1. 定义 Arbiter 自身状态 (只有 IDLE 才能接客)
    wire arb_is_idle = (arb_current_state == BUFFER_IDLE);

    // 2. 定义下游是否准备好 (Controller Ready)
    wire downstream_ready = buffer_to_merged_in_ready;

    // 3. 定义 Ready 输出信号 (Strict Handshake)
    // 只有 Arbiter 空闲 且 下游也空闲时，才向上游发 Ready
    assign buffer_to_down_broadcast_ready = downstream_ready && arb_is_idle;
    // 上行重传通道还需要等待下行广播没有占用
    assign buffer_to_up_retrans_ready     = downstream_ready && arb_is_idle && (!down_broadcast_to_buffer_valid);

    // 4. 定义 Fire 信号 (用于内部逻辑触发)
    // Down Broadcast Fire
    wire down_fire = down_broadcast_to_buffer_valid && downstream_ready && arb_is_idle;
    
    // Up Retrans Fire (优先级低)
    wire up_fire   = up_retrans_to_buffer_valid && downstream_ready && arb_is_idle && (!down_broadcast_to_buffer_valid);
// ----------------------------------------------------------------------------


    // -------------------------------------------------------
    // Part 1: State Register Update (Sequential)
    // -------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arb_current_state <= BUFFER_IDLE;
        end
        else begin
            arb_current_state <= arb_next_state;
        end
    end

    // -------------------------------------------------------
    // Part 2: Next State Logic (Combinational)
    // -------------------------------------------------------

    // 定义不需要等待 Payload 的条件
    // Case 1: Down Broadcast Copy (不需要这里的 Payload，只需要 Copy BRAM)
    wire req_is_copy = down_broadcast_to_buffer_valid; 
    
    // Case 2: Up Retrans Read (不需要这里的 Payload，只需要 Read Aggregate BRAM)
    // 注：aggregate_payload_en 表示第一次到达，才需要写 Payload
    wire req_is_read_only = up_retrans_to_buffer_valid && 
                            up_retrans_to_buffer_read_buffer_en;

    // Case 3: First Arrival (只有这个必须利用 Parser 刚写进来的数据)
    wire req_is_first_arrival = up_retrans_to_buffer_valid && 
                                up_retrans_to_buffer_aggregate_payload_en;



    always @(*) begin
        arb_next_state = arb_current_state; // Default

        case (arb_current_state)
            BUFFER_IDLE: begin
                // 只要有请求，就准备进入等待状态
                // if (down_broadcast_to_buffer_valid || up_retrans_to_buffer_valid) begin
                //     arb_next_state = BUFFER_WAIT;
                // end

                // if (req_is_copy || req_is_first_arrival) begin
                //     arb_next_state = BUFFER_WAIT;
                // end
                
                // else if (req_is_read_only) begin
                //     arb_next_state = BUFFER_FOWARDING;
                // end

                if (down_fire) begin
                    // Down Broadcast 总是做 Copy，需要等待 Payload
                    arb_next_state = BUFFER_WAIT;
                end
                else if (up_fire) begin
                    // 根据请求类型跳转
                    if (up_retrans_to_buffer_aggregate_payload_en) begin
                        // First Arrival (Payload Write Mode) -> Wait
                        arb_next_state = BUFFER_WAIT;
                    end
                    else if (up_retrans_to_buffer_read_buffer_en) begin
                        // Retransmission (Read Only Mode) -> Forwarding
                        arb_next_state = BUFFER_FOWARDING;
                    end
                end 

                    
            end

            BUFFER_WAIT: begin
                // 等待 Payload 写完
                if (payload_write_done) begin
                    arb_next_state = BUFFER_IDLE;
                end
            end

            BUFFER_FOWARDING: begin
                // if (store_forwarding_in_valid && store_forwarding_in_data[FAN_IN] && store_forwarding_in_addr == store_merged_buffer_metadata_in[15:8]) begin
                if (forwarding_release_hit) begin
                    arb_next_state = BUFFER_IDLE;
                end

                else if (store_real_to_buffer_need_aggregator_for_port_retrans) begin
                    arb_next_state = BUFFER_IDLE;
                end

                else if (forwarding_in_valid == 0) begin
                    arb_next_state = BUFFER_IDLE;
                end
            end
            
            default: arb_next_state = BUFFER_IDLE;
        endcase
    end

    // -------------------------------------------------------
    // Part 3: Data Storage & Output Logic (Sequential)
    // -------------------------------------------------------
    // 关键：数据处理必须在时钟沿进行，这样才能生成寄存器

    assign down_buffer_req_bus = {
        down_broadcast_to_buffer_metadata_out,
        down_broadcast_to_buffer_copy_buffer_en
    };
    assign {
        down_buffer_metadata_holdfix,
        down_buffer_copy_holdfix
    } = down_buffer_req_bus_holdfix;

    assign up_buffer_req_bus = {
        up_retrans_to_buffer_metadata_out,
        up_retrans_to_buffer_aggregate_payload_en,
        up_retrans_to_buffer_read_buffer_en,
        real_to_buffer_need_aggregator_for_port_retrans
    };
    assign {
        up_buffer_metadata_holdfix,
        up_buffer_aggregate_holdfix,
        up_buffer_read_holdfix,
        up_buffer_need_aggregator_holdfix
    } = up_buffer_req_bus_holdfix;

    assign forwarding_capture_bus = {forwarding_in_addr, forwarding_in_data};
    assign {
        forwarding_capture_addr_holdfix,
        forwarding_capture_data_holdfix
    } = forwarding_capture_bus_holdfix;

    genvar down_buffer_req_holdfix_i;
    generate
        for (down_buffer_req_holdfix_i = 0; down_buffer_req_holdfix_i < DOWN_BUFFER_REQ_BUS_WIDTH; down_buffer_req_holdfix_i = down_buffer_req_holdfix_i + 1) begin : gen_down_buffer_req_holdfix
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) u_lut1_down_buffer_req_holdfix (
                .I0(down_buffer_req_bus[down_buffer_req_holdfix_i]),
                .O(down_buffer_req_bus_holdfix[down_buffer_req_holdfix_i])
            );
        end
    endgenerate

    genvar up_buffer_req_holdfix_i;
    generate
        for (up_buffer_req_holdfix_i = 0; up_buffer_req_holdfix_i < UP_BUFFER_REQ_BUS_WIDTH; up_buffer_req_holdfix_i = up_buffer_req_holdfix_i + 1) begin : gen_up_buffer_req_holdfix
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) u_lut1_up_buffer_req_holdfix (
                .I0(up_buffer_req_bus[up_buffer_req_holdfix_i]),
                .O(up_buffer_req_bus_holdfix[up_buffer_req_holdfix_i])
            );
        end
    endgenerate

    genvar forwarding_capture_holdfix_i;
    generate
        for (forwarding_capture_holdfix_i = 0; forwarding_capture_holdfix_i < FORWARDING_CAPTURE_BUS_WIDTH; forwarding_capture_holdfix_i = forwarding_capture_holdfix_i + 1) begin : gen_forwarding_capture_holdfix
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) u_lut1_forwarding_capture_holdfix (
                .I0(forwarding_capture_bus[forwarding_capture_holdfix_i]),
                .O(forwarding_capture_bus_holdfix[forwarding_capture_holdfix_i])
            );
        end
    endgenerate

    (* DONT_TOUCH = "TRUE" *) LUT1 #(
        .INIT(2'b10)
    ) u_lut1_forwarding_capture_valid_holdfix (
        .I0(forwarding_in_valid),
        .O(forwarding_capture_valid_holdfix)
    );

    assign forwarding_release_hit =
        forwarding_in_valid &&
        forwarding_in_data[FAN_IN] &&
        (forwarding_in_addr == store_merged_buffer_metadata_in[15:8]);
    assign buffer_wait_release = (arb_current_state == BUFFER_WAIT) && payload_write_done;
    assign buffer_forward_release =
        (arb_current_state == BUFFER_FOWARDING) &&
        (forwarding_release_hit || store_real_to_buffer_need_aggregator_for_port_retrans);
    assign buffer_release_to_controller = buffer_wait_release || buffer_forward_release;

    assign merged_buffer_metadata_in = store_merged_buffer_metadata_in;
    assign merged_buffer_aggregate_payload_en = buffer_release_to_controller && store_merged_buffer_aggregate_payload_en;
    assign merged_buffer_read_buffer_en = buffer_release_to_controller && store_merged_buffer_read_buffer_en;
    assign merged_buffer_copy_buffer_en = buffer_release_to_controller && store_merged_buffer_copy_buffer_en;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset Outputs
            // Reset Internal Storage
            store_merged_buffer_aggregate_payload_en <= 0;
            store_merged_buffer_copy_buffer_en <= 0;
            store_merged_buffer_read_buffer_en <= 0;
            store_merged_buffer_metadata_in <= 0;

            // forwarding
            store_forwarding_in_addr <= 0;
            store_forwarding_in_data <= 0;
            store_forwarding_in_valid <= 0;

            store_real_to_buffer_need_aggregator_for_port_retrans <= 0;
        end
        else begin
            // 默认输出为 0 (产生脉冲)
            // metadata 可以保持，也可以清零，看需求


            // forwarding
            if (forwarding_in_valid) begin
                store_forwarding_in_addr <= forwarding_capture_addr_holdfix;
                store_forwarding_in_data <= forwarding_capture_data_holdfix;
                store_forwarding_in_valid <= forwarding_capture_valid_holdfix;    
            end

            if (buffer_release_to_controller) begin
                store_merged_buffer_metadata_in <= 0;
                store_merged_buffer_aggregate_payload_en <= 0;
                store_merged_buffer_read_buffer_en <= 0;
                store_merged_buffer_copy_buffer_en <= 0;
                store_real_to_buffer_need_aggregator_for_port_retrans <= 0;
            end
            
            case (arb_current_state)
                BUFFER_IDLE: begin
                    // 在 IDLE 状态检测到 Valid，立即锁存数据 (Capture)
                    // 优先级：DownBroadcast > UpRetrans
                    // if (down_broadcast_to_buffer_valid) begin
                    //     store_merged_buffer_metadata_in <= down_broadcast_to_buffer_metadata_out;
                    //     store_merged_buffer_copy_buffer_en <= down_broadcast_to_buffer_copy_buffer_en;
                    //     // 清除其他标志
                    //     store_merged_buffer_aggregate_payload_en <= 0;
                    //     store_merged_buffer_read_buffer_en <= 0;
                    // end
                    // else if (up_retrans_to_buffer_valid) begin
                    //     store_merged_buffer_metadata_in <= up_retrans_to_buffer_metadata_out;
                    //     store_merged_buffer_aggregate_payload_en <= up_retrans_to_buffer_aggregate_payload_en;
                    //     store_merged_buffer_read_buffer_en <= up_retrans_to_buffer_read_buffer_en;
                    //     // 清除其他标志
                    //     store_merged_buffer_copy_buffer_en <= 0;
                    //     store_real_to_buffer_need_aggregator_for_port_retrans <= real_to_buffer_need_aggregator_for_port_retrans;
                    if (down_fire) begin
                        store_merged_buffer_metadata_in <= down_buffer_metadata_holdfix;
                        store_merged_buffer_copy_buffer_en <= down_buffer_copy_holdfix;
                        // 清除其他
                        store_merged_buffer_aggregate_payload_en <= 0;
                        store_merged_buffer_read_buffer_en <= 0;
                        store_real_to_buffer_need_aggregator_for_port_retrans <= 0;
                    end
                    else if (up_fire) begin
                        store_merged_buffer_metadata_in <= up_buffer_metadata_holdfix;
                        store_merged_buffer_aggregate_payload_en <= up_buffer_aggregate_holdfix;
                        store_merged_buffer_read_buffer_en <= up_buffer_read_holdfix;
                        
                        store_real_to_buffer_need_aggregator_for_port_retrans <= up_buffer_need_aggregator_holdfix;
                        // 清除其他
                        store_merged_buffer_copy_buffer_en <= 0;
                    end    
                end

                BUFFER_WAIT: begin
                    // 如果 Payload 写完了，把锁存的数据输出给 Buffer Controller
                    if (payload_write_done) begin
                        // if (store_forwarding_in_valid && store_forwarding_in_data[FAN_IN] && store_forwarding_in_addr == store_merged_buffer_metadata_in[15:8]) begin
                        //     merged_buffer_copy_buffer_en <= store_merged_buffer_copy_buffer_en;
                        //     store_forwarding_in_addr <= 0;
                        //     store_forwarding_in_data <= 0;
                        //     store_forwarding_in_valid <= 0;
                        // end
                        
                    end
                end

                BUFFER_FOWARDING: begin
                    // if (store_forwarding_in_valid && store_forwarding_in_data[FAN_IN] && store_forwarding_in_addr == store_merged_buffer_metadata_in[15:8]) begin
                    if (buffer_forward_release) begin
                    end
                end
            endcase
        end
    end


    // always @(posedge clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         merged_buffer_aggregate_payload_en <= 0;
    //         merged_buffer_copy_buffer_en <= 0;
    //         merged_buffer_read_buffer_en <= 0;
    //         merged_buffer_metadata_in <= 0;

    //         store_merged_buffer_aggregate_payload_en <= 0;
    //         store_merged_buffer_copy_buffer_en <= 0;
    //         store_merged_buffer_read_buffer_en <= 0;
    //         store_merged_buffer_metadata_in <= 0;
    //     end

    //     else begin
    //         case (arb_next_state)

    //             BUFFER_READ: begin
    //                 if (from_down_broadcast_to_buffer_valid) begin
    //                     store_merged_buffer_metadata_in <= down_broadcast_to_buffer_metadata_out;
    //                     store_merged_buffer_copy_buffer_en <= down_broadcast_to_buffer_copy_buffer_en;
    //                 end
                
    //                 else if (from_up_retrans_to_buffer_valid) begin
    //                     store_merged_buffer_metadata_in <= up_retrans_to_buffer_metadata_out;
    //                     store_merged_buffer_aggregate_payload_en <= up_retrans_to_buffer_aggregate_payload_en;
    //                     store_merged_buffer_read_buffer_en <= up_retrans_to_buffer_read_buffer_en; 
    //                 end
    //             end


    //             BUFFER_WAIT: begin
    //                 if (payload_write_done) begin
    //                     merged_buffer_aggregate_payload_en <= store_merged_buffer_aggregate_payload_en;
    //                     merged_buffer_copy_buffer_en <= store_merged_buffer_copy_buffer_en;
    //                     merged_buffer_read_buffer_en <= store_merged_buffer_read_buffer_en;
    //                     merged_buffer_metadata_in <= store_merged_buffer_metadata_in;
    //                 end
    //             end
    //         endcase
    //     end
    // end


    // always @(*) begin
    //     merged_buffer_aggregate_payload_en = 0;
    //     merged_buffer_copy_buffer_en = 0;
    //     merged_buffer_read_buffer_en = 0;
    //     merged_buffer_metadata_in = 0;

    //     if (down_broadcast_to_buffer_valid) begin
    //         merged_buffer_metadata_in = down_broadcast_to_buffer_metadata_out;
    //         merged_buffer_copy_buffer_en = down_broadcast_to_buffer_copy_buffer_en;
    //     end

    //     else if (up_retrans_to_buffer_valid) begin
    //         merged_buffer_metadata_in = up_retrans_to_buffer_metadata_out;
    //         merged_buffer_aggregate_payload_en = up_retrans_to_buffer_aggregate_payload_en;
    //         merged_buffer_read_buffer_en = up_retrans_to_buffer_read_buffer_en; 
    //     end
            
    // end

    // Ready 信号分发逻辑

    // DownBroadcast (高优先级): 只要 Buffer 准备好，他就可以发
    // assign buffer_to_down_broadcast_ready = buffer_to_merged_in_ready;

    // Retrans (低优先级): 只要 Buffer 准备好，且 down_broadcast 没有占用通道时，它就可以发
    // assign buffer_to_up_retrans_ready = buffer_to_merged_in_ready && (!down_broadcast_to_buffer_valid);


    // 2.5 --- aggregate_buffer_controller ---
    aggregate_buffer_controller #(
        .PAYLOAD_ITEM_NUM(PAYLOAD_ITEM_NUM),
        .PAYLOAD_ITEM_WIDTH(PAYLOAD_ITEM_WIDTH),
        .PAYLOAD_ITEM_COUNT_WIDTH(PAYLOAD_ITEM_COUNT_WIDTH),
        .SLOTS_WIDTH(ADDR_WIDTH),
        .BUFFER_SLOTS(BUFFER_SLOTS),
        .METADATA_LEN(METADATA_LEN)      
    )allreduce_aggregate_buffer_controller (
        .clk(clk),
        .rst_n(rst_n),
        .aggregate_payload_en(merged_buffer_aggregate_payload_en),
        .for_port_retrans_read_buffer_en(merged_buffer_read_buffer_en),
        .for_down_broadcast_copy_buffer_en(merged_buffer_copy_buffer_en),
        .metadata_in(merged_buffer_metadata_in),

        .payload_bram_rd_vector_pack(payload_bram_rd_pack),
        .payload_bram_rd_idx(buffer_to_payload_bram_rd_idx),
        .payload_bram_rd_addr(buffer_to_payload_bram_rd_addr),
        .payload_bram_rd_en_pack(buffer_to_payload_bram_rd_en_pack),

        .aggregate_bram_rd_grant(aggregate_bram_arb_to_buffer_rd_grant),
        .aggregate_bram_rd_vector_pack(aggregate_bram_rd_data_pack),
        .aggregate_bram_rd_addr(buffer_to_aggregate_bram_arb_rd_addr),
        .aggregate_bram_rd_en_pack(buffer_to_aggregate_bram_arb_rd_en_pack),

        .updated_aggregate_bram_wr_en_pack(buffer_to_aggregate_bram_arb_wr_en_pack),
        .updated_aggregate_bram_wr_addr(buffer_to_aggregate_bram_arb_wr_addr),
        .updated_aggregate_bram_wr_grant(aggregate_bram_arb_to_buffer_wr_grant),

        .task_is_aggregate_to_up_broadcast_out(buffer_task_is_aggregate_to_up_broadcast),

        .to_deparser_metadata_out(buffer_to_deparser_metadata_out),
        .to_deparser_valid(buffer_to_deparser_valid),
        .to_deparser_up_port_retrans_ok_en(buffer_to_deparser_up_port_retrans_ok_en),
        .to_deparser_down_down_broadcast_ok_en(buffer_to_deparser_down_down_broadcast_ok_en),
        .to_deparser_ready(deparser_to_buffer_ready),

        .to_up_broadcast_metadata_out(buffer_to_up_broadcast_metadata_out),
        .to_up_broadcast_valid(buffer_to_up_broadcast_valid),
        .to_up_broadcast_check_en(buffer_to_up_broadcast_check_en),
        .to_up_broadcast_ready(up_broadcast_to_buffer_ready),

        .in_ready(buffer_to_merged_in_ready)     // ok
    );

    // 2.6-x --- up_broadcast input arbiter
    reg [METADATA_LEN-1:0]                      merged_up_broadcast_metadata_in;
    // reg                                         merged_up_broadcast_valid;
    reg                                         merged_up_broadcast_FAN_retrans_en;
    reg                                         merged_up_broadcast_check_en;

    wire                                        up_broadcast_to_merged_in_ready;

    always @(*) begin
        merged_up_broadcast_metadata_in = 0;
        merged_up_broadcast_FAN_retrans_en = 0;
        merged_up_broadcast_check_en = 0;

        if (up_retrans_to_up_broadcast_FAN_retrans_check_en) begin
            merged_up_broadcast_FAN_retrans_en = up_retrans_to_up_broadcast_FAN_retrans_check_en;
            merged_up_broadcast_metadata_in = up_retrans_to_up_broadcast_metadata_out;
        end

        else if (buffer_to_up_broadcast_check_en) begin
            merged_up_broadcast_check_en = buffer_to_up_broadcast_check_en;
            merged_up_broadcast_metadata_in = buffer_to_up_broadcast_metadata_out;
        end
    end

    assign up_broadcast_to_up_retrans_ready = up_broadcast_to_merged_in_ready;
    assign up_broadcast_to_buffer_ready = up_broadcast_to_merged_in_ready && (!up_retrans_to_up_broadcast_valid);

    // 2.6 --- up_broadcast_checkor_arrival_updater ---
    up_broadcast_checkor_arrival_updater #(
        .FAN_IN(FAN_IN),
        .BUFFER_SLOTS(BUFFER_SLOTS),
        .BUFFER_SLOTS_WIDTH(BUFFER_SLOTS_WIDTH),
        .FAN_IN_WIDTH(FAN_IN_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .PAYLOAD_ITEM_WIDTH(PAYLOAD_ITEM_WIDTH),
        .PAYLOAD_ITEM_NUM(PAYLOAD_ITEM_NUM),
        .METADATA_LEN(METADATA_LEN)
    ) allreduce_up_broadcast (
        .clk(clk),
        .rst_n(rst_n),
        .in_metadata(merged_up_broadcast_metadata_in),
        .FAN_retrans_check_en(merged_up_broadcast_FAN_retrans_en),
        .buffer_to_up_broadcast_check_en(merged_up_broadcast_check_en),

        .arrival_state_rd_en(up_broadcast_to_arrival_arb_rd_en),                    // arrival_rd
        .arrival_state_rd_addr(up_broadcast_to_arrival_arb_rd_addr),
        .arrival_state_rd_grant(arrival_arb_to_up_broadcast_rd_grant1), 
        .arrival_state_bitmap_in(allreduce_arrival_state_rd_data),

        .arrival_state_wr_en(up_broadcast_to_arrival_arb_wr_en),
        .arrival_state_wr_addr(up_broadcast_to_arrival_arb_wr_addr),                // arrival_wr
        .arrival_state_wr_data(up_broadcast_to_arrival_arb_wr_data),
        .arrival_state_wr_grant(arrival_arb_to_up_broadcast_wr_grant2),

        .degree_state_rd_en(up_broadcast_to_degree_arb_rd_en),                      // degree_rd
        .degree_state_rd_addr(up_broadcast_to_degree_arb_rd_addr),
        .degree_state_rd_grant(degree_arb_to_up_broadcast_rd_grant0),
        .degree_state_in(allreduce_degree_state_rd_data),

        .aggregate_bram_rd_grant(aggregate_bram_arb_to_up_broadcast_rd_grant),      // aggregate_bram_rd
        .aggregate_bram_rd_vector_pack(aggregate_bram_rd_data_pack),                // rd_data
        .aggregate_bram_rd_addr(up_broadcast_to_aggregate_bram_arb_rd_addr),
        .aggregate_bram_rd_en_pack(up_broadcast_to_aggregate_bram_arb_rd_en_pack),

        .to_new_sloter_valid(up_broadcast_to_sloter_valid),
        .to_new_sloter_ready(sloter_to_up_broadcast_ready),
        .new_slot_en(up_broadcast_to_sloter_new_slot_en),
        .to_new_sloter_metadata_out(up_broadcast_to_sloter_metadata_out),

        .to_deparser_valid(up_broadcast_to_deparser_valid),
        .to_deparser_ready(deparser_to_up_broadcast_ready),
        .need_aggregator_FAN_retrans_en(up_broadcast_to_deparser_FAN_retrans_en),
        .need_aggregator_FAN_trans_en(up_broadcast_to_deparser_FAN_trans_en),
        .need_aggregator_down_broadcast_en(up_broadcast_to_deparser_down_broadcast_en),
        .to_deparser_metadata_out(up_broadcast_to_deparser_metadata_out),

        .aggregate_bram_rd_vector_pack_out(up_broadcast_to_deparser_aggregate_bram_out),

        .in_ready(up_broadcast_to_merged_in_ready),

        // forwading
        .forwarding_valid(forwarding_in_valid),
        .forwarding_addr(forwarding_in_addr),
        .forwarding_data(forwarding_in_data),

        .last_forwarding_valid(store_forwarding_in_valid),
        .last_forwarding_addr(store_forwarding_in_addr),
        .last_forwarding_data(store_forwarding_in_data),

        .real_FAN_retrans_check_en(real_to_broadcast_for_FAN_retrans_check_en)
    );

    // 2.7 --- new_slot_creater ---
    new_slot_creater #(
        .WINDOWSIZE(WINDOWSIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .PAYLOAD_ITEM_WIDTH(PAYLOAD_ITEM_WIDTH),
        .PAYLOAD_ITEM_NUM(PAYLOAD_ITEM_NUM),
        .SLOTS_WIDTH(ADDR_WIDTH)
    ) allreduce_sloter (
        .clk(clk),
        .rst_n(rst_n),
        .new_slot_en(sloter_new_slot_en),
        .in_valid(1'b1),
        .in_metadata(sloter_metadata_in),
        .new_slot_addr_override(sloter_addr_override),
        .new_slot_addr_override_en(sloter_addr_override_en),
        // .in_valid(up_broadcast_output_valid),

        .new_arrival_state_wr_en(sloter_to_arrival_arb_wr_en),
        .new_arrival_state_wr_addr(sloter_to_arrival_arb_wr_addr),
        .new_arrival_state_wr_data(sloter_to_arrival_arb_wr_data),
        .new_arrival_state_wr_grant(arrival_arb_to_sloter_wr_grant1),
        
        .new_degree_wr_en(sloter_to_degree_arb_wr_en),
        .new_degree_wr_addr(sloter_to_degree_arb_wr_addr),
        .new_degree_wr_data(sloter_to_degree_arb_wr_data),
        .new_degree_wr_grant(degree_arb_to_sloter_wr_grant1),

        .new_aggregate_bram_wr_grant(aggregate_bram_arb_to_sloter_wr_grant),
        .new_aggregate_bram_wr_vector_pack(sloter_to_aggregate_bram_arb_wr_vector_pack),
        .new_aggregate_bram_wr_addr(sloter_to_aggregate_bram_arb_wr_addr),
        .new_aggregate_bram_wr_en_pack(sloter_to_aggregate_bram_arb_wr_en_pack),

        .in_ready(sloter_to_up_broadcast_ready),
        .out_ready(sloter_out_ready)
    );

    // 2.8 --- down_broadcast_checkor_arrival_updater ---
    down_broadcast_checkor_arrival_updater #(
        .PAYLOAD_ITEM_NUM(PAYLOAD_ITEM_NUM),
        .PAYLOAD_ITEM_WIDTH(PAYLOAD_ITEM_WIDTH),
        .FAN_IN(FAN_IN),
        .BUFFER_SLOTS(BUFFER_SLOTS),
        .BUFFER_SLOTS_WIDTH(BUFFER_SLOTS_WIDTH),
        .FAN_IN_WIDTH(FAN_IN_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) allreduce_down_broadcast_checkor_arrival_updater (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(typer_to_down_broadcast_valid_r),
        .in_metadata(typer_metadata_to_down_broadcast_r),

        .arrival_state_rd_en(down_broadcast_to_arrival_arb_rd_en),
        .arrival_state_rd_addr(down_broadcast_to_arrival_arb_rd_addr),
        .arrival_state_bitmap_in(allreduce_arrival_state_rd_data),
        .arrival_state_rd_grant(arrival_arb_to_down_broadcast_rd_grant0),

        .arrival_state_wr_addr(down_broadcast_to_arrival_arb_wr_addr),
        .arrival_state_wr_en(down_broadcast_to_arrival_arb_wr_en),
        .arrival_state_wr_data(down_broadcast_to_arrival_arb_wr_data),
        .arrival_state_wr_grant(arrival_arb_to_down_broadcast_wr_grant0),

        .to_buffer_valid(down_broadcast_to_buffer_valid),
        .to_buffer_ready(buffer_to_down_broadcast_ready),
        .copy_buffer_en(down_broadcast_to_buffer_copy_buffer_en),
        .to_buffer_metadata_out(down_broadcast_to_buffer_metadata_out),

        // .to_deparser_valid(down_broadcast_to_deparser_valid),
        // .to_deparser_ready(deparser_to_down_broadcast_ready),
        // .down_broadcast_en(down_broadcast_to_deparser_down_broadcast_en),
        // .to_deparser_metadata_out(down_broadcast_to_deparser_metadata_out),

        .in_ready(down_broadcast_to_typer_in_ready)    // ok
    );


    // 2.9 --- aggregate_bram_rd_arbiter ---
    payload_read_arbiter #(
        .ADDR_WIDTH(ADDR_WIDTH),    
        .PAYLOAD_ITEM_NUM(PAYLOAD_ITEM_NUM)
    ) aggregate_bram_rd_arb (
        .clk(clk),
        .rst_n(rst_n),

        .req0_rd_en(up_broadcast_to_aggregate_bram_arb_rd_en_pack),
        .req0_rd_addr(up_broadcast_to_aggregate_bram_arb_rd_addr),
        .grant0(aggregate_bram_arb_to_up_broadcast_rd_grant),

        .req1_rd_en(buffer_to_aggregate_bram_arb_rd_en_pack),
        .req1_rd_addr(buffer_to_aggregate_bram_arb_rd_addr),
        .grant1(aggregate_bram_arb_to_buffer_rd_grant),

        .req2_rd_en(moe_to_aggregate_bram_arb_rd_en_pack),
        .req2_rd_addr(moe_to_aggregate_bram_arb_rd_addr),
        .grant2(aggregate_bram_arb_to_moe_rd_grant),

        .payload_rd_en(aggregate_bram_rd_en_pack),
        .payload_rd_addr(aggregate_bram_rd_addr_pack)
    );

    // 2.10 --- aggregate_bram_wr_arbiter ---
    payload_wr_arbiter #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .PAYLOAD_ITEM_NUM(PAYLOAD_ITEM_NUM),
        .PAYLOAD_ITEM_WIDTH(PAYLOAD_ITEM_WIDTH)
    ) aggregate_bram_wr_arb (
        .clk(clk),
        .rst_n(rst_n),
        
        .req0_wr_en(sloter_to_aggregate_bram_arb_wr_en_pack),
        .req0_wr_addr(sloter_to_aggregate_bram_arb_wr_addr),
        .req0_wr_data_pack(sloter_to_aggregate_bram_arb_wr_vector_pack),
        .grant0(aggregate_bram_arb_to_sloter_wr_grant),
        
        .req1_wr_en(buffer_to_aggregate_bram_arb_wr_en_pack),
        .req1_wr_addr(buffer_to_aggregate_bram_arb_wr_addr),
        .req1_wr_data_pack(buffer_to_aggregate_bram_arb_wr_vector_pack),
        .grant1(aggregate_bram_arb_to_buffer_wr_grant),

        .req2_wr_en(moe_to_aggregate_bram_arb_wr_en_pack),
        .req2_wr_addr(moe_to_aggregate_bram_arb_wr_addr),
        .req2_wr_data_pack(moe_to_aggregate_bram_arb_wr_vector_pack),
        .grant2(aggregate_bram_arb_to_moe_wr_grant),

        .payload_wr_data_pack(aggregate_bram_wr_data_pack),
        .payload_wr_addr(aggregate_bram_wr_addr_pack),
        .payload_wr_en(aggregate_bram_wr_en_pack)
    );
    

    // 2.11 --- arrival_state_rd_arbiter ---
    bram_read_arbiter #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) arrival_state_rd_arb (
        .clk(clk),
        .rst_n(rst_n),

        .req0_rd_en(down_broadcast_to_arrival_arb_rd_en),
        .req0_rd_addr(down_broadcast_to_arrival_arb_rd_addr),
        .grant0(arrival_arb_to_down_broadcast_rd_grant0),

        .req1_rd_en(up_broadcast_to_arrival_arb_rd_en),
        .req1_rd_addr(up_broadcast_to_arrival_arb_rd_addr),
        .grant1(arrival_arb_to_up_broadcast_rd_grant1),

        .req2_rd_en(up_retrans_to_arrival_arb_rd_en),
        .req2_rd_addr(up_retrans_to_arrival_arb_rd_addr),
        .grant2(arrival_arb_to_up_retrans_rd_grant2),

        .req3_rd_en(moe_to_arrival_arb_rd_en),
        .req3_rd_addr(moe_to_arrival_arb_rd_addr),
        .grant3(arrival_arb_to_moe_rd_grant3),

        .bram_rd_en(allreduce_arrival_state_rd_en),
        .bram_rd_addr(allreduce_arrival_state_rd_addr)
    );

    // 2.12 --- arrival_state_wr_arbiter ---
    bram_write_arbiter #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)  
    ) arrival_state_wr_arb (
        .clk(clk),
        .rst_n(rst_n),

        .req0_wr_en(down_broadcast_to_arrival_arb_wr_en),
        .req0_wr_addr(down_broadcast_to_arrival_arb_wr_addr),
        .req0_wr_data(down_broadcast_to_arrival_arb_wr_data),
        .grant0(arrival_arb_to_down_broadcast_wr_grant0),

        .req1_wr_en(sloter_to_arrival_arb_wr_en),
        .req1_wr_addr(sloter_to_arrival_arb_wr_addr),
        .req1_wr_data(sloter_to_arrival_arb_wr_data),
        .grant1(arrival_arb_to_sloter_wr_grant1),

        .req2_wr_en(up_broadcast_to_arrival_arb_wr_en),
        .req2_wr_addr(up_broadcast_to_arrival_arb_wr_addr),
        .req2_wr_data(up_broadcast_to_arrival_arb_wr_data),
        .grant2(arrival_arb_to_up_broadcast_wr_grant2),

        .req3_wr_en(up_retrans_to_arrival_arb_wr_en),
        .req3_wr_addr(up_retrans_to_arrival_arb_wr_addr),
        .req3_wr_data(up_retrans_to_arrival_arb_wr_data),
        .grant3(arrival_arb_to_up_retrans_wr_grant3),

        .req4_wr_en(moe_to_arrival_arb_wr_en),
        .req4_wr_addr(moe_to_arrival_arb_wr_addr),
        .req4_wr_data(moe_to_arrival_arb_wr_data),
        .grant4(arrival_arb_to_moe_wr_grant4),

        .bram_wr_en(allreduce_arrival_state_wr_en),
        .bram_wr_addr(allreduce_arrival_state_wr_addr),
        .bram_wr_data(allreduce_arrival_state_wr_data)
    );

    // 2.13 --- arrival_state_bram ---
    arrival_state_mem #(
        .BUFFER_SLOTS(BUFFER_SLOTS),
        // .DATA_WIDTH(INGRESS_PROT_NUM),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) allreduce_arrival_state_bram (
        .clk(clk),
        .wr_en(allreduce_arrival_state_wr_en),
        .wr_addr(allreduce_arrival_state_wr_addr),
        .wr_data(allreduce_arrival_state_wr_data),
        .rd_en(allreduce_arrival_state_rd_en),
        .rd_addr(allreduce_arrival_state_rd_addr),
        .rd_data(allreduce_arrival_state_rd_data)
    );
    

    // 2.14 --- degree_state_rd_arbiter ---
    bram_read_arbiter #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) degree_state_rd_arb (
        .clk(clk),
        .rst_n(rst_n),

        // .req0_rd_en(down_broadcast_to_degree_arb_rd_en),
        // .req0_rd_addr(down_broadcast_to_degree_arb_rd_addr),
        // .grant0(degree_arb_to_down_broadcast_rd_grant0),

        // .req0_rd_en(0),
        // .req0_rd_addr(0),
        // .grant0(degree_arb_to_down_broadcast_rd_grant0),

        .req0_rd_en(up_broadcast_to_degree_arb_rd_en),
        .req0_rd_addr(up_broadcast_to_degree_arb_rd_addr),
        .grant0(degree_arb_to_up_broadcast_rd_grant0),

        .req1_rd_en(up_retrans_to_degree_arb_rd_en),            
        .req1_rd_addr(up_retrans_to_degree_arb_rd_addr),
        .grant1(degree_arb_to_up_retrans_rd_grant1),

        .req2_rd_en(1'b0),
        .req2_rd_addr({ADDR_WIDTH{1'b0}}),
        .grant2(),

        .req3_rd_en(1'b0),
        .req3_rd_addr({ADDR_WIDTH{1'b0}}),
        .grant3(),

        .bram_rd_en(allreduce_degree_state_rd_en),
        .bram_rd_addr(allreduce_degree_state_rd_addr)
    );

    // 2.15 --- degree_state_wr_arbiter ---
    bram_write_arbiter #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)  
    ) degree_state_wr_arb (
        .clk(clk),
        .rst_n(rst_n),

        .req0_wr_en(1'b0),
        .req0_wr_addr({ADDR_WIDTH{1'b0}}),
        .req0_wr_data({DATA_WIDTH{1'b0}}),
        .grant0(),

        .req1_wr_en(sloter_to_degree_arb_wr_en),
        .req1_wr_addr(sloter_to_degree_arb_wr_addr),
        .req1_wr_data(sloter_to_degree_arb_wr_data),
        .grant1(degree_arb_to_sloter_wr_grant1),

        .req2_wr_en(1'b0),
        .req2_wr_addr({ADDR_WIDTH{1'b0}}),
        .req2_wr_data({DATA_WIDTH{1'b0}}),
        .grant2(),

        .req3_wr_en(up_retrans_to_degree_arb_wr_en),
        .req3_wr_addr(up_retrans_to_degree_arb_wr_addr),
        .req3_wr_data(up_retrans_to_degree_arb_wr_data),
        .grant3(degree_arb_to_up_retrans_wr_grant3),

        .req4_wr_en(1'b0),
        .req4_wr_addr({ADDR_WIDTH{1'b0}}),
        .req4_wr_data({DATA_WIDTH{1'b0}}),
        .grant4(),

        .bram_wr_en(allreduce_degree_state_wr_en),
        .bram_wr_addr(allreduce_degree_state_wr_addr),
        .bram_wr_data(allreduce_degree_state_wr_data)
    );

    // 2.16 --- degree_state_bram ---
    degree_bram #(
        .BUFFER_SLOTS(BUFFER_SLOTS),
        .BUFFER_SLOTS_WIDTH(BUFFER_SLOTS_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .FAN_IN(FAN_IN),
        // .DATA_WIDTH(FAN_IN_WIDTH+1)
        .DATA_WIDTH(DATA_WIDTH)
    ) allreduce_degree_bram (
        .clk(clk),
        .wr_en(allreduce_degree_state_wr_en),
        .wr_addr(allreduce_degree_state_wr_addr),
        .wr_data(allreduce_degree_state_wr_data),
        .rd_en(allreduce_degree_state_rd_en),
        .rd_addr(allreduce_degree_state_rd_addr),
        .rd_data(allreduce_degree_state_rd_data)
    );


    // =============================================================================
    // SECTION 3: OUTPUT ARBITER (TO DEPARSER)
    // =============================================================================
    // 优先级策略: Buffer > UpBroadcast > DownBroadcast > Typer(Ack)

    // wire req_buffer = buffer_to_deparser_valid;                            
    wire req_ack_up = typer_ack_up_en ;
    wire req_ack_down = typer_ack_down_en;
    wire req_up_port_retrans = buffer_to_deparser_up_port_retrans_ok_en;
    wire req_up_root_down_broadcast = up_broadcast_to_deparser_down_broadcast_en;
    wire req_up_noroot_FAN_retrans = up_broadcast_to_deparser_FAN_retrans_en;
    wire req_up_noroot_FAN_trans = up_broadcast_to_deparser_FAN_trans_en;
    // wire req_down_down_broadcast = down_broadcast_to_deparser_down_broadcast_en;
    wire req_down_down_broadcast = buffer_to_deparser_down_down_broadcast_ok_en;

    // wire grant_ack_down = req_ack_down;
    // wire grant_ack_up = !req_ack_down && req_ack_up;

    // // down_broadcast
    // wire grant_down_down_broadcast = !req_ack_down && !req_ack_up && req_down_down_broadcast;
    // // buffer
    // wire grant_up_port_retrans = !req_ack_down && !req_ack_up && !req_down_down_broadcast && req_up_port_retrans;
    // // up_broadcast
    // wire grant_up_root_down_broadcast = !req_ack_down && !req_ack_up && !req_down_down_broadcast && !req_up_port_retrans && req_up_root_down_broadcast;

    // wire grant_up_noroot_FAN_retrans = !req_ack_down && !req_ack_up && !req_down_down_broadcast && !req_up_port_retrans && !req_up_root_down_broadcast 
    //     && req_up_noroot_FAN_retrans;
    
    // wire grant_up_noroot_FAN_trans = !req_ack_down && !req_ack_up && !req_down_down_broadcast && !req_up_port_retrans && !req_up_root_down_broadcast 
    //      && !req_up_noroot_FAN_retrans && req_up_noroot_FAN_trans;

    wire grant_typer = (req_ack_up || req_ack_down);
    // wire grant_down_broadcast = !(req_ack_up || req_ack_down) && req_down_down_broadcast;
    wire grant_buffer = !(req_ack_up || req_ack_down) && (req_down_down_broadcast || req_up_port_retrans);

    wire grant_up_broadcast = !(req_ack_up || req_ack_down) && !req_down_down_broadcast && !req_up_port_retrans 
        && (req_up_root_down_broadcast || req_up_noroot_FAN_retrans || req_up_noroot_FAN_trans);

    assign deparser_to_typer_ready          = pipe_can_accept && grant_typer;
    assign deparser_to_buffer_ready         = pipe_can_accept && grant_buffer;
    // assign deparser_to_down_broadcast_ready = deparser_in_ready && grant_down_broadcast;
    assign deparser_to_up_broadcast_ready   = pipe_can_accept && grant_up_broadcast;

    // =============================================================================
    // SKID BUFFER on aggregator -> deparser interface
    //
    // Cuts the long BRAM_Q -> cross-SLR -> deparser payload input path:
    //   before:  mux_comb -> [cross-SLR] -> deparser_FF
    //   after :  mux_comb -> skid_FF / skid_FF -> [cross-SLR] -> deparser_FF
    //
    // 1-deep with mandatory 1-cycle bubble between transactions to avoid
    // overwriting deparser's payload staging registers. Throughput impact is
    // negligible since deparser already takes many cycles per packet.
    // =============================================================================

    // Combinational mux outputs (was the original direct-assign logic)
    wire [METADATA_LEN-1:0]                                  metadata_comb =
        grant_buffer       ? buffer_to_deparser_metadata_out :
        grant_up_broadcast ? up_broadcast_to_deparser_metadata_out :
        metadata_with_type;

    wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]           payload_comb =
        grant_up_broadcast ? aggregate_bram_rd_data_pack :
        grant_buffer       ? (buffer_to_deparser_down_down_broadcast_ok_en ? payload_bram_rd_pack : aggregate_bram_rd_data_pack) :
        {(PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH){1'b0}};

    wire down_broadcast_en_comb =
        (grant_up_broadcast && up_broadcast_to_deparser_down_broadcast_en) ||
        (grant_buffer && buffer_to_deparser_down_down_broadcast_ok_en);
    wire port_retrans_en_comb       = grant_buffer       && buffer_to_deparser_up_port_retrans_ok_en;
    wire FAN_retrans_en_comb        = grant_up_broadcast && up_broadcast_to_deparser_FAN_retrans_en;
    wire FAN_first_trans_en_comb    = grant_up_broadcast && up_broadcast_to_deparser_FAN_trans_en;
    wire ack_build_en_comb          = typer_ack_up_en;
    wire ack_down_en_comb           = typer_ack_down_en;

    // Source-side valid: derived from the deparser's agg_req_valid semantics
    wire skid_src_valid =
        down_broadcast_en_comb || port_retrans_en_comb ||
        FAN_retrans_en_comb    || FAN_first_trans_en_comb ||
        ack_build_en_comb      || ack_down_en_comb;

    // Skid buffer registers
    reg                                                      skid_valid;
    reg [METADATA_LEN-1:0]                                   skid_metadata;
    reg [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]            skid_payload;
    reg                                                      skid_down_broadcast_en;
    reg                                                      skid_port_retrans_en;
    reg                                                      skid_FAN_retrans_en;
    reg                                                      skid_FAN_first_trans_en;
    reg                                                      skid_ack_build_en;
    reg                                                      skid_ack_down_en;

    // Pipe stage: inserted between the comb mux output and the skid_payload
    // FF to break the BRAM_Q -> mux_LUT -> [cross-SLR] -> skid_payload path.
    // Without this stage, the 8192-bit aggregate BRAM Q drives a wide LUT-mux
    // whose output crosses SLR boundaries to reach skid_payload, dominating
    // setup violations (~80 paths, WNS = -0.46 ns). With pipe in place, the
    // mux LUT and pipe_payload FF can be placed in the same SLR as the source
    // BRAMs (BRAM_Q -> mux -> pipe_payload is local), and pipe_payload ->
    // skid_payload becomes a register-to-register cross-SLR hop with a full
    // clock period available. Pipe is 1-deep with the same skid-style flow
    // control (1-cycle bubble between transactions); deparser handshake
    // latency increases by 1 cycle but throughput is unaffected.
    reg                                                      pipe_valid;
    reg [METADATA_LEN-1:0]                                   pipe_metadata;
    reg [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]            pipe_payload;
    reg                                                      pipe_down_broadcast_en;
    reg                                                      pipe_port_retrans_en;
    reg                                                      pipe_FAN_retrans_en;
    reg                                                      pipe_FAN_first_trans_en;
    reg                                                      pipe_ack_build_en;
    reg                                                      pipe_ack_down_en;

    // Pipe-stage flow control: accept comb mux when empty; drain into skid
    // whenever skid is empty.
    assign pipe_can_accept = !pipe_valid;
    wire pipe_drain      = pipe_valid && !skid_valid;
    wire pipe_push       = pipe_can_accept && skid_src_valid;

    // Skid-stage flow control: accept from pipe; drain to deparser.
    wire skid_drain      = deparser_in_ready && skid_valid;
    wire skid_can_accept = !skid_valid;
    wire skid_push       = skid_can_accept && pipe_valid;

    // Pipe stage update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipe_valid              <= 1'b0;
            pipe_metadata           <= 0;
            pipe_payload            <= 0;
            pipe_down_broadcast_en  <= 1'b0;
            pipe_port_retrans_en    <= 1'b0;
            pipe_FAN_retrans_en     <= 1'b0;
            pipe_FAN_first_trans_en <= 1'b0;
            pipe_ack_build_en       <= 1'b0;
            pipe_ack_down_en        <= 1'b0;
        end
        else begin
            if (pipe_push) begin
                pipe_valid              <= 1'b1;
                pipe_metadata           <= metadata_comb;
                pipe_payload            <= payload_comb;
                pipe_down_broadcast_en  <= down_broadcast_en_comb;
                pipe_port_retrans_en    <= port_retrans_en_comb;
                pipe_FAN_retrans_en     <= FAN_retrans_en_comb;
                pipe_FAN_first_trans_en <= FAN_first_trans_en_comb;
                pipe_ack_build_en       <= ack_build_en_comb;
                pipe_ack_down_en        <= ack_down_en_comb;
            end
            else if (pipe_drain) begin
                pipe_valid              <= 1'b0;
                pipe_down_broadcast_en  <= 1'b0;
                pipe_port_retrans_en    <= 1'b0;
                pipe_FAN_retrans_en     <= 1'b0;
                pipe_FAN_first_trans_en <= 1'b0;
                pipe_ack_build_en       <= 1'b0;
                pipe_ack_down_en        <= 1'b0;
            end
        end
    end

    // Skid stage update (now sourced from pipe stage, not directly from comb)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            skid_valid              <= 1'b0;
            skid_metadata           <= 0;
            skid_payload            <= 0;
            skid_down_broadcast_en  <= 1'b0;
            skid_port_retrans_en    <= 1'b0;
            skid_FAN_retrans_en     <= 1'b0;
            skid_FAN_first_trans_en <= 1'b0;
            skid_ack_build_en       <= 1'b0;
            skid_ack_down_en        <= 1'b0;
        end
        else begin
            if (skid_push) begin
                skid_valid              <= 1'b1;
                skid_metadata           <= pipe_metadata;
                skid_payload            <= pipe_payload;
                skid_down_broadcast_en  <= pipe_down_broadcast_en;
                skid_port_retrans_en    <= pipe_port_retrans_en;
                skid_FAN_retrans_en     <= pipe_FAN_retrans_en;
                skid_FAN_first_trans_en <= pipe_FAN_first_trans_en;
                skid_ack_build_en       <= pipe_ack_build_en;
                skid_ack_down_en        <= pipe_ack_down_en;
            end
            else if (skid_drain) begin
                skid_valid              <= 1'b0;
                skid_down_broadcast_en  <= 1'b0;
                skid_port_retrans_en    <= 1'b0;
                skid_FAN_retrans_en     <= 1'b0;
                skid_FAN_first_trans_en <= 1'b0;
                skid_ack_build_en       <= 1'b0;
                skid_ack_down_en        <= 1'b0;
            end
        end
    end

    // metadata out (registered)
    assign metadata_with_type_out_to_deparser = skid_metadata;

    // payload out (registered)
    assign aggregate_bram_payload_out_to_deparser = skid_payload;

    // controller signals out (registered)
    assign aggregator_down_broadcast_en_out_to_deparser    = skid_down_broadcast_en;
    assign aggregator_port_retrans_en_out_to_deparser      = skid_port_retrans_en;
    assign aggregator_FAN_retrans_en_out_to_deparser       = skid_FAN_retrans_en;
    assign aggregator_FAN_first_trans_en_out_to_deparser   = skid_FAN_first_trans_en;
    assign Typer_ack_build_en_out_to_deparser              = skid_ack_build_en;
    assign Typer_ack_down_en_out_to_deparser               = skid_ack_down_en;

    // =============================================================================
    // SECTION 4: PARSER BACKPRESSURE (INPUT READY)
    // =============================================================================
    assign parser_out_ready = 
        // (typer_ack_up_en || typer_ack_down_en)             ? (grant_typer && deparser_in_ready) : 
        (typer_data_root_up_en || typer_data_noroot_up_en) ? up_retrans_to_typer_in_ready :       
        (typer_data_down_en)                               ? down_broadcast_to_typer_in_ready :   
        1'b1; 


endmodule
