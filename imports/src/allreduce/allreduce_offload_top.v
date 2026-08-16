`timescale 1ns / 1ps
`include "moe_defs.vh"
`include "slot_req_defs.vh"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/12 09:55:55
// Design Name: 
// Module Name: allreduce_offload_top
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


module allreduce_offload_top#(
    parameter PROT_NUM                  = 2,                            // 通信组数量
    parameter AXIS_DATA_WIDTH           = 512,
    parameter AXIS_KEEP_WIDTH           = AXIS_DATA_WIDTH / 8,
    parameter ORIGIN_HDR_LEN            = 54*8,

    parameter ADDR_RAM_SLOT_WIDTH       = 10,                            //对应psn的最大值，原本是8

    parameter PKT_HDR_LEN               = (2*6+4*4+3*2+1) * 8,
    parameter METADATA_LEN              = 2*8+3+5,

    // BUFFER
    parameter WINDOWSIZE                = 512,                            // 滑动窗口大小
    parameter BUFFER_SLOTS              = 1024,                           // 缓冲区长度
    parameter RING_SLOT_WIDTH           = 512,                            // 滑动窗口大小
    parameter BUFFER_SLOTS_WIDTH        = $clog2(BUFFER_SLOTS),

    // 数据payload相关
    parameter PAYLOAD_WIDTH             = 1024*8,
    parameter PAYLOAD_ITEM_NUM          = 16,
    parameter PAYLOAD_ITEM_WIDTH        = AXIS_DATA_WIDTH,
    parameter PAYLOAD_BEATS             = PAYLOAD_WIDTH / AXIS_DATA_WIDTH,
    parameter PAYLOAD_ITEM_COUNT_WIDTH  = $clog2(PAYLOAD_ITEM_NUM),

    // WIDTH
    parameter MAC_ADDR_WIDTH            = 48,
    parameter IP_ADDR_WIDTH             = 32,
    parameter PSN_WIDTH                 = 32,
    parameter PORT_WIDTH                = 16,
    parameter IP_START                  = 26,
    parameter BTH_START                 = 42,
    parameter OPCODE_WIDTH              = 8,
    parameter QPN_START                 = 46,
    parameter QPN_LEN                   = 32,

    // Parser -> FIFO
    parameter FIFO_DEPTH                = 32,
    parameter HASH_KEY_WIDTH            = 160,
    parameter HASH_DATA_WIDTH           = 9,

    // state controll
    parameter FAN_IN                    = 2,                           // 通信组数量 
    parameter FAN_IN_WIDTH              = $clog2(FAN_IN),
    parameter STATE_WIDTH               = PROT_NUM,

    // 
    parameter ADDR_WIDTH                = 8,
    parameter DATA_WIDTH                = 64,                           // 不用改：通信组数量 （原本32）

    // Typer
    parameter OPCODE_ACK                = 8'h11,
    parameter OPCODE_FIRST              = 8'h0,
    parameter OPCODE_MIDDLE             = 8'h1,
    parameter OPCODE_LAST               = 8'h2,
    parameter OPCODE_SEND_ONLY          = 8'h4,

    parameter TYPE_ACK_UP               = 3'b001,
    parameter TYPE_NOROOT_DATA_UP       = 3'b010,
    parameter TYPE_ROOT_DATA_UP         = 3'b011,
    parameter TYPE_DATA_DOWN            = 3'b100,
    parameter TYPE_ACK_DOWN             = 3'b101,
    parameter TYPE_NOVALID              = 3'b000,

    parameter ENABLE_MOE_COMBINE        = 0,
    parameter MOE_WINDOW_SIZE           = 8,
    parameter MOE_USE_REAL_PAYLOAD      = 0,
    parameter ENABLE_MOE_DISPATCH_INIT  = 0,
    parameter ENABLE_MOE_DISPATCH_EGRESS = 0,
    parameter [15:0] MOE_EXPERT_PORT_MASK_FLAT = 16'h0201

)(

          
    input wire                                                  rst_n,
    // input wire                                                  sys_clk_90m,
    input                                                       clk,               

      // AXI-stream input -> slave
    input wire [AXIS_DATA_WIDTH-1:0]                            s_axis_tdata,
    input wire [AXIS_KEEP_WIDTH-1:0]                            s_axis_tkeep,
    input wire                                                  s_axis_tvalid,
    input wire                                                  s_axis_tlast,
    output wire                                                 s_axis_tready,

    // AXI-stream output -> master (Currently placeholder without Deparser) => directly output
    output wire [AXIS_DATA_WIDTH-1:0]                           m_axis_tdata,
    output wire [AXIS_KEEP_WIDTH-1:0]                           m_axis_tkeep,
    output wire [127:0]                                          m_axis_tuser,
    output wire                                                 m_axis_tvalid,
    output wire                                                 m_axis_tlast,
    input wire                                                  m_axis_tready,

    // Route sideband (from deparser, for wrapper to build TUSER dst_port)
    output wire [2:0]                                           m_axis_route_type,
    output wire                                                 m_axis_is_aggregated,
    output wire [7:0]                                           m_axis_agg_ingress_port,
    output wire [255:0]                                         dbg_moe_perf_counters_flat,


    // Need to deparser
    input wire [7:0]                                            ingress_port,
    input wire                                                  cfg_is_root,

    // Per-port identity LUT (广播路径使用)
    input wire [47:0]                                           cfg_my_mac_p0,
    input wire [47:0]                                           cfg_my_mac_p1,
    input wire [31:0]                                           cfg_my_ip_p0,
    input wire [31:0]                                           cfg_my_ip_p1,
    input wire [23:0]                                           cfg_my_qp_p0,
    input wire [23:0]                                           cfg_my_qp_p1,
    input wire [15:0]                                           cfg_my_port_p0,
    input wire [15:0]                                           cfg_my_port_p1,
    input wire [47:0]                                           cfg_peer_mac_p0,
    input wire [47:0]                                           cfg_peer_mac_p1,
    input wire [31:0]                                           cfg_peer_ip_p0,
    input wire [31:0]                                           cfg_peer_ip_p1,
    input wire [23:0]                                           cfg_peer_qp_p0,
    input wire [23:0]                                           cfg_peer_qp_p1,
    input wire [15:0]                                           cfg_peer_port_p0,
    input wire [15:0]                                           cfg_peer_port_p1


    // output wire [PKT_HDR_LEN-1:0]                               parser_to_deparser_header_out,

    // output wire [METADATA_LEN-1:0]                              aggregator_to_deparser_metadata_out,
    // output wire                                                 aggregator_to_deparser_ack_build_en_out,                 // up_ack类型
    // output wire                                                 aggregator_to_deparser_ack_down_en_out,                  // ack_down，实际不存在
    // output wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]       aggregator_to_deparser_payload_out,                      // 输出payload信息
    // output wire                                                 aggregator_to_deparser_FAN_retrans_en_out,               // no_root_up_data，重传给父节点
    // output wire                                                 aggregator_to_deparser_FAN_first_trans_en_out,           // no_root_up_data，转发给父节点
    // output wire                                                 aggregator_to_deparser_down_broadcast_en_out,            // root_up_data转down_data/或down_data，广播给子节点
    // output wire                                                 aggregator_to_deparser_port_retrans_en_out,              // up_data类型，特定port重传
    
    // input wire                                                  deparser_to_aggregator_in_ready
);

    localparam MOE_ENGINE_ENTRY_COUNT = 2 * MOE_WINDOW_SIZE;
    localparam MOE_ENGINE_ENTRY_ADDR_WIDTH = $clog2(MOE_ENGINE_ENTRY_COUNT);

    wire [METADATA_LEN-1:0]                                     parser_to_aggregator_agg_metadata;
    wire [OPCODE_WIDTH-1:0]                                     parser_to_aggregator_agg_opcode;
    wire                                                        parser_to_aggregator_agg_payload_fire_en;
    wire                                                        aggregator_to_parser_ready;                         // aggregator 允许 parser 进

    wire [RING_SLOT_WIDTH+PAYLOAD_ITEM_COUNT_WIDTH-1:0]         parser_to_aggregator_payload_wr_addr;
    wire [PAYLOAD_ITEM_WIDTH-1:0]                               parser_to_aggregator_payload_wr_data;
    wire                                                        parser_to_aggregator_payload_wr_en;
    wire [METADATA_LEN-1:0]                                     parser_to_aggregator_payload_wr_metadata;
    wire                                                        moe_core_slot_init_ready;
    wire                                                        moe_core_slot_init_fire;
    wire                                                        moe_explicit_init_valid;
    wire                                                        moe_dispatch_init_selected;
    wire                                                        moe_init_valid;
    wire [ADDR_RAM_SLOT_WIDTH-1:0]                               moe_core_slot_init_addr;
    wire [31:0]                                                  moe_core_slot_init_seq;
    wire [ADDR_RAM_SLOT_WIDTH-1:0]                               moe_core_slot_init_slot_mod;
    reg                                                         moe_core_slot_init_pending;
    reg [ADDR_RAM_SLOT_WIDTH-1:0]                               moe_core_slot_init_pending_addr;
    reg                                                         moe_core_slot_init_seen;
    wire                                                        moe_core_slot_init_issue_valid;
    wire [ADDR_RAM_SLOT_WIDTH-1:0]                               moe_core_slot_init_issue_addr;
    wire                                                        moe_core_aggregate_update_valid;
    wire                                                        moe_core_aggregate_update_ready;
    wire                                                        moe_core_aggregate_update_done;
    wire [MOE_ENGINE_ENTRY_ADDR_WIDTH-1:0]                       moe_engine_aggregate_update_addr;
    wire [ADDR_RAM_SLOT_WIDTH-1:0]                               moe_core_aggregate_update_addr;
    wire [PAYLOAD_ITEM_WIDTH-1:0]                                moe_core_aggregate_update_data;
    wire [PAYLOAD_ITEM_WIDTH-1:0]                                moe_core_aggregate_update_sum;
    wire                                                        moe_core_aggregate_query_valid;
    wire                                                        moe_core_aggregate_query_ready;
    wire                                                        moe_core_aggregate_query_done;
    wire [MOE_ENGINE_ENTRY_ADDR_WIDTH-1:0]                       moe_engine_aggregate_query_addr;
    wire [ADDR_RAM_SLOT_WIDTH-1:0]                               moe_core_aggregate_query_addr;
    wire [PAYLOAD_ITEM_WIDTH-1:0]                                moe_core_aggregate_query_data;
    wire                                                        moe_core_arrival_update_valid;
    wire                                                        moe_core_arrival_update_ready;
    wire                                                        moe_core_arrival_update_done;
    wire [MOE_ENGINE_ENTRY_ADDR_WIDTH-1:0]                       moe_engine_arrival_update_addr;
    wire [ADDR_RAM_SLOT_WIDTH-1:0]                               moe_core_arrival_update_addr;
    wire [5:0]                                                  moe_core_arrival_update_lane_id;
    wire [DATA_WIDTH-1:0]                                       moe_core_arrival_update_bitmap;

    assign moe_core_aggregate_update_addr =
        {{(ADDR_RAM_SLOT_WIDTH-MOE_ENGINE_ENTRY_ADDR_WIDTH){1'b0}},
         moe_engine_aggregate_update_addr};
    assign moe_core_aggregate_query_addr =
        {{(ADDR_RAM_SLOT_WIDTH-MOE_ENGINE_ENTRY_ADDR_WIDTH){1'b0}},
         moe_engine_aggregate_query_addr};
    assign moe_core_arrival_update_addr =
        {{(ADDR_RAM_SLOT_WIDTH-MOE_ENGINE_ENTRY_ADDR_WIDTH){1'b0}},
         moe_engine_arrival_update_addr};

    // DEBUG: parser 抽出的 peer_mac/peer_ip 最低字节 (ILA 用, 验证字节序)
    wire [7:0]                                                  parser_dbg_s1_peer_mac_lsb;
    wire [7:0]                                                  parser_dbg_s1_peer_ip_lsb;
    wire                                                        parser_dbg_s3_valid;
    wire                                                        parser_dbg_lookup_hit;
    wire                                                        parser_dbg_endpoint_match;
    wire                                                        parser_dbg_send_only_match;
    wire                                                        parser_dbg_moe_prefix_match;
    wire [7:0]                                                  parser_dbg_opcode;
    wire [23:0]                                                 parser_dbg_qpn;

    // MoE parser descriptor sideband. Phase 5.5 can consume it through the
    // optional combine engine while the default parameter keeps legacy
    // AllReduce behavior unchanged.
    wire                                                        parser_moe_desc_valid;
    wire [7:0]                                                  parser_moe_desc_op_type;
    wire [127:0]                                                parser_moe_desc_out;
    wire                                                        parser_moe_payload_valid;
    wire [7:0]                                                  parser_moe_payload_op_type;
    wire [AXIS_DATA_WIDTH-1:0]                                  parser_moe_payload_data;
    wire [15:0]                                                 parser_moe_magic;
    wire [7:0]                                                  parser_moe_version;
    wire [7:0]                                                  parser_moe_owner_rank;
    wire [7:0]                                                  parser_moe_flags;
    wire [31:0]                                                 parser_moe_global_seq;
    wire [31:0]                                                 parser_moe_psn;
    wire [7:0]                                                  parser_moe_ingress_id;
    wire [7:0]                                                  parser_moe_psn_mod;
    wire                                                        slot_req_valid;
    wire [2:0]                                                  slot_req_kind;
    wire [7:0]                                                  slot_req_owner_rank;
    wire [7:0]                                                  slot_req_op_arg;
    wire [7:0]                                                  slot_req_flags;
    wire [31:0]                                                 slot_req_global_seq;
    wire [31:0]                                                 slot_req_token_id;
    wire [31:0]                                                 slot_req_psn;
    wire [7:0]                                                  slot_req_ingress_id;
    wire [7:0]                                                  slot_req_psn_mod;
    wire [63:0]                                                 slot_req_expected_bitmap;
    wire [7:0]                                                  slot_req_route_mask;
    wire [5:0]                                                  slot_req_lane_id;
    wire                                                        slot_req_is_dispatch;
    wire                                                        slot_req_is_combine_init;
    wire                                                        slot_req_is_combine_data;
    wire                                                        slot_req_is_combine_result;

    wire [AXIS_DATA_WIDTH-1:0]                                  deparser_m_axis_tdata;
    wire [AXIS_KEEP_WIDTH-1:0]                                  deparser_m_axis_tkeep;
    wire                                                        deparser_m_axis_tvalid;
    wire                                                        deparser_m_axis_tlast;
    wire                                                        deparser_m_axis_tready;
    wire [2:0]                                                  deparser_m_axis_route_type;
    wire                                                        deparser_m_axis_is_aggregated;
    wire [7:0]                                                  deparser_m_axis_agg_ingress_port;

    wire [AXIS_DATA_WIDTH-1:0]                                  moe_m_axis_tdata;
    wire [AXIS_KEEP_WIDTH-1:0]                                  moe_m_axis_tkeep;
    wire [127:0]                                                moe_m_axis_tuser;
    wire                                                        moe_m_axis_tvalid;
    wire                                                        moe_m_axis_tlast;
    wire                                                        moe_m_axis_tready;
    wire [AXIS_DATA_WIDTH-1:0]                                  moe_dispatch_m_axis_tdata;
    wire [AXIS_KEEP_WIDTH-1:0]                                  moe_dispatch_m_axis_tkeep;
    wire [127:0]                                                moe_dispatch_m_axis_tuser;
    wire                                                        moe_dispatch_m_axis_tvalid;
    wire                                                        moe_dispatch_m_axis_tlast;
    wire                                                        moe_dispatch_m_axis_tready;
    wire                                                        moe_init_ready;
    wire                                                        moe_init_accept;
    wire                                                        moe_init_drop_owner;
    wire                                                        moe_init_drop_window;
    wire                                                        moe_init_drop_busy;
    wire                                                        moe_dispatch_init_valid;
    wire                                                        moe_dispatch_init_ready;
    wire [7:0]                                                  moe_dispatch_init_owner_rank;
    wire [15:0]                                                 moe_dispatch_init_microbatch_id;
    wire [31:0]                                                 moe_dispatch_init_global_seq;
    wire [31:0]                                                 moe_dispatch_init_token_id;
    wire [63:0]                                                 moe_dispatch_init_expected_bitmap;
    wire [15:0]                                                 moe_dispatch_init_token_len;
    wire [7:0]                                                  moe_dispatch_init_chunk_count;
    wire                                                        moe_dispatch_accept;
    wire                                                        moe_dispatch_drop_busy;
    wire                                                        moe_data_ready;
    wire                                                        moe_data_accept;
    wire                                                        moe_data_drop_owner;
    wire                                                        moe_data_drop_no_entry;
    wire                                                        moe_data_drop_unexpected;
    wire                                                        moe_data_drop_duplicate;
    wire                                                        moe_release_accept;
    wire                                                        moe_release_drop_owner;
    wire                                                        moe_release_drop_no_entry;
    wire                                                        moe_release_drop_busy;
    wire                                                        moe_dispatch_egress_ready;
    wire                                                        moe_dispatch_egress_valid;
    wire                                                        moe_dispatch_egress_fire;
    reg                                                         moe_slot_req_valid_r;
    reg [2:0]                                                   moe_slot_req_kind_r;
    reg [7:0]                                                   moe_slot_owner_rank_r;
    reg [31:0]                                                  moe_slot_global_seq_r;
    reg [31:0]                                                  moe_slot_token_id_r;
    reg [31:0]                                                  moe_slot_psn_r;
    reg [63:0]                                                  moe_slot_expected_bitmap_r;
    reg [7:0]                                                   moe_slot_route_mask_r;
    reg [5:0]                                                   moe_slot_lane_id_r;
    reg                                                         moe_data_desc_pending;
    reg [7:0]                                                   moe_data_owner_rank_pending;
    reg [7:0]                                                   moe_data_expert_id_pending;
    reg [31:0]                                                  moe_data_global_seq_pending;
    reg [31:0]                                                  moe_data_token_id_pending;
    reg [31:0]                                                  moe_data_psn_pending;
    wire                                                        moe_data_fire;
    wire                                                        moe_capture_data_desc;
    reg                                                         moe_payload_pending;
    reg [511:0]                                                 moe_payload_data_r;
    reg                                                         moe_dispatch_desc_pending;
    reg [7:0]                                                   moe_dispatch_owner_rank_pending;
    reg [7:0]                                                   moe_dispatch_expert_bitmap_pending;
    reg [31:0]                                                  moe_dispatch_global_seq_pending;
    reg [31:0]                                                  moe_dispatch_psn_pending;
    reg                                                         moe_dispatch_payload_pending;
    reg [511:0]                                                 moe_dispatch_payload_data_r;
    reg [31:0]                                                  dbg_moe_dispatch_accept_count;
    reg [31:0]                                                  dbg_moe_init_accept_count;
    reg [31:0]                                                  dbg_moe_data_accept_count;
    reg [31:0]                                                  dbg_moe_release_accept_count;
    reg [31:0]                                                  dbg_moe_dispatch_output_count;
    reg [31:0]                                                  dbg_moe_combine_output_count;
    reg [31:0]                                                  dbg_moe_output_stall_count;
    reg [31:0]                                                  dbg_moe_drop_event_count;

    // AETH 字段 (parser -> deparser, 用于 ACK 重构真值透传)
    wire [7:0]                                                  parser_aeth_syndrome;
    wire [23:0]                                                 parser_aeth_msn;

    // DEBUG: deparser 内部 header 各级状态的低 32 bit (诊断 header 通路)
    wire [31:0]                                                 deparser_dbg_header_for_pkt_lo;
    wire [31:0]                                                 deparser_dbg_constructed_header_lo;

    // DEBUG (第二批): 系统化定位 m_axis_route_type=0 的 6 路 probe
    wire [2:0]                                                  deparser_dbg_current_state;
    wire                                                        deparser_dbg_header_v_at_agg_slot;
    wire [7:0]                                                  deparser_dbg_from_agg_slot;
    wire [7:0]                                                  deparser_dbg_parser_slot_r;
    wire                                                        deparser_dbg_header_valid_r;
    wire                                                        deparser_dbg_agg_req_valid;

    assign parser_moe_magic = parser_moe_desc_out[127:112];
    assign parser_moe_version = parser_moe_desc_out[111:104];
    assign parser_moe_owner_rank = parser_moe_desc_out[95:88];
    assign parser_moe_flags = parser_moe_desc_out[87:80];
    assign parser_moe_global_seq = parser_moe_desc_out[79:48];
    assign parser_moe_psn = parser_moe_desc_out[47:16];
    assign parser_moe_ingress_id = parser_moe_desc_out[15:8];
    assign parser_moe_psn_mod = parser_moe_desc_out[7:0];
    moe_slot_request_adapter u_moe_slot_request_adapter (
        .desc_valid(parser_moe_desc_valid),
        .desc_op_type(parser_moe_desc_op_type),
        .desc_in(parser_moe_desc_out),
        .slot_req_valid(slot_req_valid),
        .slot_req_kind(slot_req_kind),
        .slot_owner_rank(slot_req_owner_rank),
        .slot_op_arg(slot_req_op_arg),
        .slot_flags(slot_req_flags),
        .slot_global_seq(slot_req_global_seq),
        .slot_token_id(slot_req_token_id),
        .slot_psn(slot_req_psn),
        .slot_ingress_id(slot_req_ingress_id),
        .slot_psn_mod(slot_req_psn_mod),
        .slot_expected_bitmap(slot_req_expected_bitmap),
        .slot_route_mask(slot_req_route_mask),
        .slot_lane_id(slot_req_lane_id),
        .is_dispatch(slot_req_is_dispatch),
        .is_combine_init(slot_req_is_combine_init),
        .is_combine_data(slot_req_is_combine_data),
        .is_combine_result(slot_req_is_combine_result)
    );
    assign dbg_moe_perf_counters_flat = {
        dbg_moe_drop_event_count,
        dbg_moe_output_stall_count,
        dbg_moe_combine_output_count,
        dbg_moe_dispatch_output_count,
        dbg_moe_release_accept_count,
        dbg_moe_data_accept_count,
        dbg_moe_init_accept_count,
        dbg_moe_dispatch_accept_count
    };

    localparam OUTPUT_SEL_NONE     = 2'd0;
    localparam OUTPUT_SEL_COMBINE  = 2'd1;
    localparam OUTPUT_SEL_DISPATCH = 2'd2;
    localparam OUTPUT_SEL_DEPARSER = 2'd3;

    reg [1:0] output_sel_r;
    wire output_locked = (output_sel_r != OUTPUT_SEL_NONE);
    wire moe_combine_output_valid = (ENABLE_MOE_COMBINE != 0) && moe_m_axis_tvalid;
    wire moe_dispatch_output_valid = (ENABLE_MOE_DISPATCH_EGRESS != 0) && moe_dispatch_m_axis_tvalid;
    wire deparser_output_valid = deparser_m_axis_tvalid;
    wire select_combine_output = output_locked ?
                                 (output_sel_r == OUTPUT_SEL_COMBINE) :
                                 moe_combine_output_valid;
    wire select_dispatch_output = output_locked ?
                                  (output_sel_r == OUTPUT_SEL_DISPATCH) :
                                  (!moe_combine_output_valid && moe_dispatch_output_valid);
    wire select_deparser_output = output_locked ?
                                  (output_sel_r == OUTPUT_SEL_DEPARSER) :
                                  (!moe_combine_output_valid &&
                                   !moe_dispatch_output_valid &&
                                   deparser_output_valid);
    wire moe_output_selected = select_combine_output || select_dispatch_output;
    wire moe_dispatch_output_done = (output_sel_r == OUTPUT_SEL_DISPATCH) &&
                                    m_axis_tvalid && m_axis_tready && m_axis_tlast;
    wire moe_combine_output_done = moe_release_accept;
    wire moe_output_stall = moe_output_selected && m_axis_tvalid && !m_axis_tready;
    wire moe_drop_event = moe_dispatch_drop_busy ||
                          moe_init_drop_owner ||
                          moe_init_drop_window ||
                          moe_init_drop_busy ||
                          moe_data_drop_owner ||
                          moe_data_drop_no_entry ||
                          moe_data_drop_unexpected ||
                          moe_data_drop_duplicate ||
                          moe_release_drop_owner ||
                          moe_release_drop_no_entry ||
                          moe_release_drop_busy;
    assign deparser_m_axis_tready = m_axis_tready && select_deparser_output;
    assign moe_m_axis_tready = m_axis_tready &&
                               (output_sel_r != OUTPUT_SEL_DISPATCH) &&
                               (output_sel_r != OUTPUT_SEL_DEPARSER);
    assign moe_dispatch_m_axis_tready = m_axis_tready &&
                                        (output_sel_r == OUTPUT_SEL_DISPATCH);

    function [7:0] port_mask_to_binary;
        input [7:0] port_mask;
        begin
            casez (port_mask)
                8'b????_???1: port_mask_to_binary = 8'd0;
                8'b????_??10: port_mask_to_binary = 8'd1;
                8'b????_?100: port_mask_to_binary = 8'd2;
                8'b????_1000: port_mask_to_binary = 8'd3;
                default:      port_mask_to_binary = 8'd0;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            moe_slot_req_valid_r <= 1'b0;
            moe_slot_req_kind_r <= `SLOT_REQ_KIND_NONE;
            moe_slot_owner_rank_r <= 8'd0;
            moe_slot_global_seq_r <= 32'd0;
            moe_slot_token_id_r <= 32'd0;
            moe_slot_psn_r <= 32'd0;
            moe_slot_expected_bitmap_r <= 64'd0;
            moe_slot_route_mask_r <= 8'd0;
            moe_slot_lane_id_r <= 6'd0;
            moe_data_desc_pending <= 1'b0;
            moe_data_owner_rank_pending <= 8'd0;
            moe_data_expert_id_pending <= 8'd0;
            moe_data_global_seq_pending <= 32'd0;
            moe_data_token_id_pending <= 32'd0;
            moe_data_psn_pending <= 32'd0;
            moe_payload_pending <= 1'b0;
            moe_payload_data_r <= 512'd0;
            moe_dispatch_desc_pending <= 1'b0;
            moe_dispatch_owner_rank_pending <= 8'd0;
            moe_dispatch_expert_bitmap_pending <= 8'd0;
            moe_dispatch_global_seq_pending <= 32'd0;
            moe_dispatch_psn_pending <= 32'd0;
            moe_dispatch_payload_pending <= 1'b0;
            moe_dispatch_payload_data_r <= 512'd0;
            output_sel_r <= OUTPUT_SEL_NONE;
            dbg_moe_dispatch_accept_count <= 32'd0;
            dbg_moe_init_accept_count <= 32'd0;
            dbg_moe_data_accept_count <= 32'd0;
            dbg_moe_release_accept_count <= 32'd0;
            dbg_moe_dispatch_output_count <= 32'd0;
            dbg_moe_combine_output_count <= 32'd0;
            dbg_moe_output_stall_count <= 32'd0;
            dbg_moe_drop_event_count <= 32'd0;
            moe_core_slot_init_pending <= 1'b0;
            moe_core_slot_init_pending_addr <= {ADDR_RAM_SLOT_WIDTH{1'b0}};
            moe_core_slot_init_seen <= 1'b0;
        end
        else begin
            moe_slot_req_valid_r <= (ENABLE_MOE_COMBINE != 0) && slot_req_valid;
            moe_slot_req_kind_r <= slot_req_kind;
            moe_slot_owner_rank_r <= slot_req_owner_rank;
            moe_slot_global_seq_r <= slot_req_global_seq;
            moe_slot_token_id_r <= slot_req_token_id;
            moe_slot_psn_r <= slot_req_psn;
            moe_slot_expected_bitmap_r <= slot_req_expected_bitmap;
            moe_slot_route_mask_r <= slot_req_route_mask;
            moe_slot_lane_id_r <= slot_req_lane_id;

            if (moe_capture_data_desc) begin
                moe_data_desc_pending <= 1'b1;
                moe_data_owner_rank_pending <= slot_req_owner_rank;
                moe_data_expert_id_pending <= {2'd0, slot_req_lane_id};
                moe_data_global_seq_pending <= slot_req_global_seq;
                moe_data_token_id_pending <= slot_req_token_id;
                moe_data_psn_pending <= slot_req_psn;
            end

            if ((ENABLE_MOE_COMBINE != 0) && (MOE_USE_REAL_PAYLOAD != 0) &&
                parser_moe_payload_valid &&
                (parser_moe_payload_op_type == `MOE_OP_COMBINE_DATA)) begin
                moe_payload_pending <= 1'b1;
                moe_payload_data_r <= parser_moe_payload_data;
            end

            if ((ENABLE_MOE_COMBINE != 0) && (ENABLE_MOE_DISPATCH_EGRESS != 0) &&
                slot_req_is_dispatch &&
                (!moe_dispatch_desc_pending || moe_dispatch_egress_fire)) begin
                moe_dispatch_desc_pending <= 1'b1;
                moe_dispatch_owner_rank_pending <= slot_req_owner_rank;
                moe_dispatch_expert_bitmap_pending <= slot_req_route_mask;
                moe_dispatch_global_seq_pending <= slot_req_global_seq;
                moe_dispatch_psn_pending <= slot_req_psn;
            end

            if ((ENABLE_MOE_COMBINE != 0) && (ENABLE_MOE_DISPATCH_EGRESS != 0) &&
                parser_moe_payload_valid &&
                (parser_moe_payload_op_type == `MOE_OP_DISPATCH) &&
                (!moe_dispatch_payload_pending || moe_dispatch_egress_fire)) begin
                moe_dispatch_payload_pending <= 1'b1;
                moe_dispatch_payload_data_r <= parser_moe_payload_data;
            end

            if (moe_data_fire && !moe_capture_data_desc) begin
                moe_data_desc_pending <= 1'b0;
                if (MOE_USE_REAL_PAYLOAD != 0) begin
                    moe_payload_pending <= 1'b0;
                end
            end

            if (moe_dispatch_egress_fire) begin
                moe_dispatch_desc_pending <= 1'b0;
                moe_dispatch_payload_pending <= 1'b0;
                output_sel_r <= OUTPUT_SEL_DISPATCH;
            end

            if (!moe_init_valid) begin
                moe_core_slot_init_seen <= 1'b0;
            end
            else if (!moe_core_slot_init_seen) begin
                moe_core_slot_init_seen <= 1'b1;
            end

            if (moe_core_slot_init_fire) begin
                moe_core_slot_init_pending <= 1'b0;
            end
            else if (moe_init_valid &&
                     !moe_core_slot_init_ready &&
                     !moe_core_slot_init_pending &&
                     !moe_core_slot_init_seen) begin
                moe_core_slot_init_pending <= 1'b1;
                moe_core_slot_init_pending_addr <= moe_core_slot_init_addr;
            end

            if (m_axis_tvalid && m_axis_tready) begin
                if (output_sel_r == OUTPUT_SEL_NONE) begin
                    if (!m_axis_tlast) begin
                        if (select_combine_output) begin
                            output_sel_r <= OUTPUT_SEL_COMBINE;
                        end
                        else if (select_dispatch_output) begin
                            output_sel_r <= OUTPUT_SEL_DISPATCH;
                        end
                        else if (select_deparser_output) begin
                            output_sel_r <= OUTPUT_SEL_DEPARSER;
                        end
                    end
                end
                else if (m_axis_tlast) begin
                    output_sel_r <= OUTPUT_SEL_NONE;
                end
            end

            if (moe_dispatch_accept) begin
                dbg_moe_dispatch_accept_count <= dbg_moe_dispatch_accept_count + 1'b1;
            end
            if (moe_init_accept) begin
                dbg_moe_init_accept_count <= dbg_moe_init_accept_count + 1'b1;
            end
            if (moe_data_accept) begin
                dbg_moe_data_accept_count <= dbg_moe_data_accept_count + 1'b1;
            end
            if (moe_release_accept) begin
                dbg_moe_release_accept_count <= dbg_moe_release_accept_count + 1'b1;
            end
            if (moe_dispatch_output_done) begin
                dbg_moe_dispatch_output_count <= dbg_moe_dispatch_output_count + 1'b1;
            end
            if (moe_combine_output_done) begin
                dbg_moe_combine_output_count <= dbg_moe_combine_output_count + 1'b1;
            end
            if (moe_output_stall) begin
                dbg_moe_output_stall_count <= dbg_moe_output_stall_count + 1'b1;
            end
            if (moe_drop_event) begin
                dbg_moe_drop_event_count <= dbg_moe_drop_event_count + 1'b1;
            end
        end
    end


    // =================================================================
    // Internal Wires: Parser <-> Deparser (Pass-through path) => to egress directly
    // =================================================================
    wire                                            parser_to_egress_pkt_valid_out;
    wire [AXIS_DATA_WIDTH-1:0]                      parser_to_egress_pkt_data_out;
    wire [AXIS_KEEP_WIDTH-1:0]                      parser_to_egress_pkt_keep_out;
    wire                                            parser_to_egress_pkt_last_out;
    wire                                            egress_to_parser_pkt_ready;

    wire [PKT_HDR_LEN-1:0]                          parser_to_deparser_header_out;
    wire                                            parser_to_deparser_header_valid;

    // assign egress_to_parser_pkt_ready = 1'b1;
   

    // =================================================================
    // Internal Wires: Aggregator <-> Deparser (Aggregated path)
    // =================================================================
    // wire                                            agg_ack_build_en;
    // wire                                            agg_ack_down_en;
    // wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]  agg_payload_to_deparser;
    // wire                                            agg_fan_retrans_en;
    // wire                                            agg_fan_first_trans_en;
    // wire                                            agg_down_broadcast_en;
    // wire                                            agg_port_retrans_en;
    // wire                                            deparser_to_aggregator_ready;

    wire [METADATA_LEN-1:0]                         aggregator_to_deparser_metadata_out;
    wire                                            aggregator_to_deparser_ack_build_en_out;
    wire                                            aggregator_to_deparser_ack_down_en_out;
    wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]  aggregator_to_deparser_payload_out;
    wire                                            aggregator_to_deparser_FAN_retrans_en_out;
    wire                                            aggregator_to_deparser_FAN_first_trans_en_out;
    wire                                            aggregator_to_deparser_down_broadcast_en_out;
    wire                                            aggregator_to_deparser_port_retrans_en_out;
    wire                                            deparser_to_aggregator_in_ready;

    // wire clk;
    // wire pll_locked;
    // wire pll_reset;

    // assign pll_reset = ~rst_n;


    // // =================================================================
    // // Logic: Payload Write Monitor (Implemented in Top Level)
    // // =================================================================
    // reg payload_write_done;

    // always @(posedge clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         payload_write_done <= 1'b0;
    //     end
    //     else begin
    //         if (parser_to_aggregator_payload_wr_en && parser_to_aggregator_payload_wr_addr[PAYLOAD_ITEM_COUNT_WIDTH-1:0] == 0) begin
    //             payload_write_done <= 1'b0;
    //         end

    //         else if (parser_to_aggregator_payload_wr_en && parser_to_aggregator_payload_wr_addr[PAYLOAD_ITEM_COUNT_WIDTH-1:0] == (PAYLOAD_ITEM_NUM - 1)) begin
    //             payload_write_done <= 1'b1;
    //         end
    //     end
    // end

    // wire aggregator_need_payload;       // 区分aggregator需要使用到payload的情况

    // assign aggregator_need_payload =  ;




    // =================================================================
    // Temporary Logic for missing Deparser
    // =================================================================
    // In a complete design, a Deparser module would arbitrate between 
    // pkt_* (pass-through) and agg_* (aggregated) signals to drive m_axis_*.
    // Here we just map the ready signals to allow simulation flow.
    // assign deparser_to_parser_pkt_ready = m_axis_tready;
    // assign deparser_to_aggregator_ready = m_axis_tready;
    
    // // Tie off master outputs to 0 for now to prevent floating outputs
    // assign m_axis_tdata = 0;
    // assign m_axis_tkeep = 0;
    // assign m_axis_tvalid = 0;
    // assign m_axis_tlast = 0;

    // =================================================================
    // Module Instantiation: Parser
    // =================================================================
    parser #(
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
        .AXIS_KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .ORIGIN_HDR_LEN(ORIGIN_HDR_LEN),
        .HASH_KEY_WIDTH(HASH_KEY_WIDTH),
        .HASH_DATA_WIDTH(HASH_DATA_WIDTH),
        .PKT_HDR_LEN(PKT_HDR_LEN),
        .METADATA_LEN(METADATA_LEN),
        .PAYLOAD_WIDTH(PAYLOAD_WIDTH),
        .PAYLOAD_ITEM_NUM(PAYLOAD_ITEM_NUM),
        .PAYLOAD_ITEM_WIDTH(PAYLOAD_ITEM_WIDTH),
        .MAC_ADDR_WIDTH(MAC_ADDR_WIDTH),
        .IP_ADDR_WIDTH(IP_ADDR_WIDTH),
        .PSN_WIDTH(PSN_WIDTH),
        .PORT_WIDTH(PORT_WIDTH),
        .IP_START(IP_START),
        .BTH_START(BTH_START),
        .OPCODE_WIDTH(OPCODE_WIDTH),
        .QPN_START(QPN_START),
        .QPN_LEN(QPN_LEN),
        .WINDOWSIZE(WINDOWSIZE),
        .BUFFER_SLOTS(BUFFER_SLOTS),
        .RING_SLOT_WIDTH(RING_SLOT_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),
        .RAM_SLOT_WIDTH(ADDR_RAM_SLOT_WIDTH)
    ) allreduce_parser (
        .axis_clk(clk),
        .rst_n(rst_n),
        
        // AXI Stream Input
        .axis_in_data(s_axis_tdata),
        .axis_tkeep(s_axis_tkeep),
        .axis_tvalid(s_axis_tvalid),
        .axis_tlast(s_axis_tlast),
        .in_ready(s_axis_tready),
        .ingress_port(ingress_port),

        // Pass-through Output (to egress)
        .pkt_valid_out(parser_to_egress_pkt_valid_out),
        .pkt_data_out(parser_to_egress_pkt_data_out),
        .pkt_keep_out(parser_to_egress_pkt_keep_out),
        .pkt_last_out(parser_to_egress_pkt_last_out),
        .pkt_ready_in(egress_to_parser_pkt_ready),  //output-egress 是否运行送出

        // to deparser for aggregator
        .agg_header_out(parser_to_deparser_header_out), // Not used by aggregator core
        .agg_header_valid(parser_to_deparser_header_valid),

        // Aggregator Interface
        .agg_metadata_out(parser_to_aggregator_agg_metadata),
        .agg_opcode_out(parser_to_aggregator_agg_opcode),
        .agg_payload_fire_en(parser_to_aggregator_agg_payload_fire_en),
        .agg_ready_in(aggregator_to_parser_ready),

        .cfg_local_mac(cfg_my_mac_p0),
        .cfg_local_ip(cfg_my_ip_p0),
        .cfg_local_udp_port(cfg_my_port_p0),
        .cfg_local_qpn(cfg_my_qp_p0),
        .cfg_enable_moe(ENABLE_MOE_COMBINE != 0),

        // Payload BRAM Interface
        .payload_wr_addr(parser_to_aggregator_payload_wr_addr),
        .payload_wr_data(parser_to_aggregator_payload_wr_data),
        .payload_wr_en(parser_to_aggregator_payload_wr_en),
        .latched_metadata_for_write(parser_to_aggregator_payload_wr_metadata),
        .payload_wr_ready(1'b1), // BRAM in aggregator is always ready for write

        // MoE Phase 1 descriptor sideband
        .moe_desc_valid(parser_moe_desc_valid),
        .moe_desc_op_type(parser_moe_desc_op_type),
        .moe_desc_out(parser_moe_desc_out),
        .moe_payload_valid(parser_moe_payload_valid),
        .moe_payload_op_type(parser_moe_payload_op_type),
        .moe_payload_data(parser_moe_payload_data),

        // DEBUG: parser 抽出的 peer_mac/peer_ip 低字节, 用于上板确认字节序
        .dbg_s1_peer_mac_lsb(parser_dbg_s1_peer_mac_lsb),
        .dbg_s1_peer_ip_lsb (parser_dbg_s1_peer_ip_lsb),
        .dbg_s3_valid        (parser_dbg_s3_valid),
        .dbg_lookup_hit      (parser_dbg_lookup_hit),
        .dbg_endpoint_match  (parser_dbg_endpoint_match),
        .dbg_send_only_match (parser_dbg_send_only_match),
        .dbg_moe_prefix_match(parser_dbg_moe_prefix_match),
        .dbg_opcode          (parser_dbg_opcode),
        .dbg_qpn             (parser_dbg_qpn),

        // AETH 字段输出
        .agg_aeth_syndrome_out(parser_aeth_syndrome),
        .agg_aeth_msn_out(parser_aeth_msn)
    );

    aggregator_core_top #(
        .METADATA_LEN(METADATA_LEN),
        .PAYLOAD_ITEM_WIDTH(PAYLOAD_ITEM_WIDTH),
        .INGRESS_PROT_NUM(PROT_NUM), // Mapping PROT_NUM to INGRESS_PROT_NUM
        .RING_SLOT_WIDTH(RING_SLOT_WIDTH),
        .WINDOWSIZE(WINDOWSIZE),
        // .ADDR_WIDTH(ADDR_WIDTH),
        .ADDR_WIDTH(ADDR_RAM_SLOT_WIDTH),

        .DATA_WIDTH(DATA_WIDTH),
        .OPCODE_WIDTH(OPCODE_WIDTH),
        .OPCODE_ACK(OPCODE_ACK),
        .OPCODE_FIRST(OPCODE_FIRST),
        .OPCODE_MIDDLE(OPCODE_MIDDLE), // Note: Parameter name mismatch fix
        .OPCODE_LAST(OPCODE_LAST),
        .OPCODE_SEND_ONLY(OPCODE_SEND_ONLY),
        .PAYLOAD_ITEM_NUM(PAYLOAD_ITEM_NUM),
        .BUFFER_SLOTS(BUFFER_SLOTS)
    ) u_aggregator (
        .clk(clk),
        .rst_n(rst_n),

        // Input from Parser
        .parser_agg_metadata(parser_to_aggregator_agg_metadata),
        .parser_agg_opcode(parser_to_aggregator_agg_opcode),
        .parser_agg_payload_fire_en(parser_to_aggregator_agg_payload_fire_en),
        .parser_payload_wr_metadata(parser_to_aggregator_payload_wr_metadata),
        .parser_payload_wr_addr(parser_to_aggregator_payload_wr_addr),
        .parser_payload_wr_data(parser_to_aggregator_payload_wr_data),
        .parser_payload_wr_en(parser_to_aggregator_payload_wr_en),
        .parser_out_ready(aggregator_to_parser_ready),
        .moe_slot_init_valid(moe_core_slot_init_issue_valid),
        .moe_slot_init_addr(moe_core_slot_init_issue_addr),
        .moe_slot_init_ready(moe_core_slot_init_ready),
        .moe_slot_init_fire(moe_core_slot_init_fire),
        .moe_aggregate_update_valid(moe_core_aggregate_update_valid),
        .moe_aggregate_update_addr(moe_core_aggregate_update_addr),
        .moe_aggregate_update_data(moe_core_aggregate_update_data),
        .moe_aggregate_update_ready(moe_core_aggregate_update_ready),
        .moe_aggregate_update_done(moe_core_aggregate_update_done),
        .moe_aggregate_update_sum_dbg(moe_core_aggregate_update_sum),
        .moe_aggregate_query_valid(moe_core_aggregate_query_valid),
        .moe_aggregate_query_addr(moe_core_aggregate_query_addr),
        .moe_aggregate_query_ready(moe_core_aggregate_query_ready),
        .moe_aggregate_query_done(moe_core_aggregate_query_done),
        .moe_aggregate_query_data(moe_core_aggregate_query_data),
        .moe_arrival_update_valid(moe_core_arrival_update_valid),
        .moe_arrival_update_addr(moe_core_arrival_update_addr),
        .moe_arrival_update_lane_id(moe_core_arrival_update_lane_id),
        .moe_arrival_update_ready(moe_core_arrival_update_ready),
        .moe_arrival_update_done(moe_core_arrival_update_done),
        .moe_arrival_update_bitmap_dbg(moe_core_arrival_update_bitmap),

        // Output to Deparser
        .deparser_in_ready(deparser_to_aggregator_in_ready),
        .metadata_with_type_out_to_deparser(aggregator_to_deparser_metadata_out),
        .Typer_ack_build_en_out_to_deparser(aggregator_to_deparser_ack_build_en_out),
        .Typer_ack_down_en_out_to_deparser(aggregator_to_deparser_ack_down_en_out),
        .aggregate_bram_payload_out_to_deparser(aggregator_to_deparser_payload_out),
        .aggregator_FAN_retrans_en_out_to_deparser(aggregator_to_deparser_FAN_retrans_en_out),
        .aggregator_FAN_first_trans_en_out_to_deparser(aggregator_to_deparser_FAN_first_trans_en_out),
        .aggregator_down_broadcast_en_out_to_deparser(aggregator_to_deparser_down_broadcast_en_out),
        .aggregator_port_retrans_en_out_to_deparser(aggregator_to_deparser_port_retrans_en_out)
    );

    deparser #(
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
        .AXIS_KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .PKT_HDR_LEN(PKT_HDR_LEN),
        .METADATA_LEN(METADATA_LEN),
        .PAYLOAD_ITEM_NUM(PAYLOAD_ITEM_NUM),
        .PAYLOAD_ITEM_WIDTH(PAYLOAD_ITEM_WIDTH),
        .PAYLOAD_TOTAL_WIDTH(PAYLOAD_WIDTH),
        .MAC_ADDR_WIDTH(MAC_ADDR_WIDTH),
        .IP_ADDR_WIDTH(IP_ADDR_WIDTH),
        .PORT_WIDTH(PORT_WIDTH),
        .QPN_LEN(QPN_LEN),
        .PSN_WIDTH(PSN_WIDTH),
        .OPCODE_WIDTH(OPCODE_WIDTH),
        // 必须和 parser 的 RAM_SLOT_WIDTH(=ADDR_RAM_SLOT_WIDTH=10) 对齐.
        // 默认值 4 与 parser 不匹配, psn_mod>15 的包会让 deparser header_v /
        // header_mem 越界, route_type 恒 0, 输出 17 拍全零垃圾包.
        // 仿真用 PSN=0 时 psn_mod=0 始终落 slot 0 掩盖了这个 bug, 上板真实 PSN
        // 必现.
        .HEADER_SLOT_WIDTH(4)
    ) allreduce_deparser (
        .clk(clk),
        .rst_n(rst_n),

        // 1. Interface with Parser (Pass-through Path)
        .from_parser_pkt_valid(parser_to_egress_pkt_valid_out),
        .from_parser_pkt_data(parser_to_egress_pkt_data_out),
        .from_parser_pkt_keep(parser_to_egress_pkt_keep_out),
        .from_parser_pkt_last(parser_to_egress_pkt_last_out),
        .in_parser_pkt_ready(egress_to_parser_pkt_ready),

        // 2. Interface with Parser (Header Info)
        .from_parser_header_in(parser_to_deparser_header_out),
        .from_parser_metadata_in(parser_to_aggregator_agg_metadata),
        .from_parser_header_valid(parser_to_deparser_header_valid),
        .from_parser_aeth_syndrome_in(parser_aeth_syndrome),
        .from_parser_aeth_msn_in(parser_aeth_msn),
        .cfg_is_root(cfg_is_root),
        .cfg_my_mac_p0(cfg_my_mac_p0),
        .cfg_my_mac_p1(cfg_my_mac_p1),
        .cfg_my_ip_p0(cfg_my_ip_p0),
        .cfg_my_ip_p1(cfg_my_ip_p1),
        .cfg_my_qp_p0(cfg_my_qp_p0),
        .cfg_my_qp_p1(cfg_my_qp_p1),
        .cfg_my_port_p0(cfg_my_port_p0),
        .cfg_my_port_p1(cfg_my_port_p1),
        .cfg_peer_mac_p0(cfg_peer_mac_p0),
        .cfg_peer_mac_p1(cfg_peer_mac_p1),
        .cfg_peer_ip_p0(cfg_peer_ip_p0),
        .cfg_peer_ip_p1(cfg_peer_ip_p1),
        .cfg_peer_qp_p0(cfg_peer_qp_p0),
        .cfg_peer_qp_p1(cfg_peer_qp_p1),
        .cfg_peer_port_p0(cfg_peer_port_p0),
        .cfg_peer_port_p1(cfg_peer_port_p1),

        // 3. Interface with Aggregator
        .from_agg_metadata_in(aggregator_to_deparser_metadata_out),
        .from_agg_ack_build_en(aggregator_to_deparser_ack_build_en_out),
        .from_agg_ack_down_en(aggregator_to_deparser_ack_down_en_out),
        .from_agg_FAN_retrans_en(aggregator_to_deparser_FAN_retrans_en_out),
        .from_agg_FAN_first_trans_en(aggregator_to_deparser_FAN_first_trans_en_out),
        .from_agg_down_broadcast_en(aggregator_to_deparser_down_broadcast_en_out),
        .from_agg_port_retrans_en(aggregator_to_deparser_port_retrans_en_out),
        .from_agg_payload_in(aggregator_to_deparser_payload_out),
        .in_agg_ready(deparser_to_aggregator_in_ready),

        // 4. Master AXI Stream Output
        .m_axis_tdata(deparser_m_axis_tdata),
        .m_axis_tkeep(deparser_m_axis_tkeep),
        .m_axis_tvalid(deparser_m_axis_tvalid),
        .m_axis_tlast(deparser_m_axis_tlast),
        .m_axis_tready(deparser_m_axis_tready),

        // 5. Route sideband
        .m_axis_route_type(deparser_m_axis_route_type),
        .m_axis_is_aggregated(deparser_m_axis_is_aggregated),
        .m_axis_agg_ingress_port(deparser_m_axis_agg_ingress_port),

        // DEBUG: deparser 内部 header_for_pkt / constructed_header 的低 32 bit
        .dbg_header_for_pkt_lo   (deparser_dbg_header_for_pkt_lo),
        .dbg_constructed_header_lo(deparser_dbg_constructed_header_lo),

        // DEBUG (第二批): 系统化定位 m_axis_route_type=0 的 6 路 probe
        .dbg_current_state          (deparser_dbg_current_state),
        .dbg_header_v_at_agg_slot   (deparser_dbg_header_v_at_agg_slot),
        .dbg_from_agg_slot          (deparser_dbg_from_agg_slot),
        .dbg_parser_slot_r          (deparser_dbg_parser_slot_r),
        .dbg_header_valid_r         (deparser_dbg_header_valid_r),
        .dbg_agg_req_valid          (deparser_dbg_agg_req_valid)
    );

    assign moe_explicit_init_valid = moe_slot_req_valid_r &&
                                     (moe_slot_req_kind_r == `SLOT_REQ_KIND_INIT);
    assign moe_dispatch_init_selected = moe_dispatch_init_valid && !moe_explicit_init_valid;
    assign moe_init_valid = moe_explicit_init_valid || moe_dispatch_init_selected;
    assign moe_dispatch_init_ready = moe_init_ready && !moe_explicit_init_valid;
    assign moe_core_slot_init_seq = moe_dispatch_init_selected ?
                                    moe_dispatch_init_global_seq :
                                    moe_slot_global_seq_r;
    wire moe_synthetic_data_valid = moe_data_desc_pending;
    wire moe_real_data_valid = moe_data_desc_pending && moe_payload_pending;
    wire moe_data_valid = (MOE_USE_REAL_PAYLOAD != 0) ?
                          moe_real_data_valid : moe_synthetic_data_valid;
    assign moe_data_fire = moe_data_valid && moe_data_ready;
    assign moe_capture_data_desc = (ENABLE_MOE_COMBINE != 0) &&
                                   slot_req_is_combine_data &&
                                   (!moe_data_desc_pending || moe_data_fire);
    wire [63:0] moe_init_expected_bitmap = moe_slot_expected_bitmap_r;
    wire [7:0] moe_init_owner_rank = moe_dispatch_init_selected ?
                                     moe_dispatch_init_owner_rank : moe_slot_owner_rank_r;
    assign moe_core_slot_init_slot_mod = moe_core_slot_init_seq % MOE_WINDOW_SIZE;
    assign moe_core_slot_init_addr = (moe_init_owner_rank * MOE_WINDOW_SIZE) +
                                      moe_core_slot_init_slot_mod;
    wire [15:0] moe_init_microbatch_id = moe_dispatch_init_selected ?
                                     moe_dispatch_init_microbatch_id : 16'h0000;
    wire [31:0] moe_init_global_seq = moe_dispatch_init_selected ?
                                      moe_dispatch_init_global_seq : moe_slot_global_seq_r;
    wire [31:0] moe_init_token_id = moe_dispatch_init_selected ?
                                    moe_dispatch_init_token_id : moe_slot_token_id_r;
    wire [63:0] moe_selected_init_expected_bitmap = moe_dispatch_init_selected ?
                                                   moe_dispatch_init_expected_bitmap :
                                                   moe_init_expected_bitmap;
    wire [15:0] moe_init_token_len = moe_dispatch_init_selected ?
                                     moe_dispatch_init_token_len : 16'd1024;
    wire [7:0] moe_init_chunk_count = moe_dispatch_init_selected ?
                                      moe_dispatch_init_chunk_count : 8'd1;
    assign moe_core_slot_init_issue_valid = moe_core_slot_init_pending ||
                                            (moe_init_valid && !moe_core_slot_init_seen);
    assign moe_core_slot_init_issue_addr = moe_core_slot_init_pending ?
                                           moe_core_slot_init_pending_addr :
                                           moe_core_slot_init_addr;
    wire [31:0] moe_token_id = moe_data_token_id_pending;
    wire [31:0] moe_payload_word = {24'd0, moe_data_expert_id_pending} + 32'd1;
    wire [511:0] moe_synthetic_payload = {16{moe_payload_word}};
    wire [7:0] moe_data_owner_rank = moe_data_owner_rank_pending;
    wire [31:0] moe_data_global_seq = moe_data_global_seq_pending;
    wire [31:0] moe_data_token_id = moe_token_id;
    wire [7:0] moe_data_expert_id = moe_data_expert_id_pending;
    wire [511:0] moe_data_payload = (MOE_USE_REAL_PAYLOAD != 0) ?
                                    moe_payload_data_r : moe_synthetic_payload;
    wire [31:0] moe_result_psn = moe_data_psn_pending;
    assign moe_dispatch_egress_valid = (ENABLE_MOE_COMBINE != 0) &&
                                       (ENABLE_MOE_DISPATCH_EGRESS != 0) &&
                                       moe_dispatch_desc_pending &&
                                       moe_dispatch_payload_pending &&
                                       (output_sel_r == OUTPUT_SEL_NONE) &&
                                       !moe_combine_output_valid &&
                                       !deparser_output_valid;
    assign moe_dispatch_egress_fire = moe_dispatch_egress_valid && moe_dispatch_egress_ready;

    moe_dispatch_init_adapter u_moe_dispatch_init_adapter (
        .clk(clk),
        .rst_n(rst_n),
        .enable((ENABLE_MOE_COMBINE != 0) && (ENABLE_MOE_DISPATCH_INIT != 0)),
        .slot_req_valid(moe_slot_req_valid_r),
        .slot_req_kind(moe_slot_req_kind_r),
        .slot_owner_rank(moe_slot_owner_rank_r),
        .slot_global_seq(moe_slot_global_seq_r),
        .slot_token_id(moe_slot_token_id_r),
        .slot_expected_bitmap(moe_slot_expected_bitmap_r),
        .init_valid(moe_dispatch_init_valid),
        .init_ready(moe_dispatch_init_ready),
        .init_owner_rank(moe_dispatch_init_owner_rank),
        .init_microbatch_id(moe_dispatch_init_microbatch_id),
        .init_global_seq(moe_dispatch_init_global_seq),
        .init_token_id(moe_dispatch_init_token_id),
        .init_expected_bitmap(moe_dispatch_init_expected_bitmap),
        .init_token_len(moe_dispatch_init_token_len),
        .init_chunk_count(moe_dispatch_init_chunk_count),
        .dispatch_accept(moe_dispatch_accept),
        .dispatch_drop_busy(moe_dispatch_drop_busy)
    );

    moe_combine_engine #(
        .NUM_OWNERS(2),
        .WINDOW_SIZE(MOE_WINDOW_SIZE),
        .PAYLOAD_WIDTH(512),
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
        .AXIS_KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .AXIS_TUSER_WIDTH(128),
        .ROCE_PAYLOAD_BYTES(1024),
        .USE_EXTERNAL_REDUCE(1)
    ) u_moe_combine_engine (
        .clk(clk),
        .rst_n(rst_n),

        .init_valid(moe_init_valid),
        .init_ready(moe_init_ready),
        .init_owner_rank(moe_init_owner_rank),
        .init_microbatch_id(moe_init_microbatch_id),
        .init_global_seq(moe_init_global_seq),
        .init_token_id(moe_init_token_id),
        .init_expected_bitmap(moe_selected_init_expected_bitmap),
        .init_token_len(moe_init_token_len),
        .init_chunk_count(moe_init_chunk_count),
        .init_accept(moe_init_accept),
        .init_drop_owner(moe_init_drop_owner),
        .init_drop_window(moe_init_drop_window),
        .init_drop_busy(moe_init_drop_busy),

        .data_valid(moe_data_valid),
        .data_ready(moe_data_ready),
        .data_owner_rank(moe_data_owner_rank),
        .data_microbatch_id(16'h0000),
        .data_global_seq(moe_data_global_seq),
        .data_token_id(moe_data_token_id),
        .data_expert_id(moe_data_expert_id[5:0]),
        .data_chunk_id(8'd0),
        .data_payload(moe_data_payload),
        .data_accept(moe_data_accept),
        .data_drop_owner(moe_data_drop_owner),
        .data_drop_no_entry(moe_data_drop_no_entry),
        .data_drop_unexpected(moe_data_drop_unexpected),
        .data_drop_duplicate(moe_data_drop_duplicate),
        .external_reduce_update_valid(moe_core_aggregate_update_valid),
        .external_reduce_update_ready(moe_core_aggregate_update_ready),
        .external_reduce_update_addr(moe_engine_aggregate_update_addr),
        .external_reduce_update_data(moe_core_aggregate_update_data),
        .external_reduce_update_done(moe_core_aggregate_update_done),
        .external_reduce_update_sum(moe_core_aggregate_update_sum),
        .external_reduce_query_valid(moe_core_aggregate_query_valid),
        .external_reduce_query_ready(moe_core_aggregate_query_ready),
        .external_reduce_query_addr(moe_engine_aggregate_query_addr),
        .external_reduce_query_done(moe_core_aggregate_query_done),
        .external_reduce_query_data(moe_core_aggregate_query_data),
        .external_arrival_update_valid(moe_core_arrival_update_valid),
        .external_arrival_update_ready(moe_core_arrival_update_ready),
        .external_arrival_update_addr(moe_engine_arrival_update_addr),
        .external_arrival_update_lane_id(moe_core_arrival_update_lane_id),
        .external_arrival_update_done(moe_core_arrival_update_done),

        .cfg_fpga_mac(cfg_my_mac_p0),
        .cfg_fpga_ip(cfg_my_ip_p0),
        .cfg_fpga_udp_port(cfg_my_port_p0),
        .cfg_owner0_mac(cfg_peer_mac_p0),
        .cfg_owner0_ip(cfg_peer_ip_p0),
        .cfg_owner0_qp(cfg_peer_qp_p0),
        .cfg_owner0_udp_port(cfg_peer_port_p0),
        .cfg_owner1_mac(cfg_peer_mac_p1),
        .cfg_owner1_ip(cfg_peer_ip_p1),
        .cfg_owner1_qp(cfg_peer_qp_p1),
        .cfg_owner1_udp_port(cfg_peer_port_p1),
        .cfg_owner_port_mask_flat(16'h0201),
        .cfg_result_psn(moe_result_psn + 32'd1),

        .m_axis_tdata(moe_m_axis_tdata),
        .m_axis_tkeep(moe_m_axis_tkeep),
        .m_axis_tuser(moe_m_axis_tuser),
        .m_axis_tvalid(moe_m_axis_tvalid),
        .m_axis_tlast(moe_m_axis_tlast),
        .m_axis_tready(moe_m_axis_tready),

        .release_accept(moe_release_accept),
        .release_drop_owner(moe_release_drop_owner),
        .release_drop_no_entry(moe_release_drop_no_entry),
        .release_drop_busy(moe_release_drop_busy),
        .dbg_owner_head_seq_flat()
    );

    moe_dispatch_egress_builder #(
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
        .AXIS_KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .AXIS_TUSER_WIDTH(128),
        .NUM_EXPERTS(2),
        .PAYLOAD_WIDTH(512),
        .ROCE_PAYLOAD_BYTES(1024)
    ) u_moe_dispatch_egress_builder (
        .clk(clk),
        .rst_n(rst_n),

        .dispatch_valid(moe_dispatch_egress_valid),
        .dispatch_ready(moe_dispatch_egress_ready),
        .dispatch_owner_rank(moe_dispatch_owner_rank_pending),
        .dispatch_global_seq(moe_dispatch_global_seq_pending),
        .dispatch_expert_bitmap({56'd0, moe_dispatch_expert_bitmap_pending}),
        .dispatch_payload_data(moe_dispatch_payload_data_r),

        .cfg_fpga_mac(cfg_my_mac_p0),
        .cfg_fpga_ip(cfg_my_ip_p0),
        .cfg_fpga_udp_port(cfg_my_port_p0),
        .cfg_expert0_mac(cfg_peer_mac_p0),
        .cfg_expert0_ip(cfg_peer_ip_p0),
        .cfg_expert0_qp(cfg_peer_qp_p0),
        .cfg_expert0_udp_port(cfg_peer_port_p0),
        .cfg_expert1_mac(cfg_peer_mac_p1),
        .cfg_expert1_ip(cfg_peer_ip_p1),
        .cfg_expert1_qp(cfg_peer_qp_p1),
        .cfg_expert1_udp_port(cfg_peer_port_p1),
        .cfg_expert_port_mask_flat(MOE_EXPERT_PORT_MASK_FLAT),
        .cfg_dispatch_psn(moe_dispatch_psn_pending + 32'd1),

        .m_axis_tdata(moe_dispatch_m_axis_tdata),
        .m_axis_tkeep(moe_dispatch_m_axis_tkeep),
        .m_axis_tuser(moe_dispatch_m_axis_tuser),
        .m_axis_tvalid(moe_dispatch_m_axis_tvalid),
        .m_axis_tlast(moe_dispatch_m_axis_tlast),
        .m_axis_tready(moe_dispatch_m_axis_tready)
    );

    assign m_axis_tdata = select_combine_output ? moe_m_axis_tdata :
                          (select_dispatch_output ? moe_dispatch_m_axis_tdata :
                           deparser_m_axis_tdata);
    assign m_axis_tkeep = select_combine_output ? moe_m_axis_tkeep :
                          (select_dispatch_output ? moe_dispatch_m_axis_tkeep :
                           deparser_m_axis_tkeep);
    assign m_axis_tuser = select_combine_output ? moe_m_axis_tuser :
                          (select_dispatch_output ? moe_dispatch_m_axis_tuser :
                           128'd0);
    assign m_axis_tvalid = select_combine_output ? moe_m_axis_tvalid :
                           (select_dispatch_output ? moe_dispatch_m_axis_tvalid :
                            deparser_m_axis_tvalid);
    assign m_axis_tlast = select_combine_output ? moe_m_axis_tlast :
                          (select_dispatch_output ? moe_dispatch_m_axis_tlast :
                           deparser_m_axis_tlast);
    assign m_axis_is_aggregated = moe_output_selected ? 1'b1 : deparser_m_axis_is_aggregated;
    assign m_axis_route_type = moe_output_selected ? 3'd2 : deparser_m_axis_route_type;
    assign m_axis_agg_ingress_port = moe_output_selected ?
                                     port_mask_to_binary(m_axis_tuser[31:24]) :
                                     deparser_m_axis_agg_ingress_port;


//     //----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG

//     clk_wiz_0 instance_name
//    (
//     // Clock out ports
//     .clk_out1(clk),     // output clk_out1//250M
//     // Status and control signals
//     .reset(pll_reset), // input reset
//     .locked(pll_locked),       // output locked
//    // Clock in ports
//     .clk_in1(sys_clk_90m)      // input clk_in1
//     );

//     // INST_TAG_END ------ End INSTANTIATION Template ---------


// ============================================================
// ILA probes (系统化诊断版, 17 probe, 共 197 bit)
// 保留原 11 probe 不改位宽, 新增 6 路定位 latched_route_type=0 根因.
//
//  probe | 位宽 | 信号                                  | 诊断目标
//  ------|------|--------------------------------------|----------------------------
//   0    |   8  | ingress_port                         | 包入口, 区分 Port0/1
//   1    |   1  | FAN_first_trans_en  (主触发)          | ILA trigger
//   2    |   1  | agg_payload_fire_en                  | parser 写 BRAM 完成脉冲
//   3    |   1  | m_axis_tvalid                        | deparser 17 拍输出
//   4    |   1  | m_axis_tlast                         | 包末
//   5    |   3  | m_axis_route_type                    | =1 即 ROUTE_TO_PARENT
//   6    |  32  | {s3_valid, hash_hit, endpoint_match, send_only,
//                  opcode, dst_mac_lsb, dst_ip_lsb, 4'b0}
//   7    |  32  | {8'h00, parsed_dst_qpn[23:0]}
//   8    |  32  | deparser.constructed_header[31:0]
//   9    |  32  | m_axis_tdata[31:0]                   | [环节4] 最终 FF 输出低 32
//  10    |  32  | m_axis_tdata[63:32]
// --- 第二批 (定位 route_type=0) ---
//  11    |   3  | deparser.current_state               | FAN 那拍 FSM 在哪
//                                                        IDLE=0 / PASS_THROUGH=1 /
//                                                        GEN_HEADER=2 / GEN_PAYLOAD=3
//  12    |   1  | header_v[from_agg_metadata_in[15:8]] | agg 读的 slot 是否有效
//  13    |   8  | from_agg_metadata_in[15:8]           | agg 侧 slot 号
//  14    |   8  | metadata_slot_r                      | parser 侧 slot 号
//  15    |   1  | parser s3_valid                      | parser 已收到完整头部
//  16    |   1  | agg_req_valid                        | deparser 看到的 agg 请求 OR
//
// 判定矩阵 (trigger = probe1==R, 抓 FAN 那拍):
//  probe11 != 0                         => FSM 被 pass_through/gen 抢占
//  probe11 == 0 && probe12 == 0
//                   && probe13 != probe14 => slot 错位 (aggregator 改了 metadata)
//                   && probe13 == probe14 => parser 还没写 header_v, 时序问题
//                                           (再看 probe15 近 N 拍是否 pulse 过)
//  probe11 == 0 && probe12 == 1 && probe5 仍为 0
//                                       => latched 赋值 block 被其他原因 gate
// ============================================================
(* DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg [7:0]  ila_ingress_port;
(* DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg        ila_FAN_trans;
(* DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg        ila_agg_fire_payload_en;
(* DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg        ila_m_axis_tvalid;
(* DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg        ila_m_axis_tlast;
(* DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg [2:0]  ila_m_axis_route_type;
(* DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg [31:0] ila_parser_peer_mac_lo;
(* DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg [31:0] ila_dep_header_for_pkt_lo;
(* DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg [31:0] ila_dep_constructed_lo;
(* DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg [31:0] ila_m_axis_tdata_lo;
(* DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg [31:0] ila_m_axis_tdata_hi;
(* DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg [2:0]  ila_dep_current_state;
(* DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg        ila_dep_header_v_at_agg_slot;
(* DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg [7:0]  ila_dep_from_agg_slot;
(* DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg [7:0]  ila_dep_parser_slot_r;
(* DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg        ila_dep_header_valid_r;
(* DONT_TOUCH = "TRUE", MARK_DEBUG = "TRUE" *) reg        ila_dep_agg_req_valid;

always @(posedge clk) begin
    ila_ingress_port             <= ingress_port;
    ila_FAN_trans                <= aggregator_to_deparser_FAN_first_trans_en_out;
    ila_agg_fire_payload_en      <= parser_to_aggregator_agg_payload_fire_en;
    ila_m_axis_tvalid            <= m_axis_tvalid;
    ila_m_axis_tlast             <= m_axis_tlast;
    ila_m_axis_route_type        <= m_axis_route_type;
    ila_parser_peer_mac_lo       <= {parser_dbg_s3_valid,
                                     parser_dbg_lookup_hit,
                                     parser_dbg_endpoint_match,
                                     parser_dbg_send_only_match,
                                     parser_dbg_opcode,
                                     parser_dbg_s1_peer_mac_lsb,
                                     parser_dbg_s1_peer_ip_lsb,
                                     4'b0000};
    ila_dep_header_for_pkt_lo    <= {8'h00, parser_dbg_qpn};
    ila_dep_constructed_lo       <= deparser_dbg_constructed_header_lo;
    ila_m_axis_tdata_lo          <= m_axis_tdata[31:0];
    ila_m_axis_tdata_hi          <= m_axis_tdata[63:32];
    ila_dep_current_state        <= deparser_dbg_current_state;
    ila_dep_header_v_at_agg_slot <= deparser_dbg_header_v_at_agg_slot;
    ila_dep_from_agg_slot        <= deparser_dbg_from_agg_slot;
    ila_dep_parser_slot_r        <= deparser_dbg_parser_slot_r;
    ila_dep_header_valid_r       <= parser_dbg_s3_valid;
    ila_dep_agg_req_valid        <= deparser_dbg_agg_req_valid;
end

ila_0 ila_allreduce (
    .clk(clk),
    .probe0 (ila_ingress_port),
    .probe1 (ila_FAN_trans),
    .probe2 (ila_agg_fire_payload_en),
    .probe3 (ila_m_axis_tvalid),
    .probe4 (ila_m_axis_tlast),
    .probe5 (ila_m_axis_route_type),
    .probe6 (ila_parser_peer_mac_lo),
    .probe7 (ila_dep_header_for_pkt_lo),
    .probe8 (ila_dep_constructed_lo),
    .probe9 (ila_m_axis_tdata_lo),
    .probe10(ila_m_axis_tdata_hi),
    .probe11(ila_dep_current_state),
    .probe12(ila_dep_header_v_at_agg_slot),
    .probe13(ila_dep_from_agg_slot),
    .probe14(ila_dep_parser_slot_r),
    .probe15(ila_dep_header_valid_r),
    .probe16(ila_dep_agg_req_valid)
);



endmodule
