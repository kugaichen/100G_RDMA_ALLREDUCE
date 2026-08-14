`timescale 1ns / 1ps
`include "moe_defs.vh"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/09/04 17:32:09
// Design Name: 
// Module Name: parser
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


module parser #(

    parameter AXIS_DATA_WIDTH    = 512,
    parameter AXIS_KEEP_WIDTH    = AXIS_DATA_WIDTH / 8,
    parameter ORIGIN_HDR_LEN     = 54*8,

    // Hash Table
    parameter HASH_KEY_WIDTH     = 160,
    parameter HASH_DATA_WIDTH    = 9,

    // HEADER / METADATA
    parameter PKT_HDR_LEN        = (2*6+4*4+3*2+1) * 8,
    parameter METADATA_LEN       = 2*8+3+5,
    
    // PAYLOAD
    parameter PAYLOAD_WIDTH      = 1024*8,
    parameter PAYLOAD_ITEM_NUM   = 16,
    parameter PAYLOAD_ITEM_WIDTH = AXIS_DATA_WIDTH,
    parameter PAYLOAD_BEATS      = PAYLOAD_WIDTH / AXIS_DATA_WIDTH,
    parameter PAYLOAD_ITEM_COUNT_WIDTH = $clog2(PAYLOAD_ITEM_NUM),

    // WIDTH
    parameter MAC_ADDR_WIDTH = 48,
    parameter IP_ADDR_WIDTH = 32,
    parameter PSN_WIDTH = 32,
    parameter PORT_WIDTH = 16,
    parameter IP_START = 26,
    parameter BTH_START = 42,
    parameter OPCODE_WIDTH = 8,
    parameter QPN_START = 46,
    parameter QPN_LEN = 32,

    // BUFFER
    parameter WINDOWSIZE = 8,
    parameter BUFFER_SLOTS = 16,
    parameter RING_SLOT_WIDTH = 8,

    parameter FIFO_DEPTH = 32,

    parameter RAM_SLOT_WIDTH = 8,
    parameter MOE_DESC_WIDTH = `MOE_DESC_WIDTH
    
)(
    input wire                          axis_clk,
    input wire                          rst_n,

    // input slvae axi stream
    input wire [AXIS_DATA_WIDTH-1:0]    axis_in_data,
    input wire [AXIS_KEEP_WIDTH-1:0]    axis_tkeep,
    input wire                          axis_tvalid,
    input wire                          axis_tlast,
    output wire                         in_ready,   //反压
    input wire [7:0]                    ingress_port,

    // output
    // For packets that do not need aggregating 
    output reg                          pkt_valid_out,
    output reg  [AXIS_DATA_WIDTH-1:0]   pkt_data_out,
    output reg  [AXIS_KEEP_WIDTH-1:0]   pkt_keep_out,
    output reg                          pkt_last_out,
    input  wire                         pkt_ready_in,

    // For packets that do need aggregating 
    output reg                          agg_header_valid,
    output reg  [PKT_HDR_LEN-1:0]       agg_header_out,
    output reg  [METADATA_LEN-1:0]      agg_metadata_out,
    output reg  [OPCODE_WIDTH-1:0]      agg_opcode_out,
    output reg                          agg_payload_fire_en,
    input wire                          agg_ready_in,

    // Minimal RoCE endpoint identity. SEND_ONLY data and incoming ACK must
    // match these fields before entering the AllReduce protocol path.
    input wire [47:0]                   cfg_local_mac,
    input wire [31:0]                   cfg_local_ip,
    input wire [15:0]                   cfg_local_udp_port,
    input wire [23:0]                   cfg_local_qpn,
    input wire                          cfg_enable_moe,


    // --- BRAM 写命令输出端口 ---
    // 这些信号将控制外部的BRAM
    output reg [RING_SLOT_WIDTH+PAYLOAD_ITEM_COUNT_WIDTH-1:0]    payload_wr_addr,
    output reg [PAYLOAD_ITEM_WIDTH-1:0]     payload_wr_data,
    output reg                              payload_wr_en,
    output reg [METADATA_LEN-1:0]           latched_metadata_for_write,
    input wire                              payload_wr_ready,

    // ---- MoE Phase 1 descriptor sideband ----
    // This sideband is observational for now. It does not alter the existing
    // AllReduce aggregate/pass-through path until later phases consume it.
    output reg                              moe_desc_valid,
    output reg [7:0]                        moe_desc_op_type,
    output reg [MOE_DESC_WIDTH-1:0]         moe_desc_out,
    output reg                              moe_payload_valid,
    output reg [7:0]                        moe_payload_op_type,
    output reg [PAYLOAD_ITEM_WIDTH-1:0]     moe_payload_data,

    // ---- DEBUG 用: parser stage1 抽出的 peer_mac/peer_ip 最低字节 ----
    // 上板时若 hash 常 miss, 需要判断 CMAC 送进来的 AXIS 字节序与 parser
    // 预期是否一致。s1 是第一级从 header_buffer 抽字段, 看低字节即可区分:
    //   test2 期望 dst_mac=aa:bb:cc:44:55:66, dst_ip=10.0.2.34 (=0x0A000222)
    //   若 parser 解对 (与 tb 字节序一致) -> peer_mac[7:0]=0x66, peer_ip[7:0]=0x22
    //   若 CMAC 是 network-order 反过来  -> peer_mac[7:0]=0xAA, peer_ip[7:0]=0x0A
    output wire [7:0]                       dbg_s1_peer_mac_lsb,
    output wire [7:0]                       dbg_s1_peer_ip_lsb,
    output wire                             dbg_s3_valid,
    output wire                             dbg_lookup_hit,
    output wire                             dbg_endpoint_match,
    output wire                             dbg_send_only_match,
    output wire                             dbg_moe_prefix_match,
    output wire [7:0]                       dbg_opcode,
    output wire [23:0]                      dbg_qpn,

    // AETH 字段输出 (仅 opcode==0x11 时有效, 用于 deparser ACK 重构真值透传)
    output reg [7:0]                        agg_aeth_syndrome_out,
    output reg [23:0]                       agg_aeth_msn_out
);      

    // ===================================
    // 1-----before parse -> fifo control
    // ===================================

    // Input 
    wire                                fifo_wr_en = axis_tvalid && in_ready;
    wire                                fifo_rd_en;
    wire [AXIS_DATA_WIDTH-1:0]          fifo_data_out;
    wire [AXIS_KEEP_WIDTH-1:0]          fifo_keep_out;
    wire                                fifo_lout;
    wire                                fifo_dout_valid;
    wire                                fifo_full;
    wire                                fifo_empty;

    // ====================================
    // 2------Hash Connection Table
    // ====================================

    // hash_connection_table create
    // localparam HASH_KEY_WIDTH  = 160;
    // localparam HASH_DATA_WIDTH = 1;

    wire [HASH_KEY_WIDTH-1:0]           lookup_key;
    wire                                lookup_hit;
    wire [HASH_DATA_WIDTH-1:0]          lookup_data;

    reg                                 expecting_new_header;

    fifo_sync #(
        .DATA_WIDTH(AXIS_DATA_WIDTH),
        .KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) pkt_fifo (
        .clk(axis_clk),
        .rst_n(rst_n),
        .wr_en(fifo_wr_en),
        .din(axis_in_data),
        .kin(axis_tkeep),
        .lin(axis_tlast),
        .full(fifo_full),
        .rd_en(fifo_rd_en),
        .dout(fifo_data_out),
        .kout(fifo_keep_out),
        .lout(fifo_lout),
        .dout_valid(fifo_dout_valid),
        .empty(fifo_empty)
    );

    assign in_ready = !fifo_full;


    // ====================================
    // 3------pkt into pipeline 
    // ====================================

    reg [AXIS_DATA_WIDTH-1:0]           header_buffer;
    reg                                 header_ready;
    wire [AXIS_DATA_WIDTH-1:0]          header_buffer_holdfix;
    wire                                header_ready_holdfix;
    genvar                              header_buffer_holdfix_i;

    // Keep the original pipeline latency, but add a tiny buffer stage on the
    // fanout-heavy header handoff so the FF->FF min paths are no longer near-zero.
    generate
        for (header_buffer_holdfix_i = 0; header_buffer_holdfix_i < AXIS_DATA_WIDTH; header_buffer_holdfix_i = header_buffer_holdfix_i + 1) begin : gen_header_buffer_holdfix
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) u_lut1_header_buffer_holdfix (
                .I0(header_buffer[header_buffer_holdfix_i]),
                .O(header_buffer_holdfix[header_buffer_holdfix_i])
            );
        end
    endgenerate

    (* DONT_TOUCH = "TRUE" *) LUT1 #(
        .INIT(2'b10)
    ) u_lut1_header_ready_holdfix (
        .I0(header_ready),
        .O(header_ready_holdfix)
    );

    // [修正] 合并为一个标准的时序逻辑块
    always @(posedge axis_clk or negedge rst_n) begin
        if (!rst_n) begin
            header_ready <= 1'b0;
            header_buffer <= 0;
            expecting_new_header <= 1'b1;
        end
        else begin
            // 1. Header Ready 生成逻辑
            header_ready <= fifo_wr_en && (fifo_empty || expecting_new_header);

            // 2. Header Buffer 捕获逻辑
            if (fifo_wr_en) begin
                header_buffer <= axis_in_data;
            end

            // 3. 状态机跳转逻辑 (关键修复)
            if (fifo_wr_en) begin
                if (expecting_new_header) begin
                    // 当前是 Header
                    // 如果这也是最后一拍 (单拍包)，则下一次还是期待 Header
                    // 否则，下一次期待 Payload
                    if (axis_tlast) 
                        expecting_new_header <= 1'b1;
                    else 
                        expecting_new_header <= 1'b0;
                end
                else begin
                    // 当前是 Payload
                    // 如果检测到 Last，说明包结束，下一次期待 Header
                    if (axis_tlast) begin
                        expecting_new_header <= 1'b1;
                    end
                end
            end
        end
    end

    
    // pipeline register
    // ----------------------------------------------
    // stage 1: extract
    reg                         s1_valid;
    reg [MAC_ADDR_WIDTH-1:0]    s1_src_mac;
    reg [MAC_ADDR_WIDTH-1:0]    s1_peer_mac;
    reg [IP_ADDR_WIDTH-1:0]     s1_src_ip;
    reg [IP_ADDR_WIDTH-1:0]     s1_peer_ip;
    reg [PORT_WIDTH-1:0]        s1_src_port;
    reg [PORT_WIDTH-1:0]        s1_peer_port;
    reg [7:0]                   s1_ingress_port;
    reg [15:0]                  s1_data_length;
    reg [AXIS_DATA_WIDTH-1:0]   s1_header_buffer;


    // stage 2: lookup connection_table and compare
    reg                         s2_valid;
    reg [15:0]                  s2_data_length;

    reg [AXIS_DATA_WIDTH-1:0]   s2_header_buffer;
    reg [MAC_ADDR_WIDTH-1:0]    s2_src_mac;
    reg [MAC_ADDR_WIDTH-1:0]    s2_peer_mac;
    reg [IP_ADDR_WIDTH-1:0]     s2_src_ip; 
    reg [IP_ADDR_WIDTH-1:0]     s2_peer_ip; 
    reg [PORT_WIDTH-1:0]        s2_src_port;
    reg [PORT_WIDTH-1:0]        s2_peer_port;
    reg [7:0]                   s2_ingress_port;

    // stage 3: wait hash result
    reg                         s3_valid;
    reg [15:0]                  s3_data_length;
    reg [MAC_ADDR_WIDTH-1:0]    s3_src_mac;
    reg [MAC_ADDR_WIDTH-1:0]    s3_peer_mac;
    reg [IP_ADDR_WIDTH-1:0]     s3_src_ip; 
    reg [IP_ADDR_WIDTH-1:0]     s3_peer_ip; 
    reg [PORT_WIDTH-1:0]        s3_src_port;
    reg [PORT_WIDTH-1:0]        s3_peer_port;
    reg [7:0]                   s3_ingress_port;
    reg [AXIS_DATA_WIDTH-1:0]   s3_header_buffer;

    // stage 4: bth extract
    reg                         s4_valid;
    reg [7:0]                   s4_opcode;
    reg [31:0]                  s4_qpn;
    reg [PSN_WIDTH-1:0]         s4_apsn;
    // reg [7:0]                   s4_psn_out;
    reg [RAM_SLOT_WIDTH-1:0]       s4_psn_out;


    reg [15:0]                  s4_data_len_out;
    reg                         s4_lookup_hit;
    reg [HASH_DATA_WIDTH-1:0]   s4_lookup_data;
    reg                         s4_root_info;
    reg [MAC_ADDR_WIDTH-1:0]    s4_src_mac;
    reg [MAC_ADDR_WIDTH-1:0]    s4_peer_mac;
    reg [IP_ADDR_WIDTH-1:0]     s4_src_ip; 
    reg [IP_ADDR_WIDTH-1:0]     s4_peer_ip; 
    reg [PORT_WIDTH-1:0]        s4_src_port;
    reg [PORT_WIDTH-1:0]        s4_peer_port;
    reg [7:0]                   s4_ingress_port;

    reg [7:0]                   s4_aeth_syndrome;
    reg [23:0]                  s4_aeth_msn;

    reg                         s4_egress_en;
    reg                         s4_aggregate_en;
    reg                         s4_moe_consume_en;
    reg [7:0]                   s4_moe_op_type;
    reg [35*8-1:0]              s4_header_out;
    reg [METADATA_LEN-1:0]      s4_metadata_out;
    
    localparam PIPE_COPY_BUS_WIDTH = AXIS_DATA_WIDTH + 8 + 16 +
                                     (2 * PORT_WIDTH) + (2 * IP_ADDR_WIDTH) +
                                     (2 * MAC_ADDR_WIDTH);

    wire [PIPE_COPY_BUS_WIDTH-1:0] s1_stage_bus;
    wire [PIPE_COPY_BUS_WIDTH-1:0] s1_stage_bus_holdfix;
    wire                           s1_valid_holdfix;
    genvar                         s1_stage_holdfix_i;

    wire [PIPE_COPY_BUS_WIDTH-1:0] s2_stage_bus;
    wire [PIPE_COPY_BUS_WIDTH-1:0] s2_stage_bus_holdfix;
    wire                           s2_valid_holdfix;
    genvar                         s2_stage_holdfix_i;

    wire [PIPE_COPY_BUS_WIDTH-1:0] s3_stage_bus;
    wire [PIPE_COPY_BUS_WIDTH-1:0] s3_stage_bus_holdfix;
    wire                           s3_valid_holdfix;
    genvar                         s3_stage_holdfix_i;

    wire [AXIS_DATA_WIDTH-1:0]     s3_header_buffer_holdfix;
    wire [7:0]                     s3_ingress_port_holdfix;
    wire [15:0]                    s3_data_length_holdfix;
    wire [PORT_WIDTH-1:0]          s3_peer_port_holdfix;
    wire [PORT_WIDTH-1:0]          s3_src_port_holdfix;
    wire [IP_ADDR_WIDTH-1:0]       s3_peer_ip_holdfix;
    wire [IP_ADDR_WIDTH-1:0]       s3_src_ip_holdfix;
    wire [MAC_ADDR_WIDTH-1:0]      s3_peer_mac_holdfix;
    wire [MAC_ADDR_WIDTH-1:0]      s3_src_mac_holdfix;

    wire [HASH_KEY_WIDTH-1:0]      lookup_key_holdfix;
    wire [HASH_DATA_WIDTH-1:0]     lookup_data_holdfix;
    wire                           lookup_hit_holdfix;
    genvar                         lookup_key_holdfix_i;
    genvar                         lookup_data_holdfix_i;

    assign s1_stage_bus = {s1_header_buffer, s1_ingress_port, s1_data_length,
                           s1_peer_port, s1_src_port, s1_peer_ip, s1_src_ip,
                           s1_peer_mac, s1_src_mac};

    assign s2_stage_bus = {s2_header_buffer, s2_ingress_port, s2_data_length,
                           s2_peer_port, s2_src_port, s2_peer_ip, s2_src_ip,
                           s2_peer_mac, s2_src_mac};

    assign s3_stage_bus = {s3_header_buffer, s3_ingress_port, s3_data_length,
                           s3_peer_port, s3_src_port, s3_peer_ip, s3_src_ip,
                           s3_peer_mac, s3_src_mac};

    assign {s3_header_buffer_holdfix, s3_ingress_port_holdfix, s3_data_length_holdfix,
            s3_peer_port_holdfix, s3_src_port_holdfix, s3_peer_ip_holdfix, s3_src_ip_holdfix,
            s3_peer_mac_holdfix, s3_src_mac_holdfix} = s3_stage_bus_holdfix;

    // Add a tiny combinational buffer on the pure register-copy buses so the
    // repeated stage handoff paths are not effectively zero-delay.
    generate
        for (s1_stage_holdfix_i = 0; s1_stage_holdfix_i < PIPE_COPY_BUS_WIDTH; s1_stage_holdfix_i = s1_stage_holdfix_i + 1) begin : gen_s1_stage_holdfix
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) u_lut1_s1_stage_holdfix (
                .I0(s1_stage_bus[s1_stage_holdfix_i]),
                .O(s1_stage_bus_holdfix[s1_stage_holdfix_i])
            );
        end

        for (s2_stage_holdfix_i = 0; s2_stage_holdfix_i < PIPE_COPY_BUS_WIDTH; s2_stage_holdfix_i = s2_stage_holdfix_i + 1) begin : gen_s2_stage_holdfix
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) u_lut1_s2_stage_holdfix (
                .I0(s2_stage_bus[s2_stage_holdfix_i]),
                .O(s2_stage_bus_holdfix[s2_stage_holdfix_i])
            );
        end

        for (s3_stage_holdfix_i = 0; s3_stage_holdfix_i < PIPE_COPY_BUS_WIDTH; s3_stage_holdfix_i = s3_stage_holdfix_i + 1) begin : gen_s3_stage_holdfix
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) u_lut1_s3_stage_holdfix (
                .I0(s3_stage_bus[s3_stage_holdfix_i]),
                .O(s3_stage_bus_holdfix[s3_stage_holdfix_i])
            );
        end

        for (lookup_key_holdfix_i = 0; lookup_key_holdfix_i < HASH_KEY_WIDTH; lookup_key_holdfix_i = lookup_key_holdfix_i + 1) begin : gen_lookup_key_holdfix
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) u_lut1_lookup_key_holdfix (
                .I0(lookup_key[lookup_key_holdfix_i]),
                .O(lookup_key_holdfix[lookup_key_holdfix_i])
            );
        end

        for (lookup_data_holdfix_i = 0; lookup_data_holdfix_i < HASH_DATA_WIDTH; lookup_data_holdfix_i = lookup_data_holdfix_i + 1) begin : gen_lookup_data_holdfix
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) u_lut1_lookup_data_holdfix (
                .I0(lookup_data[lookup_data_holdfix_i]),
                .O(lookup_data_holdfix[lookup_data_holdfix_i])
            );
        end
    endgenerate

    (* DONT_TOUCH = "TRUE" *) LUT1 #(
        .INIT(2'b10)
    ) u_lut1_s1_valid_holdfix (
        .I0(s1_valid),
        .O(s1_valid_holdfix)
    );

    (* DONT_TOUCH = "TRUE" *) LUT1 #(
        .INIT(2'b10)
    ) u_lut1_s2_valid_holdfix (
        .I0(s2_valid),
        .O(s2_valid_holdfix)
    );

    (* DONT_TOUCH = "TRUE" *) LUT1 #(
        .INIT(2'b10)
    ) u_lut1_s3_valid_holdfix (
        .I0(s3_valid),
        .O(s3_valid_holdfix)
    );

    (* DONT_TOUCH = "TRUE" *) LUT1 #(
        .INIT(2'b10)
    ) u_lut1_lookup_hit_holdfix (
        .I0(lookup_hit),
        .O(lookup_hit_holdfix)
    );


    // 解决时序的情况 在s4_header_out中加入LUT去Buffer，增大路径
    wire [PKT_HDR_LEN-1:0] s4_header_out_holdfix;
    genvar hdr_holdfix_i;
    generate
        for (hdr_holdfix_i = 0; hdr_holdfix_i < PKT_HDR_LEN; hdr_holdfix_i = hdr_holdfix_i + 1) begin : gen_s4_header_holdfix
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) u_lut1_s4_header_holdfix (
                .I0(s4_header_out[hdr_holdfix_i]),
                .O(s4_header_out_holdfix[hdr_holdfix_i])
            );
        end
    endgenerate

    wire [METADATA_LEN-1:0] s4_metadata_out_holdfix;
    wire [OPCODE_WIDTH-1:0] s4_opcode_holdfix;
    genvar metadata_holdfix_i;
    genvar opcode_holdfix_i;
    generate
        for (metadata_holdfix_i = 0; metadata_holdfix_i < METADATA_LEN; metadata_holdfix_i = metadata_holdfix_i + 1) begin : gen_s4_metadata_holdfix
            
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) u_lut1_s4_metadata_holdfix (
                .I0(s4_metadata_out[metadata_holdfix_i]),
                .O(s4_metadata_out_holdfix[metadata_holdfix_i])
            );
        end

        for (opcode_holdfix_i = 0; opcode_holdfix_i < OPCODE_WIDTH; opcode_holdfix_i = opcode_holdfix_i + 1) begin : gen_s4_opcode_holdfix
            
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) u_lut1_s4_opcode_holdfix (
                .I0(s4_opcode[opcode_holdfix_i]),
                .O(s4_opcode_holdfix[opcode_holdfix_i])
            );
        end
    endgenerate



    wire [31:0] s3_apsn_raw;
    wire [31:0] s3_apsn_host;          // byte-swap 后的 host 视角 APSN
    wire [31:0] s3_qpn_host;           // byte-swap 后的 host 视角 QPN
    wire [RAM_SLOT_WIDTH-1:0]  s3_psn_mod_8b;

    // [原代码: 直接位段切, 是 byte-reversed 假整数]
    // assign s3_apsn_raw = s3_header_buffer_holdfix[(QPN_START*8) + (2*QPN_LEN) - 1 : (QPN_START*8) + QPN_LEN];

    // 1. 先提取出完整的 APSN 字段 (host 视角): wire byte 50~53 = host MSB..LSB
    assign s3_apsn_raw = s3_header_buffer_holdfix[(QPN_START*8) + (2*QPN_LEN) - 1 : (QPN_START*8) + QPN_LEN];
    assign s3_apsn_host = {s3_header_buffer_holdfix[(QPN_START*8)+QPN_LEN+ 7 : (QPN_START*8)+QPN_LEN+ 0],
                           s3_header_buffer_holdfix[(QPN_START*8)+QPN_LEN+15 : (QPN_START*8)+QPN_LEN+ 8],
                           s3_header_buffer_holdfix[(QPN_START*8)+QPN_LEN+23 : (QPN_START*8)+QPN_LEN+16],
                           s3_header_buffer_holdfix[(QPN_START*8)+QPN_LEN+31 : (QPN_START*8)+QPN_LEN+24]};
    assign s3_qpn_host  = {s3_header_buffer_holdfix[(QPN_START*8)+        7 : (QPN_START*8)+        0],
                           s3_header_buffer_holdfix[(QPN_START*8)+       15 : (QPN_START*8)+        8],
                           s3_header_buffer_holdfix[(QPN_START*8)+       23 : (QPN_START*8)+       16],
                           s3_header_buffer_holdfix[(QPN_START*8)+       31 : (QPN_START*8)+       24]};

    // Wire byte 23 is IPv4 Protocol. The BTH opcode is wire byte 42.
    // The six-field SEND_ONLY rule is kept separate from the ACK path:
    // both share endpoint identity checks, while only opcodes 0x04 and 0x11
    // are admitted to protocol processing.
    wire [7:0] s3_ip_protocol = s3_header_buffer_holdfix[191:184];
    wire [7:0] s3_opcode_wire =
        s3_header_buffer_holdfix[(BTH_START*8) + OPCODE_WIDTH - 1 : (BTH_START*8)];
    wire s3_endpoint_match =
        (s3_ip_protocol == 8'h11) &&
        (s3_peer_mac_holdfix == cfg_local_mac) &&
        (s3_peer_ip_holdfix == cfg_local_ip) &&
        (s3_peer_port_holdfix == cfg_local_udp_port) &&
        (s3_qpn_host[31:24] == 8'h00) &&
        (s3_qpn_host[23:0] == cfg_local_qpn);
    wire s3_send_only_match = s3_endpoint_match && (s3_opcode_wire == 8'h04);
    wire s3_ack_match       = s3_endpoint_match && (s3_opcode_wire == 8'h11);
    wire s3_protocol_match  = s3_send_only_match || s3_ack_match;

    // MoE base prefix lives at RoCE payload byte 0, i.e. packet wire byte 54.
    // The current prototype uses all 10 bytes visible in the cached first beat.
    wire [15:0] s3_moe_magic = {s3_header_buffer_holdfix[439:432],
                                s3_header_buffer_holdfix[447:440]};
    wire [7:0]  s3_moe_version = s3_header_buffer_holdfix[455:448];
    wire [7:0]  s3_moe_op_type = s3_header_buffer_holdfix[463:456];
    wire [7:0]  s3_moe_owner_rank = s3_header_buffer_holdfix[471:464];
    wire [7:0]  s3_moe_flags = s3_header_buffer_holdfix[479:472];
    wire [31:0] s3_moe_seq_low = {s3_header_buffer_holdfix[487:480],
                                  s3_header_buffer_holdfix[495:488],
                                  s3_header_buffer_holdfix[503:496],
                                  s3_header_buffer_holdfix[511:504]};
    wire s3_moe_op_known = (s3_moe_op_type == `MOE_OP_DISPATCH) ||
                           (s3_moe_op_type == `MOE_OP_COMBINE_INIT) ||
                           (s3_moe_op_type == `MOE_OP_COMBINE_DATA) ||
                           (s3_moe_op_type == `MOE_OP_COMBINE_RESULT);
    wire s3_moe_prefix_match = cfg_enable_moe && s3_send_only_match &&
                               (s3_moe_magic == `MOE_MAGIC) &&
                               (s3_moe_version == 8'h01) &&
                               s3_moe_op_known;

    // 2. 计算取模 (用 host 视角真整数)
    assign s3_psn_mod_8b = s3_apsn_host % BUFFER_SLOTS;


    assign lookup_key = {s1_peer_mac, s1_src_mac, s1_src_ip, s1_peer_ip};

    // DEBUG 引出: parser stage1 抽出的 peer_mac/peer_ip 最低字节, 用于上板确认字节序
    assign dbg_s1_peer_mac_lsb = s1_peer_mac[7:0];
    assign dbg_s1_peer_ip_lsb  = s1_peer_ip[7:0];
    assign dbg_s3_valid         = s3_valid_holdfix;
    assign dbg_lookup_hit       = lookup_hit_holdfix;
    assign dbg_endpoint_match   = s3_endpoint_match;
    assign dbg_send_only_match  = s3_send_only_match;
    assign dbg_moe_prefix_match = s3_valid_holdfix && lookup_hit_holdfix && s3_moe_prefix_match;
    assign dbg_opcode           = s3_opcode_wire;
    assign dbg_qpn              = s3_qpn_host[23:0];

    hash_connection_table #(
        .KEY_WIDTH(HASH_KEY_WIDTH),
        .DATA_WIDTH(HASH_DATA_WIDTH)
    )u_connection_table(
        .clk(axis_clk),
        .rst_n(rst_n),

        .read_key_valid(s1_valid_holdfix), 
        .read_key(lookup_key_holdfix),
        .lookup_hit(lookup_hit),
        .lookup_data(lookup_data),

        .write_en(1'b0),
        .write_key({HASH_KEY_WIDTH{1'b0}}),
        .write_data({HASH_DATA_WIDTH{1'b0}})
    );

    // ----------------------------------
    // pipeline - 1 : extract
    always @(posedge axis_clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 1'b0;
            s1_src_mac <= 0;
            s1_peer_mac <= 0;
            s1_src_ip <= 0;
            s1_peer_ip <= 0;
            s1_src_port <= 0;
            s1_peer_port <= 0;
            s1_data_length <= 0;
            s1_ingress_port <= 0;
            s1_header_buffer <= 0;
        end
        else begin
            s1_valid <= header_ready_holdfix;
            if (header_ready_holdfix) begin
                // ================================================================
                // [原代码: 直接位段切片, 得到的是 byte-reversed "假整数"]
                // 保留原代码注释作为对照, 字节序治本后由下方 byte-swap 版本替代.
                // ----------------------------------------------------------------
                // //eth
                // s1_peer_mac <= header_buffer_holdfix[MAC_ADDR_WIDTH-1 : 0];
                // s1_src_mac <= header_buffer_holdfix[(6*8)+MAC_ADDR_WIDTH-1 : MAC_ADDR_WIDTH];
                //
                // // ip
                // s1_src_ip <= header_buffer_holdfix[(IP_START*8) + IP_ADDR_WIDTH - 1 : (IP_START*8)];
                // s1_peer_ip <= header_buffer_holdfix[(IP_START*8) + (2*IP_ADDR_WIDTH) - 1 : (IP_START*8) + IP_ADDR_WIDTH];
                //
                // // udp
                // s1_src_port <= header_buffer_holdfix[(IP_START*8) + (2*IP_ADDR_WIDTH) + PORT_WIDTH - 1 : (IP_START*8) + (2*IP_ADDR_WIDTH)];
                // s1_peer_port <= header_buffer_holdfix[(IP_START*8) + (2*IP_ADDR_WIDTH) + (2*PORT_WIDTH) - 1 : (IP_START*8) + (2*IP_ADDR_WIDTH) + PORT_WIDTH];
                // s1_data_length <= header_buffer_holdfix[(IP_START*8) + (2*IP_ADDR_WIDTH) + (3*PORT_WIDTH) - 1 : (IP_START*8) + (2*IP_ADDR_WIDTH) + (2*PORT_WIDTH)];

                // ================================================================
                // 字节序治本: byte-swap 提取
                // ----------------------------------------------------------------
                // AXIS wire 字节序: byte 0 在 tdata LSB (header_buffer[7:0]).
                // 多字节字段直接位段切, 得到的是 byte-reversed "假整数". 这里
                // 全部翻转到 host 视角真实整数:
                //   host MSB <- wire byte 0 (header_buffer 最低字节)
                //   host LSB <- wire 最末字节 (header_buffer 最高字节)
                //
                // 影响: hash_connection_table 的 HIT_KEY 本就是 host 视角整数,
                //       上板和仿真 hash 都按真实值命中, 不再依赖"两次反转相消".
                //       data_length 同时把语义改成 "纯 payload 字节数",
                //       下游 deparser 直接 + IP/UDP/BTH header 长度即可.
                // ================================================================

                // eth: dst_mac (peer_mac) wire byte 0~5; src_mac wire byte 6~11
                s1_peer_mac <= {header_buffer_holdfix[ 7: 0],
                                header_buffer_holdfix[15: 8],
                                header_buffer_holdfix[23:16],
                                header_buffer_holdfix[31:24],
                                header_buffer_holdfix[39:32],
                                header_buffer_holdfix[47:40]};
                s1_src_mac  <= {header_buffer_holdfix[55:48],
                                header_buffer_holdfix[63:56],
                                header_buffer_holdfix[71:64],
                                header_buffer_holdfix[79:72],
                                header_buffer_holdfix[87:80],
                                header_buffer_holdfix[95:88]};

                // ip: src_ip wire byte 26~29 = IP header byte 12~15 (host MSB..LSB)
                //     peer_ip wire byte 30~33
                s1_src_ip   <= {header_buffer_holdfix[(IP_START*8)+ 7 : (IP_START*8)+ 0],
                                header_buffer_holdfix[(IP_START*8)+15 : (IP_START*8)+ 8],
                                header_buffer_holdfix[(IP_START*8)+23 : (IP_START*8)+16],
                                header_buffer_holdfix[(IP_START*8)+31 : (IP_START*8)+24]};
                s1_peer_ip  <= {header_buffer_holdfix[(IP_START*8)+39 : (IP_START*8)+32],
                                header_buffer_holdfix[(IP_START*8)+47 : (IP_START*8)+40],
                                header_buffer_holdfix[(IP_START*8)+55 : (IP_START*8)+48],
                                header_buffer_holdfix[(IP_START*8)+63 : (IP_START*8)+56]};

                // udp: src_port wire byte 34~35, dst_port wire byte 36~37
                s1_src_port  <= {header_buffer_holdfix[(IP_START*8)+71 : (IP_START*8)+64],
                                 header_buffer_holdfix[(IP_START*8)+79 : (IP_START*8)+72]};
                s1_peer_port <= {header_buffer_holdfix[(IP_START*8)+87 : (IP_START*8)+80],
                                 header_buffer_holdfix[(IP_START*8)+95 : (IP_START*8)+88]};

                // UDP length wire byte 38~39 (host MSB..LSB).
                // 语义改为"纯 payload 字节数" = UDP total - UDP header(8) - BTH(12) = UDP total - 20
                s1_data_length <= {header_buffer_holdfix[(IP_START*8)+103 : (IP_START*8)+ 96],
                                   header_buffer_holdfix[(IP_START*8)+111 : (IP_START*8)+104]}
                                  - 16'd24;

                s1_ingress_port <= ingress_port;
                s1_header_buffer <= header_buffer_holdfix;

            end
        end
    end


    // pipeline - 2 : lookup connection_table and compare
    always @(posedge axis_clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 1'b0;
            s2_data_length <= 0;
            s2_src_mac <= 0;
            s2_peer_mac <= 0;
            s2_src_ip <= 0;
            s2_peer_ip <= 0;
            s2_src_port <= 0;
            s2_peer_port <= 0;
            s2_ingress_port <= 0;
            s2_header_buffer <= 0;
        end
        else begin
            s2_valid <= s1_valid_holdfix;
            if (s1_valid_holdfix) begin
                {s2_header_buffer, s2_ingress_port, s2_data_length,
                 s2_peer_port, s2_src_port, s2_peer_ip, s2_src_ip,
                 s2_peer_mac, s2_src_mac} <= s1_stage_bus_holdfix;
            end
        end 
    end
    
    // pipeline - 3 : get hash result and extract
    always @(posedge axis_clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_valid <= 1'b0;
            s3_data_length <= 0;
            s3_src_mac <= 0;
            s3_peer_mac <= 0;
            s3_src_ip <= 0;
            s3_peer_ip <= 0;
            s3_src_port <= 0;
            s3_peer_port <= 0;
            s3_ingress_port <= 0;
            s3_header_buffer <= 0;
        end
        else begin
            s3_valid <= s2_valid_holdfix;

            if (s2_valid_holdfix) begin
                {s3_header_buffer, s3_ingress_port, s3_data_length,
                 s3_peer_port, s3_src_port, s3_peer_ip, s3_src_ip,
                 s3_peer_mac, s3_src_mac} <= s2_stage_bus_holdfix;

            end
        end         
    end

    // pipeline - 4 : get hash result and extract
    always @(posedge axis_clk or negedge rst_n) begin
        if (!rst_n) begin
            s4_valid <= 1'b0;
            s4_data_len_out <= 0;
            s4_src_mac <= 0;
            s4_peer_mac <= 0;
            s4_src_ip <= 0;
            s4_peer_ip <= 0;
            s4_src_port <= 0;
            s4_peer_port <= 0;
            s4_ingress_port <= 0;
            s4_lookup_data <= 0;
            s4_lookup_hit <= 0;
            s4_opcode <= 0;
            s4_qpn <= 0;
            s4_apsn <= 0;
            s4_psn_out <= 0;
            s4_root_info <= 0;

            s4_aggregate_en <= 0;
            s4_egress_en <= 0;
            s4_moe_consume_en <= 1'b0;
            s4_moe_op_type <= `MOE_OP_NONE;
            moe_desc_valid <= 1'b0;
            moe_desc_op_type <= `MOE_OP_NONE;
            moe_desc_out <= {MOE_DESC_WIDTH{1'b0}};
        end
        else begin
            s4_valid <= s3_valid_holdfix;
            agg_payload_fire_en <= 0;
            s4_egress_en <= 0;
            s4_aggregate_en <= 0;
            s4_moe_consume_en <= 1'b0;
            s4_moe_op_type <= `MOE_OP_NONE;
            moe_desc_valid <= 1'b0;
            moe_desc_op_type <= `MOE_OP_NONE;
            moe_desc_out <= {MOE_DESC_WIDTH{1'b0}};

            if (s3_valid_holdfix) begin
                s4_lookup_data <= lookup_data_holdfix;
                s4_lookup_hit <= lookup_hit_holdfix;

                s4_data_len_out <= s3_data_length_holdfix;
                s4_src_mac <= s3_src_mac_holdfix;
                s4_peer_mac <= s3_peer_mac_holdfix;
                s4_src_ip <= s3_src_ip_holdfix;
                s4_peer_ip <= s3_peer_ip_holdfix;
                s4_src_port <= s3_src_port_holdfix;
                s4_peer_port <= s3_peer_port_holdfix;
                s4_ingress_port <= s3_ingress_port_holdfix;

                if (lookup_hit_holdfix && s3_protocol_match) begin
                    // [原代码: BTH 字段直接位段切, 得到 byte-reversed 假整数]
                    // s4_opcode <= s3_header_buffer_holdfix[(BTH_START*8) + OPCODE_WIDTH - 1 : (BTH_START*8)];
                    // s4_qpn <= s3_header_buffer_holdfix[(QPN_START*8) + QPN_LEN - 1 : (QPN_START* 8)];
                    // s4_apsn <= s3_header_buffer_holdfix[(QPN_START*8) + (2*QPN_LEN) - 1 : (QPN_START*8) + QPN_LEN];
                    // s4_psn_out <= (s3_header_buffer_holdfix[(QPN_START*8) + (2*QPN_LEN) - 1 : (QPN_START*8) + QPN_LEN]) % BUFFER_SLOTS;

                    // 字节序治本: 用 s3_qpn_host/s3_apsn_host (byte-swap 后的真整数)
                    // opcode 是单字节 wire byte 42, 不存在字节序问题
                    s4_opcode <= s3_header_buffer_holdfix[(BTH_START*8) + OPCODE_WIDTH - 1 : (BTH_START*8)];
                    s4_qpn <= s3_qpn_host;
                    s4_apsn <= s3_apsn_host;
                    s4_psn_out <= s3_apsn_host % BUFFER_SLOTS;
                    s4_root_info <= lookup_data_holdfix[8];
                    s4_aggregate_en <= !s3_moe_prefix_match;
                    s4_moe_consume_en <= s3_moe_prefix_match;
                    s4_moe_op_type <= s3_moe_prefix_match ? s3_moe_op_type : `MOE_OP_NONE;

                    // AETH 提取 (wire byte 54-57, 仅 ACK 包有效)
                    s4_aeth_syndrome <= s3_header_buffer_holdfix[439:432];
                    s4_aeth_msn <= {s3_header_buffer_holdfix[447:440],
                                    s3_header_buffer_holdfix[455:448],
                                    s3_header_buffer_holdfix[463:456]};

                    // [原代码: header_out 里 qpn/apsn 也用 byte-reversed 位段]
                    // s4_header_out <= {s3_peer_mac_holdfix, s3_src_mac_holdfix, s3_peer_ip_holdfix, s3_src_ip_holdfix, s3_peer_port_holdfix, s3_src_port_holdfix, s3_data_length_holdfix,
                    //     s3_header_buffer_holdfix[(QPN_START*8) + QPN_LEN - 1 : (QPN_START* 8)], s3_header_buffer_holdfix[(QPN_START*8) + (2*QPN_LEN) - 1 : (QPN_START*8) + QPN_LEN],
                    //     s3_header_buffer_holdfix[(BTH_START*8) + OPCODE_WIDTH - 1 : (BTH_START*8)]};

                    // 字节序治本: header_out 全部用 host 视角, 下游 deparser 收到的都是真整数
                    s4_header_out <= {s3_peer_mac_holdfix, s3_src_mac_holdfix, s3_peer_ip_holdfix, s3_src_ip_holdfix,
                        s3_peer_port_holdfix, s3_src_port_holdfix, s3_data_length_holdfix,
                        s3_qpn_host, s3_apsn_host,
                        s3_header_buffer_holdfix[(BTH_START*8) + OPCODE_WIDTH - 1 : (BTH_START*8)]};

                    s4_metadata_out <= {
                        // 4'b0000,
                        {(12-RAM_SLOT_WIDTH){1'b0}},
                        3'b000,
                        lookup_data_holdfix[8],
                        s3_psn_mod_8b,
                        lookup_data_holdfix[7:0]
                    };
                    if (s3_moe_prefix_match) begin
                        moe_desc_valid <= 1'b1;
                        moe_desc_op_type <= s3_moe_op_type;
                        moe_desc_out <= {
                            s3_moe_magic,
                            s3_moe_version,
                            s3_moe_op_type,
                            s3_moe_owner_rank,
                            s3_moe_flags,
                            s3_moe_seq_low,
                            s3_apsn_host,
                            lookup_data_holdfix[7:0],
                            s3_psn_mod_8b[7:0]
                        };
                    end
                    agg_payload_fire_en <= !s3_moe_prefix_match;
                end
                else begin
                    s4_qpn <= {QPN_LEN{1'b0}};
                    s4_apsn <= {QPN_LEN{1'b0}};
                    s4_psn_out <= 8'b0;
                    s4_root_info <= 8'b0;
                    s4_egress_en <= 1;
                    s4_moe_consume_en <= 1'b0;
                    s4_moe_op_type <= `MOE_OP_NONE;
                    s4_opcode <= {OPCODE_WIDTH{1'b0}};
                    s4_header_out <= {PKT_HDR_LEN{1'b0}};
                    s4_metadata_out <= {METADATA_LEN{1'b0}};
                    agg_payload_fire_en <= 1'b0;
                end
            end
        end         
    end




    reg pass_through_next_state, pass_through_current_state;
    localparam PT_IDLE = 1'd0;
    localparam PT_STREAM = 1'd1;

    reg                     pending_egress_req;
    reg                     pending_aggregate_req;
    reg                     pending_moe_consume_req;
    reg [7:0]               pending_moe_op_type;
    reg [PKT_HDR_LEN-1:0]   latched_s4_header;
    reg [METADATA_LEN-1:0]  latched_s4_metadata;
    reg [OPCODE_WIDTH-1:0]  latched_s4_opcode;

    localparam SHIFTER_WIDTH    = AXIS_DATA_WIDTH;
    localparam PB_IDLE          = 1'b0;
    localparam PB_PROCESS       = 1'b1;
    reg payload_buffer_current_state, payload_buffer_next_state;
    wire pass_through_fifo_rd_en;
    wire payload_buffer_fifo_rd_en;

    // output
    always @(*) begin
        // if (s4_valid) begin
        //     agg_header_valid = s4_aggregate_en;
        //     agg_header_out = s4_header_out;
        //     agg_metadata_out = s4_metadata_out;
        //     agg_opcode_out = s4_opcode; 
        // end

        if (s4_valid && s4_aggregate_en) begin
            agg_header_valid = 1'b1;
            agg_header_out = s4_header_out;
            agg_metadata_out = s4_metadata_out;
            agg_opcode_out = s4_opcode;
            agg_aeth_syndrome_out = s4_aeth_syndrome;
            agg_aeth_msn_out = s4_aeth_msn;
        end

        else if (pending_aggregate_req) begin
            agg_header_valid = 1'b0;
            agg_header_out = latched_s4_header;
            agg_metadata_out = latched_s4_metadata;
            agg_opcode_out = latched_s4_opcode;
            agg_aeth_syndrome_out = 8'h00;
            agg_aeth_msn_out = 24'h000000;
        end

        else begin
            agg_header_valid = 0;
            agg_header_out = 0;
            agg_metadata_out = 0;
            agg_opcode_out = 0;
            agg_aeth_syndrome_out = 8'h00;
            agg_aeth_msn_out = 24'h000000;
        end
    end

    // -----------------------------------------------------------
 

    // ------------------------------------------------------------
    // [新增] 优化思路1：流水线信号锁存 (Pipeline Latch)
    // 解决问题：当状态机忙于处理前一个包时，s4_valid 脉冲到达并消失，导致漏包。
    // ------------------------------------------------------------



    wire req_consumed; // 消耗信号，当状态机开始处理新包时拉高
    wire effective_egress_req = (s4_valid && s4_egress_en) || pending_egress_req;

    wire agg_req_consumed;
    assign agg_req_consumed = (payload_buffer_next_state == PB_PROCESS) && (payload_buffer_current_state == PB_IDLE);

    wire effective_aggregate_req = (s4_valid && s4_aggregate_en) || pending_aggregate_req;
    wire effective_moe_consume_req = (s4_valid && s4_moe_consume_en) || pending_moe_consume_req;
    wire effective_payload_consume_req = effective_aggregate_req || effective_moe_consume_req;

    // Output & PAYLOAD Controller
    assign fifo_rd_en =  pass_through_fifo_rd_en || payload_buffer_fifo_rd_en;

    always @(posedge axis_clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_egress_req <= 1'b0;

            pending_aggregate_req <= 1'b0;
            pending_moe_consume_req <= 1'b0;
            pending_moe_op_type <= `MOE_OP_NONE;
            latched_s4_header   <= 0;
            latched_s4_metadata <= 0;
            latched_s4_opcode   <= 0;
        end

        else begin
            if (s4_valid && s4_egress_en && !req_consumed) begin
                pending_egress_req <= 1'b1;
            end

            else if (req_consumed) begin
                pending_egress_req <= 1'b0;
            end

            // s4_valid和s4_aggregate_en被置高了应该是要消耗一次aggregate信号，即状态切换到process阶段
            // 但是agg_req_consumed并未被消耗，因此需要锁存，pending置高
            if (s4_valid && s4_aggregate_en && !agg_req_consumed) begin
                pending_aggregate_req <= 1'b1;

                if (!pending_aggregate_req) begin
                    // latched_s4_header   <= s4_header_out;
                    latched_s4_header   <= s4_header_out_holdfix;
                    latched_s4_metadata <= s4_metadata_out_holdfix;
                    latched_s4_opcode   <= s4_opcode_holdfix;
                end
            end

            else if (agg_req_consumed) begin
                pending_aggregate_req <= 1'b0;
            end

            if (s4_valid && s4_moe_consume_en && !agg_req_consumed) begin
                pending_moe_consume_req <= 1'b1;
                pending_moe_op_type <= s4_moe_op_type;
            end

            else if (agg_req_consumed && pending_moe_consume_req && !pending_aggregate_req) begin
                pending_moe_consume_req <= 1'b0;
                pending_moe_op_type <= `MOE_OP_NONE;
            end
        end
    end


    //------------------------------------------------------ 
    //  PAYLOAD buffer for "Not Lookup-hit"
    //------------------------------------------------------
   
    // [修正] 显式展开握手条件：
    // 1. !pkt_valid_out: 当前输出寄存器为空，必须读新数据填补
    // 2. pkt_ready_in:   当前输出寄存器有数据，但下游已经收走了(握手成功)，必须读新数据填补
    wire output_handshake_done = pkt_valid_out && pkt_ready_in;
    wire output_is_empty       = !pkt_valid_out;
    wire can_read_fifo         = output_handshake_done || output_is_empty;

    // 读使能：状态机允许 && (输出空了 OR 输出了一个数据) && FIFO有数据
    assign pass_through_fifo_rd_en = (pass_through_next_state == PT_STREAM) && can_read_fifo && !fifo_empty;
    

    // ------------------------------------------------------------
    // 第一段：状态寄存器更新 (Sequential)
    // ------------------------------------------------------------
    always @(posedge axis_clk or negedge rst_n) begin
        if (!rst_n) begin
            pass_through_current_state <= PT_IDLE;
        end
        else begin
            pass_through_current_state <= pass_through_next_state;
        end
    end

    // ------------------------------------------------------------
    // 第二段：状态跳转逻辑 (Combinational)
    // [修改] 优化思路2：状态机逻辑优化，支持无缝切换
    // ------------------------------------------------------------
    assign req_consumed = (pass_through_next_state == PT_STREAM) && 
                          ((pass_through_current_state == PT_IDLE) || (pkt_last_out && pkt_valid_out && pkt_ready_in));

    always @( *) begin
        pass_through_next_state = pass_through_current_state;

        case (pass_through_current_state)
            PT_IDLE: begin
                // if (s4_egress_en && s4_valid) begin
                if (effective_egress_req && (payload_buffer_current_state == PB_IDLE) &&
                    !effective_moe_consume_req) begin        // 增加互斥
                    pass_through_next_state = PT_STREAM;
                end
            end

             PT_STREAM: begin
                // 退出条件：当前输出是最后一拍 (Last)，且 Valid 为高，且下游已握手 (Ready)
                // 这意味着最后一拍已经成功传输出去
                if (pkt_valid_out && pkt_ready_in && pkt_last_out) begin
                    if (effective_egress_req) begin
                        pass_through_next_state = PT_STREAM;
                    end
                    else begin
                        pass_through_next_state = PT_IDLE;        
                    end
                
                end
                else begin
                    pass_through_next_state = PT_STREAM;
                end
            end

            default: begin
                pass_through_next_state = PT_IDLE;
            end
        endcase
    end

    // ------------------------------------------------------------
    // 第三段：输出逻辑 (Sequential)
    // ------------------------------------------------------------
    always @(posedge axis_clk or negedge rst_n) begin
        if (!rst_n) begin
            pkt_valid_out <= 0;
            pkt_data_out <= 0;
            pkt_keep_out <= 0;
            pkt_last_out <= 0;
        end
        else begin
             // 只有当输出级“流动”时才更新寄存器
            // 1. 下游 Ready (pkt_ready_in=1): 数据被取走，需要填新数据
            // 2. 当前无效 (!pkt_valid_out): 气泡状态，可以填新数据
            if (can_read_fifo) begin
                
                // 默认拉低 Valid (如果下面条件不满足)
                pkt_valid_out <= 1'b0;

                case (pass_through_next_state)
                    PT_IDLE: begin
                        pkt_valid_out <= 1'b0;
                    end

                    PT_STREAM: begin
                        if (!fifo_empty) begin
                            pkt_valid_out <= 1'b1;
                            pkt_data_out  <= fifo_data_out;
                            pkt_keep_out  <= fifo_keep_out;
                            pkt_last_out  <= fifo_lout;
                        end
                    end
                endcase
            end
        end
    end





    // ----------------------------------------------
    // PAYLOAD buffer for "Lookup-hit"                          
    // ----------------------------------------------

    reg [SHIFTER_WIDTH-1:0]                                     shifter_container;
    reg [SHIFTER_WIDTH-1:0]                                     lefter_container;
    reg [RING_SLOT_WIDTH-1:0]                                   slot_addr;


    wire [RING_SLOT_WIDTH-1:0]              slot_addr_holdfix;
    genvar slot_addr_holdfix_i;
    generate
        for (slot_addr_holdfix_i = 0; slot_addr_holdfix_i < RING_SLOT_WIDTH; slot_addr_holdfix_i = slot_addr_holdfix_i + 1) begin : gen_slot_addr_holdfix
           
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) u_lut1_slot_addr_holdfix (
                .I0(slot_addr[slot_addr_holdfix_i]),
                .O(slot_addr_holdfix[slot_addr_holdfix_i])
            );
        end
    endgenerate

    
    reg                                                         is_first_beat;
    reg                                                         drop_payload_write;
    reg                                                         moe_payload_capture_en;
    reg [7:0]                                                   current_moe_payload_op_type;
    reg [$clog2(SHIFTER_WIDTH):0]                               remain_in_shift_container;            //在每一拍shift_container中未处理的数据
    reg [$clog2(AXIS_DATA_WIDTH):0]                             valid_in_axis_data;                   //每一拍中axis_data有效的字段长度
    reg [PAYLOAD_ITEM_COUNT_WIDTH:0]                            item_counter;                      //计算256个单元的offset
    reg                                                         shifter_fifo_lout;

    wire [PAYLOAD_ITEM_COUNT_WIDTH:0] item_counter_holdfix;
    genvar item_counter_holdfix_i;
    generate
        for (item_counter_holdfix_i = 0; item_counter_holdfix_i <= PAYLOAD_ITEM_COUNT_WIDTH; item_counter_holdfix_i = item_counter_holdfix_i + 1) begin : gen_item_counter_holdfix
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) u_lut1_item_counter_holdfix (
                .I0(item_counter[item_counter_holdfix_i]),
                .O(item_counter_holdfix[item_counter_holdfix_i])
            );
        end
    endgenerate

    assign payload_buffer_fifo_rd_en = (payload_buffer_next_state == PB_PROCESS);

    // 状态器更新
    always @(posedge axis_clk or negedge rst_n) begin
        if (!rst_n) begin
            payload_buffer_current_state <= PB_IDLE;
        end

        else begin
            payload_buffer_current_state <= payload_buffer_next_state;
        end
    end

    // 状态跳转逻辑
    always @( *) begin
        payload_buffer_next_state = payload_buffer_current_state;

        case (payload_buffer_current_state) 
            // PB_IDLE: begin
            //     if (s4_aggregate_en && s4_valid && agg_ready_in) begin
            //         payload_buffer_next_state = PB_PROCESS;
            //     end      
            // end

            PB_IDLE: begin
                if (effective_payload_consume_req && agg_ready_in && (pass_through_current_state == PT_IDLE)) begin
                    payload_buffer_next_state = PB_PROCESS;
                end
            end

            PB_PROCESS: begin
                if (shifter_fifo_lout) begin
                    payload_buffer_next_state = PB_IDLE;
                end
            end
        endcase
    end

    // 输出逻辑
    always @(posedge axis_clk or negedge rst_n) begin
        if (!rst_n) begin
            payload_wr_en <= 1'b0;
            payload_wr_addr <= 0;
            payload_wr_data <= 0;
            remain_in_shift_container <= 0;
            slot_addr <= 0;
            is_first_beat <= 0;
            item_counter <= 0;
            shifter_container <= 0;
            shifter_fifo_lout <= 0;
            latched_metadata_for_write <= 0;
            drop_payload_write <= 1'b0;
            moe_payload_capture_en <= 1'b0;
            current_moe_payload_op_type <= `MOE_OP_NONE;
            moe_payload_valid <= 1'b0;
            moe_payload_op_type <= `MOE_OP_NONE;
            moe_payload_data <= {PAYLOAD_ITEM_WIDTH{1'b0}};
        end

        else begin
            payload_wr_en <= 1'b0;
            moe_payload_valid <= 1'b0;

            case (payload_buffer_current_state)
                PB_IDLE: begin
                    if (payload_buffer_next_state == PB_PROCESS) begin
                        // 1. 锁存 Metadata
                        if (s4_valid && s4_aggregate_en) begin
                            slot_addr <= s4_metadata_out_holdfix[15:8];
                            latched_metadata_for_write <= s4_metadata_out_holdfix;
                            drop_payload_write <= 1'b0;
                        end
                        else if (pending_aggregate_req) begin
                            slot_addr <= latched_s4_metadata[15:8];
                            latched_metadata_for_write <= latched_s4_metadata;
                            drop_payload_write <= 1'b0;
                        end
                        else begin
                            slot_addr <= {RING_SLOT_WIDTH{1'b0}};
                            latched_metadata_for_write <= {METADATA_LEN{1'b0}};
                            drop_payload_write <= 1'b1;
                            if (s4_valid && s4_moe_consume_en) begin
                                moe_payload_capture_en <= (s4_moe_op_type == `MOE_OP_COMBINE_DATA) ||
                                                          (s4_moe_op_type == `MOE_OP_DISPATCH);
                                current_moe_payload_op_type <= s4_moe_op_type;
                            end
                            else begin
                                moe_payload_capture_en <= (pending_moe_op_type == `MOE_OP_COMBINE_DATA) ||
                                                          (pending_moe_op_type == `MOE_OP_DISPATCH);
                                current_moe_payload_op_type <= pending_moe_op_type;
                            end
                        end
                 
                        item_counter <= 0;
                        // The protocol path also carries one-beat ACK packets.
                        // Remember tlast from the beat consumed on the
                        // PB_IDLE -> PB_PROCESS transition; otherwise an ACK
                        // waits for and consumes the next SEND_ONLY packet as
                        // if it were ACK payload.
                        shifter_fifo_lout <= fifo_lout;
                        is_first_beat <= 1'b1;
                        shifter_container <= fifo_data_out >> ORIGIN_HDR_LEN;
                        remain_in_shift_container <= AXIS_DATA_WIDTH - ORIGIN_HDR_LEN;
                        payload_wr_data <= fifo_data_out >> ORIGIN_HDR_LEN; 
                    end
                end


                PB_PROCESS: begin
                    if (fifo_lout && fifo_dout_valid) begin
                        shifter_fifo_lout <= 1'b1;
                    end

                    // 1. 数据拼接逻辑 (State Action)
                    // 只要不是最后一拍且有新数据，就拼接到容器后面
                    if (!shifter_fifo_lout && fifo_dout_valid && payload_wr_ready) begin
                        if (is_first_beat) begin
                            is_first_beat <= 1'b0;
                            payload_wr_en <= !drop_payload_write;
                            payload_wr_addr <= {slot_addr_holdfix, item_counter_holdfix[3:0]};
                            payload_wr_data <= shifter_container | (fifo_data_out << remain_in_shift_container);
                            if (drop_payload_write && moe_payload_capture_en) begin
                                moe_payload_valid <= 1'b1;
                                moe_payload_op_type <= current_moe_payload_op_type;
                                moe_payload_data <= (shifter_container >> (`MOE_PREFIX_BASE_BYTES * 8)) |
                                                    (fifo_data_out << (AXIS_DATA_WIDTH - ORIGIN_HDR_LEN -
                                                                      (`MOE_PREFIX_BASE_BYTES * 8)));
                            end
                            shifter_container <= fifo_data_out >> ORIGIN_HDR_LEN;
                            item_counter <= item_counter + 1;
                        end
                        else if (item_counter < PAYLOAD_ITEM_NUM && payload_wr_ready) begin

                            payload_wr_en <= !drop_payload_write;
                            payload_wr_addr <= {slot_addr_holdfix, item_counter_holdfix[3:0]};
                            payload_wr_data <= shifter_container | (fifo_data_out << remain_in_shift_container);
                            shifter_container <= fifo_data_out >> ORIGIN_HDR_LEN;
                            item_counter <= item_counter + 1;
                        end
                    end

                    // // 2. 写入逻辑 (State Action)
                    // // 注意：这里不需要再初始化 item_counter，它会正常累加
                    // if (remain_in_shift_container >= PAYLOAD_ITEM_WIDTH && item_counter < PAYLOAD_ITEM_NUM && payload_wr_ready) begin
                    //     payload_wr_en <= 1'b1;
                    //     payload_wr_addr <= {slot_addr, item_counter};
                    //     payload_wr_data <= shifter_container[PAYLOAD_ITEM_WIDTH-1:0];

                    //     item_counter <= item_counter + 1;
                    //     shifter_container <= (shifter_container >> PAYLOAD_ITEM_WIDTH);
                    //     remain_in_shift_container <= remain_in_shift_container - PAYLOAD_ITEM_WIDTH;
                    // end

                    // 3. 退出清理 (Transition Action: Cleanup)
                    if (payload_buffer_next_state == PB_IDLE) begin
                        shifter_fifo_lout <= 0;
                        remain_in_shift_container <= 0;
                        item_counter <= 0;
                        drop_payload_write <= 1'b0;
                        moe_payload_capture_en <= 1'b0;
                        current_moe_payload_op_type <= `MOE_OP_NONE;
                    end

                end
            endcase
        end
    end

endmodule
