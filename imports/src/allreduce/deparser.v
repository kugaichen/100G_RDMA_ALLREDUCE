`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/09/08 10:28:18
// Design Name: 
// Module Name: deparser
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

`define PACKET_TYPE_DATA 0
`define PACKET_TYPE_ACK  1
`define PACKET_TYPE_NAK  2


module deparser#(

    // AXIS_STREAM
    parameter AXIS_DATA_WIDTH       = 512,
    parameter AXIS_KEEP_WIDTH       = AXIS_DATA_WIDTH / 8,

    // ORIGINAL HEADER FROM 
    parameter ORIGIN_HDR_LEN        = 54*8,

    // HEADER STRUCTRUE
    parameter PKT_HDR_LEN           = (2*6+4*4+3*2+1) * 8,
    parameter METADATA_LEN          = 2*8+3+5,

    // PAYLOAD
    parameter PAYLOAD_ITEM_NUM      = 16,
    parameter PAYLOAD_ITEM_WIDTH    = 512,
    parameter PAYLOAD_TOTAL_WIDTH   = PAYLOAD_ITEM_WIDTH * PAYLOAD_ITEM_NUM,
    parameter FIRST_PAYLOAD_OFFSET  = 80,

    // FIELD WIDTH
    parameter MAC_ADDR_WIDTH        = 48,
    parameter IP_ADDR_WIDTH         = 32,
    parameter PSN_WIDTH             = 32,
    parameter PORT_WIDTH            = 16,
    parameter QPN_LEN               = 32,
    parameter OPCODE_WIDTH          = 8,


    // PKT
    parameter PKT_WIDTH             = 1078*8,

    // Header_in
    parameter HEADER_SLOT_WIDTH     = 4,
    parameter HEADER_SLOT_DEPTH     = (1 << HEADER_SLOT_WIDTH)
    

)(
    input wire                              clk,
    input wire                              rst_n,

    // For pass-through from parser 
    input wire                              from_parser_pkt_valid,
    input wire [AXIS_DATA_WIDTH-1:0]        from_parser_pkt_data,
    input wire [AXIS_KEEP_WIDTH-1:0]        from_parser_pkt_keep,
    input wire                              from_parser_pkt_last,
    output wire                             in_parser_pkt_ready,


    // Header for lookuphit
    input wire                              from_parser_header_valid,
    input wire [METADATA_LEN-1:0]           from_parser_metadata_in,
    input wire [PKT_HDR_LEN-1:0]            from_parser_header_in,

    // AETH 字段 (用于 ACK 重构时真值透传)
    input wire [7:0]                        from_parser_aeth_syndrome_in,
    input wire [23:0]                       from_parser_aeth_msn_in,

    // root 模式标志 (ACK 路由: root 回 ingress, 非 root 上行 parent)
    input wire                              cfg_is_root,

    // Per-port identity LUT (仅广播路径使用, ACK 路径用换位)
    input wire [47:0]                       cfg_my_mac_p0,
    input wire [47:0]                       cfg_my_mac_p1,
    input wire [31:0]                       cfg_my_ip_p0,
    input wire [31:0]                       cfg_my_ip_p1,
    input wire [23:0]                       cfg_my_qp_p0,
    input wire [23:0]                       cfg_my_qp_p1,
    input wire [15:0]                       cfg_my_port_p0,
    input wire [15:0]                       cfg_my_port_p1,
    input wire [47:0]                       cfg_peer_mac_p0,
    input wire [47:0]                       cfg_peer_mac_p1,
    input wire [31:0]                       cfg_peer_ip_p0,
    input wire [31:0]                       cfg_peer_ip_p1,
    input wire [23:0]                       cfg_peer_qp_p0,
    input wire [23:0]                       cfg_peer_qp_p1,
    input wire [15:0]                       cfg_peer_port_p0,
    input wire [15:0]                       cfg_peer_port_p1,

    // For lookuphit from parser and aggregator
    input wire [METADATA_LEN-1:0]           from_agg_metadata_in,

    // control signal from agg_typer
    input wire                              from_agg_ack_build_en,
    input wire                              from_agg_ack_down_en,
    input wire                              from_agg_FAN_retrans_en,
    input wire                              from_agg_FAN_first_trans_en,
    input wire                              from_agg_down_broadcast_en,
    input wire                              from_agg_port_retrans_en,

    // payload data
    input wire [PAYLOAD_TOTAL_WIDTH-1:0]    from_agg_payload_in, 
    output reg                              in_agg_ready,       
    
    // OUTPUT
    output reg [AXIS_DATA_WIDTH-1:0]        m_axis_tdata,
    output reg [AXIS_KEEP_WIDTH-1:0]        m_axis_tkeep,
    output reg                              m_axis_tvalid,
    output reg                              m_axis_tlast,
    input wire                              m_axis_tready,

    // Route sideband (for wrapper to build TUSER dst_port)
    output reg [2:0]                        m_axis_route_type,
    output reg                              m_axis_is_aggregated,
    output reg [7:0]                        m_axis_agg_ingress_port,

    // ---- DEBUG 端口: 把内部 header 各级状态引出供 ILA 观察 ----
    // header_for_pkt[263:232] = peer_mac 低 32 bit (parser 整数视角,
    //   = dst_mac 字节反转后的低 32 = 对应上板字节序的 dst_mac 字节 2~5)
    // constructed_header[31:0] = AXIS tdata 最低 32 bit
    //   = 上板字节序下包的 byte 0~3 = dst_mac 字节 0~3 (小端)
    // 这两个值在正常情况下都应该等于 parser 整数 0xCC445566
    output wire [31:0]                      dbg_header_for_pkt_lo,
    output wire [31:0]                      dbg_constructed_header_lo,

    // ---- DEBUG 端口 (第二批): 系统化定位 m_axis_route_type=0 的根因 ----
    // dbg_current_state         : FSM 是否在 IDLE (非 0 => 被 PASS_THROUGH/GEN_* 抢占)
    // dbg_header_v_at_agg_slot  : agg 侧 slot 对应的 header 是否有效 (0 => 还没写 / 已消费 / slot 错位)
    // dbg_from_agg_slot         : agg 侧送来的 slot index (metadata[15:8])
    // dbg_parser_slot_r         : parser 写入 header_mem 用的 slot index
    // dbg_header_valid_r        : parser→deparser 打一拍后的 header 写使能
    // dbg_agg_req_valid         : deparser 输入端可见的 agg 请求 OR 结果
    output wire [2:0]                       dbg_current_state,
    output wire                             dbg_header_v_at_agg_slot,
    output wire [7:0]                       dbg_from_agg_slot,
    output wire [7:0]                       dbg_parser_slot_r,
    output wire                             dbg_header_valid_r,
    output wire                             dbg_agg_req_valid
);
    localparam IDLE             = 3'd0;
    localparam PASS_THROUGH     = 3'd1;
    localparam GEN_HEADER       = 3'd2;
    localparam GEN_PAYLOAD      = 3'd3;
    localparam GEN_HEADER_P1    = 3'd4;  // 广播第二份包 header (P1 LUT)
    localparam GEN_PAYLOAD_P1   = 3'd5;  // 广播第二份包 payload

    localparam ROUTE_PASSTHROUGH            = 3'd0;
    localparam ROUTE_TO_PARENT              = 3'd1;
    localparam ROUTE_TO_CHILD_SINGLE        = 3'd2;
    localparam ROUTE_TO_CHILDREN_ALL        = 3'd3;
    localparam ROUTE_TO_PARENT_AND_CHILDREN = 3'd4;

    reg [2:0]   current_state, next_state;

    reg [2:0]   latched_route_type;
    reg [7:0]   latched_agg_ingress;

    reg [7:0]                       payload_beat_count;
    reg has_payload;

    wire payload_last_beat = (payload_beat_count == (PAYLOAD_ITEM_NUM - 1));

    // =================================================================
    // 0. Header Store For lookup-hit (Header is arrival early than payload)
    // =================================================================
    reg [PKT_HDR_LEN-1:0]           header_mem [0:HEADER_SLOT_DEPTH-1];
    reg [HEADER_SLOT_DEPTH-1:0]     header_v;

    reg [PKT_HDR_LEN-1:0]           header_for_pkt;

    // AETH 存储 (与 header_mem 同步写入/读出)
    reg [7:0]                        aeth_syndrome_mem [0:HEADER_SLOT_DEPTH-1];
    reg [23:0]                       aeth_msn_mem [0:HEADER_SLOT_DEPTH-1];
    reg [7:0]                        latched_aeth_syndrome;
    reg [23:0]                       latched_aeth_msn;

    // DEBUG 引出 header_for_pkt 的 peer_mac 低 32 bit
    assign dbg_header_for_pkt_lo = header_for_pkt[263:232];

    // Pipeline register: break cross-module path from parser
    // 用一级流水寄存器替代 LUT1 holdfix。
    // 原理：LUT1 只加 ~0.1ns 延迟，不够抵消时钟偏斜。
    // 流水寄存器让两级 FF 之间有完整的 4ns 周期，彻底消除 hold 违规。
    // 功能安全：header 比 payload 早到达，多 1 拍不影响时序关系。
    reg [PKT_HDR_LEN-1:0]          header_in_r;
    reg                            header_valid_r;
    reg [7:0]                      metadata_slot_r;
    // AETH 也打 1 拍, 与 header_valid_r 时序对齐
    reg [7:0]                      aeth_syndrome_r;
    reg [23:0]                     aeth_msn_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            header_in_r    <= {PKT_HDR_LEN{1'b0}};
            header_valid_r <= 1'b0;
            metadata_slot_r <= 8'd0;
            aeth_syndrome_r <= 8'h00;
            aeth_msn_r <= 24'h000000;
        end else begin
            header_in_r    <= from_parser_header_in;
            header_valid_r <= from_parser_header_valid;
            metadata_slot_r <= from_parser_metadata_in[15:8];
            aeth_syndrome_r <= from_parser_aeth_syndrome_in;
            aeth_msn_r <= from_parser_aeth_msn_in;
        end
    end

    wire is_ack_pkt = from_agg_ack_build_en || from_agg_ack_down_en;

    wire is_data_pkt = from_agg_FAN_retrans_en || from_agg_FAN_first_trans_en ||
                        from_agg_down_broadcast_en || from_agg_port_retrans_en;

    wire agg_req_valid = is_ack_pkt || is_data_pkt;

    wire [7:0] from_metadata_slot = from_parser_metadata_in[15:8];

    // FSM 优先级翻转后, IDLE 拍如果 agg_req_valid=1 会去 GEN_HEADER, 这时不能
    // 同拍接受 parser 的 passthrough beat (否则丢 1 拍). 所以 IDLE 态只有
    // 在没有 agg 请求时才对 parser ready. PASS_THROUGH 态保持原行为.
    assign in_parser_pkt_ready = ((current_state == IDLE && !agg_req_valid)
                                  || (current_state == PASS_THROUGH))
                                 && m_axis_tready;

    // ---- DEBUG 引出 ----
    assign dbg_current_state        = current_state;
    assign dbg_header_v_at_agg_slot = header_v[from_agg_metadata_in[15:8]];
    assign dbg_from_agg_slot        = from_agg_metadata_in[15:8];
    assign dbg_parser_slot_r        = metadata_slot_r;
    assign dbg_header_valid_r       = header_valid_r;
    assign dbg_agg_req_valid        = agg_req_valid;
        
    // wire agg_can_out = agg_req_valid && header_v[from_metadata_slot];

    // latched 
    reg                             latched_is_ack_pkt;
    reg                             latched_is_data_pkt;
    reg [METADATA_LEN-1:0]          latched_agg_metadata;
    reg                             latched_valid;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            header_v <= {HEADER_SLOT_DEPTH{1'b0}};
            header_for_pkt <= {PKT_HDR_LEN{1'b0}};
            latched_is_ack_pkt <= 1'b0;
            latched_is_data_pkt <= 1'b0;
            latched_agg_metadata <= {METADATA_LEN{1'b0}};
            latched_valid <= 1'b0;
            latched_route_type <= ROUTE_PASSTHROUGH;
            latched_agg_ingress <= 8'd0;
            latched_aeth_syndrome <= 8'h00;
            latched_aeth_msn <= 24'h000000;
        end

        else begin
            if (header_valid_r) begin
                header_mem[metadata_slot_r] <= header_in_r;
                header_v[metadata_slot_r] <= 1'b1;
                aeth_syndrome_mem[metadata_slot_r] <= aeth_syndrome_r;
                aeth_msn_mem[metadata_slot_r] <= aeth_msn_r;
            end

            if (current_state == IDLE && agg_req_valid && header_v[from_agg_metadata_in[15:8]]) begin
                header_for_pkt <= header_mem[from_agg_metadata_in[15:8]];
                header_v[from_agg_metadata_in[15:8]] <= 1'b0;
                latched_is_ack_pkt <= is_ack_pkt;
                latched_is_data_pkt <= is_data_pkt;
                latched_aeth_syndrome <= aeth_syndrome_mem[from_agg_metadata_in[15:8]];
                latched_aeth_msn <= aeth_msn_mem[from_agg_metadata_in[15:8]];

                latched_agg_ingress <= from_agg_metadata_in[7:0];
                if (from_agg_ack_build_en) begin
                    // 上行 ACK: 永远回 ingress port
                    latched_route_type <= ROUTE_TO_CHILD_SINGLE;
                end else if (from_agg_FAN_retrans_en || from_agg_FAN_first_trans_en) begin
                    // 数据转发: root 广播所有 child; 非 root 上行 parent
                    if (cfg_is_root)
                        latched_route_type <= ROUTE_TO_CHILDREN_ALL;
                    else
                        latched_route_type <= ROUTE_TO_PARENT;
                end
                else if (from_agg_ack_down_en || from_agg_port_retrans_en)
                    latched_route_type <= ROUTE_TO_CHILD_SINGLE;
                else if (from_agg_down_broadcast_en && from_agg_metadata_in[21:19] == 3'b011)
                    latched_route_type <= ROUTE_TO_PARENT_AND_CHILDREN;
                else if (from_agg_down_broadcast_en)
                    latched_route_type <= ROUTE_TO_CHILDREN_ALL;
                else
                    latched_route_type <= ROUTE_PASSTHROUGH;
            end
        end
            
    end


    // Constructed Header Buffer (512 bits)
    reg [AXIS_DATA_WIDTH-1:0] constructed_header;

    // DEBUG 引出 constructed_header 的最低 32 bit (= AXIS tdata 第 0~3 字节, dst_mac 字节 0~3)
    assign dbg_constructed_header_lo = constructed_header[31:0];

    // =================================================================
    // 1. Unpack Header Fields (Raw Wire Order from Parser)
    // =================================================================
    wire [47:0] h_peer_mac  = header_for_pkt[279:232];
    wire [47:0] h_src_mac   = header_for_pkt[231:184];
    wire [31:0] h_peer_ip   = header_for_pkt[183:152];
    wire [31:0] h_src_ip    = header_for_pkt[151:120];
    wire [15:0] h_peer_port = header_for_pkt[119:104];
    wire [15:0] h_src_port  = header_for_pkt[103:88];
    wire [15:0] h_len       = header_for_pkt[87:72];
    wire [31:0] h_qpn       = header_for_pkt[71:40];      // Assuming 32 bit QPN in struct
    wire [31:0] h_psn       = header_for_pkt[39:8];       // Assuming 32 bit PSN/APSN
    wire [7:0]  h_opcode    = header_for_pkt[7:0];

    // =================================================================
    // 1b. 广播路径 LUT 选择 (ACK 路径保持换位不变)
    // =================================================================
    reg port_sel;  // 0=P0, 1=P1; 广播第二份时置1
    wire is_broadcast = (latched_route_type == ROUTE_TO_CHILDREN_ALL);
    wire use_lut = latched_is_data_pkt && is_broadcast;

    wire [47:0] sel_dst_mac  = use_lut ? (port_sel ? cfg_peer_mac_p1  : cfg_peer_mac_p0)  : h_peer_mac;
    wire [47:0] sel_src_mac  = use_lut ? (port_sel ? cfg_my_mac_p1    : cfg_my_mac_p0)    : h_src_mac;
    wire [31:0] sel_dst_ip   = use_lut ? (port_sel ? cfg_peer_ip_p1   : cfg_peer_ip_p0)   : h_peer_ip;
    wire [31:0] sel_src_ip   = use_lut ? (port_sel ? cfg_my_ip_p1     : cfg_my_ip_p0)     : h_src_ip;
    wire [23:0] sel_dst_qp   = use_lut ? (port_sel ? cfg_peer_qp_p1   : cfg_peer_qp_p0)   : h_qpn[23:0];
    wire [15:0] sel_src_port = use_lut ? (port_sel ? cfg_my_port_p1   : cfg_my_port_p0)   : h_src_port;
    wire [15:0] sel_dst_port = use_lut ? (port_sel ? cfg_peer_port_p1 : cfg_peer_port_p0) : h_peer_port;

    // =================================================================
    // 2.Length Calculation
    // =================================================================
    // Eth(14) + IP(20) + UDP(8) + BTH(12) = 54 bytes
    // AETH = 4 bytes (Only for ACK)
    //
    // [原代码: 依赖 h_len 是 byte-reversed 假整数 + header_len_bytes 与 wire 解析"两次反转抵消"]
    // wire [15:0] payload_len_bytes = latched_is_data_pkt ? h_len : 16'd0;
    // wire [15:0] header_len_bytes = 16'd54 + (latched_is_ack_pkt ? 16'd4 : 16'd0);
    // wire [15:0] ip_total_len = header_len_bytes - 16'd14 + payload_len_bytes;
    // wire [15:0] udp_len = ip_total_len - 16'd20;

    // 字节序治本: h_len 现在是 parser 输出的 "纯 payload 字节数" (host 视角真整数).
    // 直接做协议规定的算术, 写回 wire 时再按 host MSB -> wire byte 0 翻转.
    wire [15:0] payload_len_bytes = latched_is_data_pkt ? h_len : 16'd0;
    // BTH+AETH 长度: data 包 = 12, ack 包 = 12 + 4 (AETH)
    wire [15:0] bth_plus_aeth = 16'd12 + (latched_is_ack_pkt ? 16'd4 : 16'd0);
    // IP total length = IP header(20) + UDP header(8) + BTH(+AETH) + payload + ICRC(4)
    wire [15:0] ip_total_len = 16'd20 + 16'd8 + bth_plus_aeth + payload_len_bytes + 16'd4;
    // UDP length = UDP header(8) + BTH(+AETH) + payload + ICRC(4) = IP total - IP header(20)
    wire [15:0] udp_len = ip_total_len - 16'd20;

    // IP header checksum (ones-complement sum of 10 16-bit words, checksum field as 0)
    // 字段: 0x4500 | total_len | 0x1111 | 0x4000 | 0x4011 | 0x0000 | src_ip_hi | src_ip_lo | dst_ip_hi | dst_ip_lo
    wire [31:0] ip_sum_pre = 16'h4500 + ip_total_len + 16'h1111 + 16'h4000
                            + 16'h4011 + 16'h0000
                            + sel_src_ip[31:16] + sel_src_ip[15:0]
                            + sel_dst_ip[31:16] + sel_dst_ip[15:0];
    wire [16:0] ip_sum_fold = ip_sum_pre[15:0] + ip_sum_pre[31:16];
    wire [15:0] ip_checksum = ~(ip_sum_fold[15:0] + {15'd0, ip_sum_fold[16]});

    // =================================================================
    // 3. MSN logic
    // =================================================================
    // [原代码: h_psn 是 byte-reversed 假整数, +1 前后都要字节翻转]
    // wire [31:0] psn_value = {h_psn[7:0], h_psn[15:8], h_psn[23:16], h_psn[31:24]};
    // wire [31:0] msn_value = psn_value + 1;
    // wire [31:0] msn = {msn_value[7:0], msn_value[15:8], msn_value[23:16], msn_value[31:24]};

    // 字节序治本: h_psn 已是 host 视角真整数, 直接 +1 即可. 写回 wire 时再翻转.
    wire [31:0] msn = h_psn + 32'd1;

    // =================================================================
    // 4. Opcode & PSN Logic
    // =================================================================
    reg [7:0]   target_opcode;
    reg [31:0]  target_psn;

    always @( *) begin
        if (latched_is_ack_pkt) begin
            target_opcode = 8'h11;
            target_psn = h_psn;
        end
        else begin
            target_opcode = h_opcode;
            // [原代码: MSB 置于 h_psn[31], 但因 h_psn 当时是 byte-reversed 假整数,
            //         实际 wire 上 MSB 落到了 byte 3 而不是 byte 0 (AckReq 位)]
            // target_psn = h_psn | 32'h80000000;
            // 字节序治本: h_psn 已是 host 视角, MSB(bit31) 就是 wire byte 0 的 MSB (= AckReq)
            target_psn = h_psn | 32'h80000000;
        end
    end

    reg [PAYLOAD_TOTAL_WIDTH-1:0]    data_payload;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_payload <= 0;
        end
        else begin
            if (is_data_pkt) begin
                data_payload <= from_agg_payload_in;
            end    
        end
    end

    // =================================================================
    // 5. Header Reconstruction Logic
    // =================================================================
    always @(*) begin
    //     if (!rst_n) begin
    //         constructed_header = {AXIS_DATA_WIDTH{1'b0}};
    //     end
    //     else begin
    //         if (agg_req_valid) begin
    //             // -------------------------------------------------------------
    //             // 5.1. Ethernet Header (14 bytes) -> Bytes 0-13
    //             // -------------------------------------------------------------
    //             constructed_header[47:0]        =   h_peer_mac;
    //             constructed_header[95:48]       =   h_src_mac;
    //             // eth type 0x0800
    //             constructed_header[103:96]      =   8'h08;          // eth_type
    //             constructed_header[111:104]     =   8'h00;          // eth_type

    //             // -------------------------------------------------------------
    //             // 5.2. IP Header (Bytes 14-33)
    //             // -------------------------------------------------------------
    //             // ver/hil 0x45
    //             constructed_header[119:112]     =   8'h45;          // ip_ver/ihl
    //             // tos 0x00
    //             constructed_header[127:120]     =   8'h00;          // ip_tos
    //             // total length -> htons(ip_total_len)
    //             constructed_header[135:128]     =   ip_total_len[15:8];
    //             constructed_header[143:136]     =   ip_total_len[7:0];
    //             // ID 0x1111
    //             constructed_header[159:144]     =   16'h1111;       // ip_id
    //             // flags_frag htons(0x4000)
    //             constructed_header[167:160]     =   8'h40;
    //             constructed_header[175:168]     =   8'h00;
    //             // ttl 0x40
    //             constructed_header[183:176]     =   8'h40;          // ip_ttl
    //             // protocol 0x11
    //             constructed_header[191:184]     =   8'h11;          // ip_protocol
    //             // checksum 
    //             constructed_header[207:192]     =   16'h0000;       // ip_checksum
    //             // src ip 
    //             constructed_header[239:208]     =   h_src_ip;       // src_ip
    //             // dst ip
    //             constructed_header[271:240]     =   h_peer_ip;      // dst_ip

    //             // -------------------------------------------------------------
    //             // 5.3. UDP Header (Bytes 34-41)
    //             // -------------------------------------------------------------   
    //             // src port 
    //             constructed_header[287:272]     =   h_src_port;     // src_port
    //             // dst port
    //             constructed_header[303:288]     =   h_peer_port;    // dst_port
    //             // length -> htons(udp_len)
    //             constructed_header[311:304]     =   udp_len[15:8];
    //             constructed_header[319:312]     =   udp_len[7:0];
    //             // checksum 
    //             constructed_header[335:320]     =   16'h0000;

    //             // -------------------------------------------------------------
    //             // 5.4. BTH Header (Bytes 42-53)
    //             // -------------------------------------------------------------  
    //             // Opcode
    //             constructed_header[343:336]     =   target_opcode;
    //             // se_m_pad
    //             constructed_header[351:344]     =   8'h00;
    //             // pkey 
    //             constructed_header[367:352]     =   16'hffff;
    //             // QPN
    //             constructed_header[399:368]     =   h_qpn;
    //             // apsn
    //             constructed_header[431:400]     =   target_psn;

    //             // -------------------------------------------------------------
    //             // 5.5. AETH Header (Bytes 54-57) && payload padding
    //             // -------------------------------------------------------------  
    //             if (is_ack_pkt) begin
    //                 constructed_header[439:432] =   8'h1F;          // syndrome = 0x1F
    //                 constructed_header[447:440] =   msn[7:0];
    //                 constructed_header[455:448] =   msn[15:8];
    //                 constructed_header[463:456] =   msn[23:16];
    //             end
    //             else if (is_data_pkt) begin
    //                 constructed_header[511:432]     =   from_agg_payload_in[79:0];
    //             end
    //         end
    //     end
    // end



        constructed_header = {AXIS_DATA_WIDTH{1'b0}};

        // =================================================================
        // [原代码: 依赖 parser 送来的 byte-reversed 假整数, 用位段直接拷贝,
        //          相当于 "两次反转" 后刚好变回 wire 字节序. length / psn
        //          因为要做算术无法两次反转抵消, 导致 wireshark 解析错误.]
        // -------------------------------------------------------------
        // // 5.1. Ethernet Header (14 bytes) -> Bytes 0-13
        // constructed_header[47:0]        =   h_peer_mac;
        // constructed_header[95:48]       =   h_src_mac;
        // constructed_header[103:96]      =   8'h08;
        // constructed_header[111:104]     =   8'h00;
        //
        // // 5.2. IP Header (Bytes 14-33)
        // constructed_header[119:112]     =   8'h45;
        // constructed_header[127:120]     =   8'h00;
        // constructed_header[135:128]     =   ip_total_len[15:8];
        // constructed_header[143:136]     =   ip_total_len[7:0];
        // constructed_header[159:144]     =   16'h1111;
        // constructed_header[167:160]     =   8'h40;
        // constructed_header[175:168]     =   8'h00;
        // constructed_header[183:176]     =   8'h40;
        // constructed_header[191:184]     =   8'h11;
        // constructed_header[207:192]     =   16'h0000;
        // constructed_header[239:208]     =   h_src_ip;
        // constructed_header[271:240]     =   h_peer_ip;
        //
        // // 5.3. UDP Header (Bytes 34-41)
        // constructed_header[287:272]     =   h_src_port;
        // constructed_header[303:288]     =   h_peer_port;
        // constructed_header[311:304]     =   udp_len[15:8];
        // constructed_header[319:312]     =   udp_len[7:0];
        // constructed_header[335:320]     =   16'h0000;
        //
        // // 5.4. BTH Header (Bytes 42-53)
        // constructed_header[343:336]     =   target_opcode;
        // constructed_header[351:344]     =   8'h00;
        // constructed_header[367:352]     =   16'hffff;
        // constructed_header[399:368]     =   h_qpn;
        // constructed_header[431:400]     =   target_psn;
        //
        // // 5.5. AETH (Bytes 54-57) && payload padding
        // if (latched_is_ack_pkt) begin
        //     constructed_header[439:432] =   8'h1F;
        //     constructed_header[447:440] =   msn[7:0];
        //     constructed_header[455:448] =   msn[15:8];
        //     constructed_header[463:456] =   msn[23:16];
        // end
        // else if (latched_is_data_pkt) begin
        //     constructed_header[511:432]     =   data_payload[79:0];
        // end
        // =================================================================

        // =================================================================
        // 字节序治本: host 视角 -> wire 字节序
        // ----------------------------------------------------------------
        // h_* 字段现在都是 parser 送过来的 host 视角真整数 (MSB 在高位).
        // wire 视角要求: byte 0 在 tdata LSB, 即 constructed_header[7:0].
        // 多字节字段按 "host MSB -> wire byte 0 -> constructed_header 低字节位"
        // 逐字节翻转赋值.
        // =================================================================

        // -------------------------------------------------------------
        // 5.1. Ethernet Header (wire byte 0~13)
        // -------------------------------------------------------------
        // dst_mac: wire byte 0~5
        constructed_header[  7:  0] = sel_dst_mac[47:40];
        constructed_header[ 15:  8] = sel_dst_mac[39:32];
        constructed_header[ 23: 16] = sel_dst_mac[31:24];
        constructed_header[ 31: 24] = sel_dst_mac[23:16];
        constructed_header[ 39: 32] = sel_dst_mac[15: 8];
        constructed_header[ 47: 40] = sel_dst_mac[ 7: 0];
        // src_mac: wire byte 6~11
        constructed_header[ 55: 48] = sel_src_mac[47:40];
        constructed_header[ 63: 56] = sel_src_mac[39:32];
        constructed_header[ 71: 64] = sel_src_mac[31:24];
        constructed_header[ 79: 72] = sel_src_mac[23:16];
        constructed_header[ 87: 80] = sel_src_mac[15: 8];
        constructed_header[ 95: 88] = sel_src_mac[ 7: 0];
        // eth_type 0x0800: wire byte 12 = 0x08, byte 13 = 0x00
        constructed_header[103: 96] = 8'h08;
        constructed_header[111:104] = 8'h00;

        // -------------------------------------------------------------
        // 5.2. IP Header (wire byte 14~33)
        // -------------------------------------------------------------
        constructed_header[119:112] = 8'h45;                 // byte 14: ver/ihl
        constructed_header[127:120] = 8'h00;                 // byte 15: tos
        constructed_header[135:128] = ip_total_len[15: 8];   // byte 16: total len MSB
        constructed_header[143:136] = ip_total_len[ 7: 0];   // byte 17: total len LSB
        constructed_header[151:144] = 8'h11;                 // byte 18: ID MSB (0x1111)
        constructed_header[159:152] = 8'h11;                 // byte 19: ID LSB
        constructed_header[167:160] = 8'h40;                 // byte 20: flags_frag MSB (0x4000)
        constructed_header[175:168] = 8'h00;                 // byte 21: flags_frag LSB
        constructed_header[183:176] = 8'h40;                 // byte 22: TTL
        constructed_header[191:184] = 8'h11;                 // byte 23: protocol (UDP=0x11)
        constructed_header[199:192] = ip_checksum[15:8];     // byte 24: checksum MSB
        constructed_header[207:200] = ip_checksum[ 7:0];     // byte 25: checksum LSB
        // src_ip: wire byte 26~29
        constructed_header[215:208] = sel_src_ip[31:24];
        constructed_header[223:216] = sel_src_ip[23:16];
        constructed_header[231:224] = sel_src_ip[15: 8];
        constructed_header[239:232] = sel_src_ip[ 7: 0];
        // dst_ip: wire byte 30~33
        constructed_header[247:240] = sel_dst_ip[31:24];
        constructed_header[255:248] = sel_dst_ip[23:16];
        constructed_header[263:256] = sel_dst_ip[15: 8];
        constructed_header[271:264] = sel_dst_ip[ 7: 0];

        // -------------------------------------------------------------
        // 5.3. UDP Header (wire byte 34~41)
        // -------------------------------------------------------------
        // src_port: wire byte 34~35
        constructed_header[279:272] = sel_src_port[15: 8];
        constructed_header[287:280] = sel_src_port[ 7: 0];
        // dst_port: wire byte 36~37
        constructed_header[295:288] = sel_dst_port[15: 8];
        constructed_header[303:296] = sel_dst_port[ 7: 0];
        // UDP length: wire byte 38~39
        constructed_header[311:304] = udp_len[15: 8];
        constructed_header[319:312] = udp_len[ 7: 0];
        // UDP checksum 0: wire byte 40~41
        constructed_header[327:320] = 8'h00;
        constructed_header[335:328] = 8'h00;

        // -------------------------------------------------------------
        // 5.4. BTH Header (wire byte 42~53)
        // -------------------------------------------------------------
        constructed_header[343:336] = target_opcode;         // byte 42: opcode
        constructed_header[351:344] = 8'h00;                 // byte 43: se/m/pad
        constructed_header[359:352] = 8'hFF;                 // byte 44: pkey MSB (0xFFFF)
        constructed_header[367:360] = 8'hFF;                 // byte 45: pkey LSB
        // QPN: wire byte 46~49 (广播用 LUT, ACK 用换位)
        constructed_header[375:368] = use_lut ? 8'h00            : h_qpn[31:24];
        constructed_header[383:376] = use_lut ? sel_dst_qp[23:16]: h_qpn[23:16];
        constructed_header[391:384] = use_lut ? sel_dst_qp[15: 8]: h_qpn[15: 8];
        constructed_header[399:392] = use_lut ? sel_dst_qp[ 7: 0]: h_qpn[ 7: 0];
        // APSN (含 AckReq bit): wire byte 50~53
        constructed_header[407:400] = target_psn[31:24];
        constructed_header[415:408] = target_psn[23:16];
        constructed_header[423:416] = target_psn[15: 8];
        constructed_header[431:424] = target_psn[ 7: 0];

        // -------------------------------------------------------------
        // 5.5. AETH Header (wire byte 54~57) / Payload first 10 bytes
        // -------------------------------------------------------------
        if (latched_is_ack_pkt) begin
            // AETH: syndrome(1) + msn(3) = 4 bytes (wire byte 54~57)
            // ACK 重构时使用入包真值透传 (避免 MSN 不一致)
            constructed_header[439:432] = latched_aeth_syndrome;   // byte 54: syndrome
            constructed_header[447:440] = latched_aeth_msn[23:16]; // byte 55: msn MSB
            constructed_header[455:448] = latched_aeth_msn[15: 8]; // byte 56: msn mid
            constructed_header[463:456] = latched_aeth_msn[ 7: 0]; // byte 57: msn LSB
        end
        else if (latched_is_data_pkt) begin
            // 数据包: wire byte 54~63 = payload 前 10 字节.
            // data_payload 是 aggregator 送来的聚合 payload, 已经是 wire 字节序
            // (BRAM 按 wire tdata 整拍存), 直接位段拷贝.
            constructed_header[511:432] = data_payload[79:0];
        end
    end
    

    // =================================================================
    // 6. State Machine & Datapath (AXI Stream Output)
    // =================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always @( *) begin
        next_state = current_state;
             
        case (current_state)
            IDLE: begin
                // 优先级翻转: agg 聚合请求优先, 避免 passthrough 长包占用 FSM
                // 导致 FAN_trans 信号活跃期间 FSM 卡在 PASS_THROUGH, latched_route_type
                // 永远写不进去.
                if (agg_req_valid) begin
                    next_state = GEN_HEADER;
                end
                else if (from_parser_pkt_valid) begin
                    next_state = PASS_THROUGH;
                end
            end

            PASS_THROUGH: begin
                if (from_parser_pkt_last && m_axis_tready) begin
                    next_state = IDLE;
                end
            end

            GEN_HEADER: begin
                if (m_axis_tready) begin
                    next_state = has_payload ? GEN_PAYLOAD : IDLE;
                end
            end

            GEN_PAYLOAD: begin
                if (m_axis_tready && payload_beat_count == (PAYLOAD_ITEM_NUM - 1)) begin
                    next_state = is_broadcast ? GEN_HEADER_P1 : IDLE;
                end
            end

            GEN_HEADER_P1: begin
                if (m_axis_tready) begin
                    next_state = has_payload ? GEN_PAYLOAD_P1 : IDLE;
                end
            end

            GEN_PAYLOAD_P1: begin
                if (m_axis_tready && payload_beat_count == (PAYLOAD_ITEM_NUM - 1)) begin
                    next_state = IDLE;
                end
            end
        endcase
    end


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tdata <= 0;
            m_axis_tkeep <= 0;
            m_axis_tvalid <= 0;
            m_axis_tlast <= 0;
            // in_parser_pkt_ready <= 0;
            in_agg_ready <= 0;
            payload_beat_count <= 0;
            has_payload <= 0;
            port_sel <= 1'b0;
            m_axis_route_type <= ROUTE_PASSTHROUGH;
            m_axis_is_aggregated <= 1'b0;
            m_axis_agg_ingress_port <= 8'd0;
        end
        else begin
            m_axis_tdata  <= {AXIS_DATA_WIDTH{1'b0}};
            m_axis_tkeep  <= {AXIS_KEEP_WIDTH{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
            m_axis_route_type <= ROUTE_PASSTHROUGH;
            m_axis_is_aggregated <= 1'b0;
            m_axis_agg_ingress_port <= 8'd0;

            // in_parser_pkt_ready <= 1'b0;
            in_agg_ready        <= 1'b0;

            case (current_state) 
                IDLE: begin
                    // 优先级翻转 (与 next_state 保持一致):
                    // 先处理 agg 聚合请求, 再处理 parser 透传 beat.
                    in_agg_ready <= 1'b1;
                    if (agg_req_valid) begin
                        has_payload <= is_data_pkt;
                        payload_beat_count <= 0;
                        port_sel <= 1'b0;
                        in_agg_ready <= 1'b0;
                    end

                    else if (from_parser_pkt_valid) begin
                        m_axis_tdata <= from_parser_pkt_data;
                        m_axis_tkeep <= from_parser_pkt_keep;
                        m_axis_tvalid <= 1'b1;
                        m_axis_tlast <= from_parser_pkt_last;

                        in_agg_ready <= 1'b0;
                    end
                end

                PASS_THROUGH: begin
                    if (from_parser_pkt_valid) begin
                        m_axis_tdata <= from_parser_pkt_data;
                        m_axis_tkeep <= from_parser_pkt_keep;
                        m_axis_tvalid <= 1'b1;
                        m_axis_tlast <= from_parser_pkt_last;
                        if (from_parser_pkt_last) begin
                            in_agg_ready <= 1'b1;  // 针对pass-throgh和aggregate连续处理调整（目前正常，后续出问题优先看
                        end
                    end 
                    // in_parser_pkt_ready <= m_axis_tready;                  
                end

                GEN_HEADER: begin
                    m_axis_tvalid <= 1'b1;
                    m_axis_tdata <= constructed_header;
                    m_axis_tkeep <= {AXIS_KEEP_WIDTH{1'b1}};

                    m_axis_tlast <= has_payload ? 1'b0 : 1'b1;

                    m_axis_is_aggregated <= 1'b1;
                    // 广播路径: 串行单播, 第一份发 P0
                    m_axis_route_type       <= is_broadcast ? ROUTE_TO_CHILD_SINGLE : latched_route_type;
                    m_axis_agg_ingress_port <= is_broadcast ? 8'd0 : latched_agg_ingress;
                end

                GEN_PAYLOAD: begin
                    m_axis_tvalid <= 1'b1;

                    case (payload_beat_count)
                        4'd0:    m_axis_tdata <= data_payload[  80 +: 512];
                        4'd1:    m_axis_tdata <= data_payload[ 592 +: 512];
                        4'd2:    m_axis_tdata <= data_payload[1104 +: 512];
                        4'd3:    m_axis_tdata <= data_payload[1616 +: 512];
                        4'd4:    m_axis_tdata <= data_payload[2128 +: 512];
                        4'd5:    m_axis_tdata <= data_payload[2640 +: 512];
                        4'd6:    m_axis_tdata <= data_payload[3152 +: 512];
                        4'd7:    m_axis_tdata <= data_payload[3664 +: 512];
                        4'd8:    m_axis_tdata <= data_payload[4176 +: 512];
                        4'd9:    m_axis_tdata <= data_payload[4688 +: 512];
                        4'd10:   m_axis_tdata <= data_payload[5200 +: 512];
                        4'd11:   m_axis_tdata <= data_payload[5712 +: 512];
                        4'd12:   m_axis_tdata <= data_payload[6224 +: 512];
                        4'd13:   m_axis_tdata <= data_payload[6736 +: 512];
                        4'd14:   m_axis_tdata <= data_payload[7248 +: 512];
                        4'd15:   m_axis_tdata <= {{80{1'b0}}, data_payload[8191 : 7760]};
                        default: m_axis_tdata <= {AXIS_DATA_WIDTH{1'b0}};
                    endcase

                    m_axis_tkeep <= payload_last_beat ? {58{1'b1}} : {AXIS_KEEP_WIDTH{1'b1}};
                    m_axis_tlast <= payload_last_beat;

                    m_axis_is_aggregated <= 1'b1;
                    m_axis_route_type       <= is_broadcast ? ROUTE_TO_CHILD_SINGLE : latched_route_type;
                    m_axis_agg_ingress_port <= is_broadcast ? 8'd0 : latched_agg_ingress;

                    if (m_axis_tready) begin
                        payload_beat_count <= payload_beat_count + 1;

                        if (payload_beat_count == (PAYLOAD_ITEM_NUM -1)) begin
                            if (is_broadcast) begin
                                port_sel <= 1'b1;
                                payload_beat_count <= 0;
                            end else begin
                                in_agg_ready <= 1'b1;
                            end
                        end
                    end

                end

                GEN_HEADER_P1: begin
                    m_axis_tvalid <= 1'b1;
                    m_axis_tdata  <= constructed_header;
                    m_axis_tkeep  <= {AXIS_KEEP_WIDTH{1'b1}};
                    m_axis_tlast  <= has_payload ? 1'b0 : 1'b1;
                    m_axis_is_aggregated    <= 1'b1;
                    m_axis_route_type       <= ROUTE_TO_CHILD_SINGLE;
                    m_axis_agg_ingress_port <= 8'd1;
                end

                GEN_PAYLOAD_P1: begin
                    m_axis_tvalid <= 1'b1;

                    case (payload_beat_count)
                        4'd0:    m_axis_tdata <= data_payload[  80 +: 512];
                        4'd1:    m_axis_tdata <= data_payload[ 592 +: 512];
                        4'd2:    m_axis_tdata <= data_payload[1104 +: 512];
                        4'd3:    m_axis_tdata <= data_payload[1616 +: 512];
                        4'd4:    m_axis_tdata <= data_payload[2128 +: 512];
                        4'd5:    m_axis_tdata <= data_payload[2640 +: 512];
                        4'd6:    m_axis_tdata <= data_payload[3152 +: 512];
                        4'd7:    m_axis_tdata <= data_payload[3664 +: 512];
                        4'd8:    m_axis_tdata <= data_payload[4176 +: 512];
                        4'd9:    m_axis_tdata <= data_payload[4688 +: 512];
                        4'd10:   m_axis_tdata <= data_payload[5200 +: 512];
                        4'd11:   m_axis_tdata <= data_payload[5712 +: 512];
                        4'd12:   m_axis_tdata <= data_payload[6224 +: 512];
                        4'd13:   m_axis_tdata <= data_payload[6736 +: 512];
                        4'd14:   m_axis_tdata <= data_payload[7248 +: 512];
                        4'd15:   m_axis_tdata <= {{80{1'b0}}, data_payload[8191 : 7760]};
                        default: m_axis_tdata <= {AXIS_DATA_WIDTH{1'b0}};
                    endcase

                    m_axis_tkeep <= payload_last_beat ? {58{1'b1}} : {AXIS_KEEP_WIDTH{1'b1}};
                    m_axis_tlast <= payload_last_beat;

                    m_axis_is_aggregated    <= 1'b1;
                    m_axis_route_type       <= ROUTE_TO_CHILD_SINGLE;
                    m_axis_agg_ingress_port <= 8'd1;

                    if (m_axis_tready) begin
                        payload_beat_count <= payload_beat_count + 1;

                        if (payload_beat_count == (PAYLOAD_ITEM_NUM -1)) begin
                            in_agg_ready <= 1'b1;
                        end
                    end
                end

            endcase
        end
    end














endmodule
