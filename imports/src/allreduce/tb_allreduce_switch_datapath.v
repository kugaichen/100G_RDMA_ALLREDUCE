`timescale 1ns / 1ps
//
// tb_allreduce_switch_datapath.v
//
// Testbench for the integrated AllReduce + 4-port switch datapath.
// Tests three scenarios:
//   1. Pass-through (non-AllReduce) L2 packet forwarding
//   2. AllReduce aggregation from two child ports
//   3. Mixed traffic (simultaneous normal + AllReduce)
//
// DUT: nf_datapath_4port (contains input_arbiter → allreduce_wrapper → OPL → output_queues)
//

// module tb_allreduce_switch_datapath;

//     // ================================================================
//     // Parameters
//     // ================================================================
//     localparam DATA_W   = 512;
//     localparam KEEP_W   = 64;
//     localparam TUSER_W  = 128;
//     localparam NUM_PORTS = 4;
//     localparam CLK_PERIOD = 3.103;  // 322 MHz

//     // RoCEv2 opcodes (matches Typer.v)
//     localparam [7:0] OPCODE_SEND_ONLY = 8'h04;
//     localparam [7:0] OPCODE_ACK       = 8'h11;

//     // ================================================================
//     // Clock & Reset
//     // ================================================================
//     reg clk = 0;
//     always #(CLK_PERIOD/2) clk = ~clk;

//     reg rst_n = 0;
//     initial begin
//         #20;
//         rst_n = 1;
//     end

//     // ================================================================
//     // DUT signals
//     // ================================================================
//     // Ingress (4 ports)
//     reg  [DATA_W-1:0]   s_axis_tdata  [0:NUM_PORTS-1];
//     reg  [KEEP_W-1:0]   s_axis_tkeep  [0:NUM_PORTS-1];
//     reg  [TUSER_W-1:0]  s_axis_tuser  [0:NUM_PORTS-1];
//     reg  [NUM_PORTS-1:0] s_axis_tvalid;
//     wire [NUM_PORTS-1:0] s_axis_tready;
//     reg  [NUM_PORTS-1:0] s_axis_tlast;

//     // Egress (4 ports)
//     wire [DATA_W-1:0]   m_axis_tdata  [0:NUM_PORTS-1];
//     wire [KEEP_W-1:0]   m_axis_tkeep  [0:NUM_PORTS-1];
//     wire [TUSER_W-1:0]  m_axis_tuser  [0:NUM_PORTS-1];
//     wire [NUM_PORTS-1:0] m_axis_tvalid;
//     reg  [NUM_PORTS-1:0] m_axis_tready;
//     wire [NUM_PORTS-1:0] m_axis_tlast;

//     // ================================================================
//     // DUT instantiation
//     // ================================================================
//     nf_datapath_4port #(
//         .C_S_AXI_DATA_WIDTH  (32),
//         .C_S_AXI_ADDR_WIDTH  (32),
//         .C_BASEADDR          (32'h0),
//         .C_M_AXIS_DATA_WIDTH (DATA_W),
//         .C_S_AXIS_DATA_WIDTH (DATA_W),
//         .C_M_AXIS_TUSER_WIDTH(TUSER_W),
//         .C_S_AXIS_TUSER_WIDTH(TUSER_W),
//         .NUM_QUEUES          (NUM_PORTS)
//     ) u_dut (
//         .axis_aclk   (clk),
//         .axis_resetn (rst_n),
//         .axi_aclk    (clk),
//         .axi_resetn  (rst_n),
//         .allreduce_clk   (clk),
//         .allreduce_rst_n (rst_n),

//         // AXI-Lite: tie off
//         .S0_AXI_AWADDR(32'h0),.S0_AXI_AWVALID(1'b0),.S0_AXI_WDATA(32'h0),
//         .S0_AXI_WSTRB(4'h0),.S0_AXI_WVALID(1'b0),.S0_AXI_BREADY(1'b1),
//         .S0_AXI_ARADDR(32'h0),.S0_AXI_ARVALID(1'b0),.S0_AXI_RREADY(1'b1),
//         .S0_AXI_ARREADY(),.S0_AXI_RDATA(),.S0_AXI_RRESP(),
//         .S0_AXI_RVALID(),.S0_AXI_WREADY(),.S0_AXI_BRESP(),
//         .S0_AXI_BVALID(),.S0_AXI_AWREADY(),

//         .S1_AXI_AWADDR(32'h0),.S1_AXI_AWVALID(1'b0),.S1_AXI_WDATA(32'h0),
//         .S1_AXI_WSTRB(4'h0),.S1_AXI_WVALID(1'b0),.S1_AXI_BREADY(1'b1),
//         .S1_AXI_ARADDR(32'h0),.S1_AXI_ARVALID(1'b0),.S1_AXI_RREADY(1'b1),
//         .S1_AXI_ARREADY(),.S1_AXI_RDATA(),.S1_AXI_RRESP(),
//         .S1_AXI_RVALID(),.S1_AXI_WREADY(),.S1_AXI_BRESP(),
//         .S1_AXI_BVALID(),.S1_AXI_AWREADY(),

//         .S2_AXI_AWADDR(32'h0),.S2_AXI_AWVALID(1'b0),.S2_AXI_WDATA(32'h0),
//         .S2_AXI_WSTRB(4'h0),.S2_AXI_WVALID(1'b0),.S2_AXI_BREADY(1'b1),
//         .S2_AXI_ARADDR(32'h0),.S2_AXI_ARVALID(1'b0),.S2_AXI_RREADY(1'b1),
//         .S2_AXI_ARREADY(),.S2_AXI_RDATA(),.S2_AXI_RRESP(),
//         .S2_AXI_RVALID(),.S2_AXI_WREADY(),.S2_AXI_BRESP(),
//         .S2_AXI_BVALID(),.S2_AXI_AWREADY(),

//         // PLACEHOLDER_DUT_PORTS
//         // Ingress
//         .s_axis_0_tdata (s_axis_tdata[0]), .s_axis_0_tkeep (s_axis_tkeep[0]),
//         .s_axis_0_tuser (s_axis_tuser[0]), .s_axis_0_tvalid(s_axis_tvalid[0]),
//         .s_axis_0_tready(s_axis_tready[0]),.s_axis_0_tlast (s_axis_tlast[0]),

//         .s_axis_1_tdata (s_axis_tdata[1]), .s_axis_1_tkeep (s_axis_tkeep[1]),
//         .s_axis_1_tuser (s_axis_tuser[1]), .s_axis_1_tvalid(s_axis_tvalid[1]),
//         .s_axis_1_tready(s_axis_tready[1]),.s_axis_1_tlast (s_axis_tlast[1]),

//         .s_axis_2_tdata (s_axis_tdata[2]), .s_axis_2_tkeep (s_axis_tkeep[2]),
//         .s_axis_2_tuser (s_axis_tuser[2]), .s_axis_2_tvalid(s_axis_tvalid[2]),
//         .s_axis_2_tready(s_axis_tready[2]),.s_axis_2_tlast (s_axis_tlast[2]),

//         .s_axis_3_tdata (s_axis_tdata[3]), .s_axis_3_tkeep (s_axis_tkeep[3]),
//         .s_axis_3_tuser (s_axis_tuser[3]), .s_axis_3_tvalid(s_axis_tvalid[3]),
//         .s_axis_3_tready(s_axis_tready[3]),.s_axis_3_tlast (s_axis_tlast[3]),

//         // Egress
//         .m_axis_0_tdata (m_axis_tdata[0]), .m_axis_0_tkeep (m_axis_tkeep[0]),
//         .m_axis_0_tuser (m_axis_tuser[0]), .m_axis_0_tvalid(m_axis_tvalid[0]),
//         .m_axis_0_tready(m_axis_tready[0]),.m_axis_0_tlast (m_axis_tlast[0]),

//         .m_axis_1_tdata (m_axis_tdata[1]), .m_axis_1_tkeep (m_axis_tkeep[1]),
//         .m_axis_1_tuser (m_axis_tuser[1]), .m_axis_1_tvalid(m_axis_tvalid[1]),
//         .m_axis_1_tready(m_axis_tready[1]),.m_axis_1_tlast (m_axis_tlast[1]),

//         .m_axis_2_tdata (m_axis_tdata[2]), .m_axis_2_tkeep (m_axis_tkeep[2]),
//         .m_axis_2_tuser (m_axis_tuser[2]), .m_axis_2_tvalid(m_axis_tvalid[2]),
//         .m_axis_2_tready(m_axis_tready[2]),.m_axis_2_tlast (m_axis_tlast[2]),

//         .m_axis_3_tdata (m_axis_tdata[3]), .m_axis_3_tkeep (m_axis_tkeep[3]),
//         .m_axis_3_tuser (m_axis_tuser[3]), .m_axis_3_tvalid(m_axis_tvalid[3]),
//         .m_axis_3_tready(m_axis_tready[3]),.m_axis_3_tlast (m_axis_tlast[3])
//     );

//     // ================================================================
//     // Helper: build TUSER
//     // ================================================================
//     function [TUSER_W-1:0] build_tuser;
//         input [7:0] src_port_1hot;
//         input [15:0] pkt_len;
//         begin
//             build_tuser = {TUSER_W{1'b0}};
//             build_tuser[23:16] = src_port_1hot;
//             build_tuser[15:0]  = pkt_len;
//         end
//     endfunction

//     // ================================================================
//     // Helper: build Ethernet + IP + UDP + BTH header in 512-bit beat
//     //   Byte layout (little-endian in 512-bit word):
//     //   [0:5]   dst_mac    [6:11]  src_mac    [12:13] eth_type=0x0800
//     //   [14:33] IP header  [34:41] UDP header [42:53] BTH header
//     //   [54:63] first 10 bytes of payload (or AETH+padding for ACK)
//     // ================================================================
//     task build_header_beat;
//         input [47:0] dst_mac;
//         input [47:0] src_mac;
//         input [31:0] dst_ip;
//         input [31:0] src_ip;
//         input [15:0] dst_udp_port;
//         input [15:0] src_udp_port;
//         input [7:0]  opcode;
//         input [31:0] qpn;
//         input [31:0] psn;
//         input [15:0] payload_len;
//         output [DATA_W-1:0] beat;
//         reg [15:0] udp_total_len;
//         reg [15:0] ip_total_len;
//         // reg [15:0] ip_total_len;
//         // reg [15:0] udp_len;
//         begin
//             beat = {DATA_W{1'b0}};
//             // ip_total_len = 16'd40 + payload_len;
//             // udp_len      = 16'd20 + payload_len;

//             // =================================================================
//             // [原代码: 整数位段塞入, byte 0 实际落在 [47:40], 不是真 CMAC wire 字节序]
//             // 保留作对照, 字节序治本后由下方逐字节翻转版本替代.
//             // ----------------------------------------------------------------
//             // // Ethernet (bytes 0-13)
//             // beat[47:0]     = dst_mac;
//             // beat[95:48]    = src_mac;
//             // beat[111:96]   = 16'h0001;
//             //
//             // // IP (bytes 14-33)
//             // beat[119:112]  = 8'h01;
//             // beat[127:120]  = 8'h00;
//             // beat[143:128]  = 16'h0009;
//             // beat[159:144]  = 16'h0002;
//             // beat[175:160]  = 8'h01;
//             // beat[183:176]  = 8'h08;
//             // beat[191:184]  = 8'h01;
//             // beat[207:192]  = 16'h11;
//             // beat[239:208]  = src_ip;
//             // beat[271:240]  = dst_ip;
//             //
//             // // UDP (bytes 34-41)
//             // beat[287:272]  = src_udp_port;
//             // beat[303:288]  = dst_udp_port;
//             // beat[319:304]  = 16'd1024;
//             // beat[335:320]  = 16'h0011;
//             //
//             // // BTH (bytes 42-53)
//             // beat[343:336]  = opcode;
//             // beat[351:344]  = 8'h01;
//             // beat[367:352]  = 16'h0011;
//             // beat[399:368]  = qpn;
//             // beat[431:400]  = psn;
//             //
//             // // Payload
//             // beat[432 +: 80] = 80'h5555_4444_3333_2222_1111;
//             // =================================================================

//             // =================================================================
//             // 字节序治本: 真实模拟 CMAC wire 字节序 (byte 0 在 tdata LSB).
//             // 输入参数 dst_mac/src_ip/qpn/psn 等都是 host 视角真整数, 这里逐字节
//             // 翻转写入 beat, 让仿真和上板 CMAC 看到一致的字节流.
//             // payload_len 是 "纯 payload 字节数" (host 语义), 与 parser
//             // s1_data_length 一致, 直接推 IP/UDP total length.
//             // =================================================================
//             udp_total_len = 16'd8  + 16'd12 + payload_len;   // UDP header + BTH + payload (data)
//             ip_total_len  = 16'd20 + udp_total_len;          // + IP header

//             // Ethernet (wire byte 0~13)
//             // dst_mac (host MSB) -> wire byte 0 -> beat[7:0]
//             beat[  7:  0] = dst_mac[47:40];
//             beat[ 15:  8] = dst_mac[39:32];
//             beat[ 23: 16] = dst_mac[31:24];
//             beat[ 31: 24] = dst_mac[23:16];
//             beat[ 39: 32] = dst_mac[15: 8];
//             beat[ 47: 40] = dst_mac[ 7: 0];
//             beat[ 55: 48] = src_mac[47:40];
//             beat[ 63: 56] = src_mac[39:32];
//             beat[ 71: 64] = src_mac[31:24];
//             beat[ 79: 72] = src_mac[23:16];
//             beat[ 87: 80] = src_mac[15: 8];
//             beat[ 95: 88] = src_mac[ 7: 0];
//             // eth_type: tb 原值 0x0001 (低位 = byte 13). 这里保留原 magic value:
//             //   wire byte 12 = 0x00, byte 13 = 0x01
//             beat[103: 96] = 8'h00;
//             beat[111:104] = 8'h01;

//             // IP Header (wire byte 14~33)
//             beat[119:112] = 8'h01;                  // byte 14 (tb 原 magic, 非标准 IP ver/ihl)
//             beat[127:120] = 8'h00;                  // byte 15
//             beat[135:128] = ip_total_len[15: 8];    // byte 16: IP total length MSB
//             beat[143:136] = ip_total_len[ 7: 0];    // byte 17
//             beat[151:144] = 8'h00;                  // byte 18 (tb 原值 0x0009: byte 18=0x00, byte 19=0x09)
//             beat[159:152] = 8'h09;                  // byte 19
//             beat[167:160] = 8'h00;                  // byte 20 (tb 原值 0x0002: byte 20=0x00, byte 21=0x02)
//             beat[175:168] = 8'h02;                  // byte 21
//             beat[183:176] = 8'h01;                  // byte 22 (tb 原 TTL=0x01)
//             beat[191:184] = 8'h08;                  // byte 23 (tb 原 protocol=0x08, 非标准)
//             beat[199:192] = 8'h00;                  // byte 24 checksum MSB
//             beat[207:200] = 8'h11;                  // byte 25 checksum LSB (tb 原值 0x11)
//             // src_ip wire byte 26~29
//             beat[215:208] = src_ip[31:24];
//             beat[223:216] = src_ip[23:16];
//             beat[231:224] = src_ip[15: 8];
//             beat[239:232] = src_ip[ 7: 0];
//             // dst_ip wire byte 30~33
//             beat[247:240] = dst_ip[31:24];
//             beat[255:248] = dst_ip[23:16];
//             beat[263:256] = dst_ip[15: 8];
//             beat[271:264] = dst_ip[ 7: 0];

//             // UDP Header (wire byte 34~41)
//             // src_port wire byte 34~35
//             beat[279:272] = src_udp_port[15: 8];
//             beat[287:280] = src_udp_port[ 7: 0];
//             // dst_port wire byte 36~37
//             beat[295:288] = dst_udp_port[15: 8];
//             beat[303:296] = dst_udp_port[ 7: 0];
//             // UDP length wire byte 38~39
//             beat[311:304] = udp_total_len[15: 8];
//             beat[319:312] = udp_total_len[ 7: 0];
//             // UDP checksum wire byte 40~41 (tb 原值 0x0011: byte 40=0x00, byte 41=0x11)
//             beat[327:320] = 8'h00;
//             beat[335:328] = 8'h11;

//             // BTH Header (wire byte 42~53)
//             beat[343:336] = opcode;                 // byte 42
//             beat[351:344] = 8'h01;                  // byte 43 (tb 原 se/m/pad=0x01)
//             beat[359:352] = 8'h00;                  // byte 44 (tb 原 pkey=0x0011: byte 44=0x00, byte 45=0x11)
//             beat[367:360] = 8'h11;                  // byte 45
//             // QPN wire byte 46~49
//             beat[375:368] = qpn[31:24];
//             beat[383:376] = qpn[23:16];
//             beat[391:384] = qpn[15: 8];
//             beat[399:392] = qpn[ 7: 0];
//             // PSN/APSN wire byte 50~53
//             beat[407:400] = psn[31:24];
//             beat[415:408] = psn[23:16];
//             beat[423:416] = psn[15: 8];
//             beat[431:424] = psn[ 7: 0];

//             // Payload first 10 bytes (wire byte 54~63, tb 原 magic value 保留)
//             beat[432 +: 80] = 80'h5555_4444_3333_2222_1111;

//         end
//     endtask

//     // ================================================================
//     // Task: send single-beat packet on a given port
//     // ================================================================
//     task send_packet_1beat;
//         input integer port;
//         input [DATA_W-1:0] data;
//         input [KEEP_W-1:0] keep;
//         input [TUSER_W-1:0] tuser;
//         begin
//             @(posedge clk);
//             s_axis_tdata[port]  <= data;
//             s_axis_tkeep[port]  <= keep;
//             s_axis_tuser[port]  <= tuser;
//             s_axis_tvalid[port] <= 1'b1;
//             s_axis_tlast[port]  <= 1'b1;
//             @(posedge clk);
// //            while (!s_axis_tready[port]) @(posedge clk);
//             s_axis_tvalid[port] <= 1'b0;
//             s_axis_tlast[port]  <= 1'b0;
//         end
//     endtask

//     // ================================================================
//     // Task: send multi-beat packet (header + N payload beats)
//     // ================================================================
//     task send_packet_multi;
//         input integer port;
//         input [DATA_W-1:0] header_beat;
//         input [TUSER_W-1:0] tuser;
//         input integer num_payload_beats;
//         integer i;
//         begin
//             // Beat 0: header
//             @(posedge clk);
//             s_axis_tdata[port]  <= header_beat;
//             s_axis_tkeep[port]  <= {KEEP_W{1'b1}};
//             s_axis_tuser[port]  <= tuser;
//             s_axis_tvalid[port] <= 1'b1;
//             s_axis_tlast[port]  <= (num_payload_beats == 0) ? 1'b1 : 1'b0;
//             @(posedge clk);
//             while (!s_axis_tready[port]) @(posedge clk);

//             // Payload beats
//             for (i = 0; i < num_payload_beats; i = i + 1) begin
//                 s_axis_tdata[port] <= {16{32'h0000_0001 + i}};
//                 s_axis_tkeep[port] <= {KEEP_W{1'b1}};
//                 s_axis_tlast[port] <= (i == num_payload_beats - 1) ? 1'b1 : 1'b0;
//                 @(posedge clk);
//                 while (!s_axis_tready[port]) @(posedge clk);
//             end

//             s_axis_tvalid[port] <= 1'b0;
//             s_axis_tlast[port]  <= 1'b0;
//         end
//     endtask

//     // ================================================================
//     // Egress monitor: capture and log packets on all output ports
//     // ================================================================
//     integer egress_pkt_count [0:NUM_PORTS-1];
//     reg [DATA_W-1:0] egress_first_beat [0:NUM_PORTS-1];
//     reg [7:0] egress_dst_port [0:NUM_PORTS-1];

//     genvar gi;
//     generate
//         for (gi = 0; gi < NUM_PORTS; gi = gi + 1) begin : gen_monitor
//             always @(posedge clk) begin
//                 if (!rst_n) begin
//                     egress_pkt_count[gi] <= 0;
//                     egress_first_beat[gi] <= {DATA_W{1'bx}};
//                 end else if (m_axis_tvalid[gi] && m_axis_tready[gi]) begin
//                     if (m_axis_tlast[gi]) begin
//                         egress_pkt_count[gi] <= egress_pkt_count[gi] + 1;
//                         $display("[%0t] EGRESS Port%0d: pkt #%0d complete, dst_port=0x%02h, first_data[31:0]=0x%08h",
//                                  $time, gi, egress_pkt_count[gi],
//                                  m_axis_tuser[gi][31:24],
//                                  (egress_first_beat[gi] === {DATA_W{1'bx}})
//                                      ? m_axis_tdata[gi][31:0]
//                                      : egress_first_beat[gi][31:0]);
//                         egress_first_beat[gi] <= {DATA_W{1'bx}};
//                     end else begin
//                         if (egress_first_beat[gi] === {DATA_W{1'bx}})
//                             egress_first_beat[gi] <= m_axis_tdata[gi];
//                     end
//                 end
//             end
//         end
//     endgenerate

//     // ================================================================
//     // Hash Connection Table Backdoor Config
//     // ================================================================
//     // Key format: {dst_mac, src_mac, src_ip, dst_ip, src_port, dst_port} = 192 bits
//     // Table entry: {root_info[1], key[192], valid[1]} = 194 bits
//     //
//     // Connection 0: root_info=1 (this node is root for this connection)
//     //   Used for root_up → port_retrans / down_broadcast scenarios
//     localparam HASH_KEY_WIDTH = 192;
//     localparam HASH_WIDTH     = 8;

//     reg [47:0] hit_src_mac_0  = 48'hAABBCCDDEEFF;
//     reg [47:0] hit_dst_mac_0  = 48'h112233445566;
//     reg [31:0] hit_src_ip_0   = 32'h0A000001;
//     reg [31:0] hit_dst_ip_0   = 32'h0A000002;
//     reg [15:0] hit_src_port_0 = 16'd1234;
//     reg [15:0] hit_dst_port_0 = 16'd5678;
//     reg        hit_root_info_0 = 1'b1;

//     wire [HASH_WIDTH-1:0] hit_hash_value_0;
//     reg [HASH_KEY_WIDTH-1:0] full_hit_key_0;

//     hash_function #(
//         .KEY_WIDTH(HASH_KEY_WIDTH),
//         .HASH_WIDTH(HASH_WIDTH)
//     ) tb_hash_func_0 (
//         .key_in({hit_dst_mac_0, hit_src_mac_0, hit_src_ip_0, hit_dst_ip_0, hit_src_port_0, hit_dst_port_0}),
//         .hash_out(hit_hash_value_0)
//     );

//     // Connection 1: root_info=0 (this node is NOT root)
//     //   Used for noroot_up → FAN_first_trans / FAN_retrans scenarios
//     reg [47:0] hit_src_mac_1  = 48'h112233DDEEFF;
//     reg [47:0] hit_dst_mac_1  = 48'hAABBCC445566;
//     reg [31:0] hit_src_ip_1   = 32'h0A000111;
//     reg [31:0] hit_dst_ip_1   = 32'h0A000222;
//     reg [15:0] hit_src_port_1 = 16'd1234;
//     reg [15:0] hit_dst_port_1 = 16'd5678;
//     reg        hit_root_info_1 = 1'b0;

//     wire [HASH_WIDTH-1:0] hit_hash_value_1;
//     reg [HASH_KEY_WIDTH-1:0] full_hit_key_1;

//     hash_function #(
//         .KEY_WIDTH(HASH_KEY_WIDTH),
//         .HASH_WIDTH(HASH_WIDTH)
//     ) tb_hash_func_1 (
//         .key_in({hit_dst_mac_1, hit_src_mac_1, hit_src_ip_1, hit_dst_ip_1, hit_src_port_1, hit_dst_port_1}),
//         .hash_out(hit_hash_value_1)
//     );

//     // Hierarchical path to hash connection table inside DUT
//     // nf_datapath_4port → allreduce_offload_wrapper → allreduce_offload_top → parser → hash_connection_table
//     `define HASH_TBL u_dut.u_allreduce_wrapper.u_allreduce.allreduce_parser.u_connection_table.table_mem

//     // ================================================================
//     // Init
//     // ================================================================
//     localparam [7:0] OPCODE_FIRST = 8'h0;
//     integer p;
//     initial begin
//         for (p = 0; p < NUM_PORTS; p = p + 1) begin
//             s_axis_tdata[p]  = {DATA_W{1'b0}};
//             s_axis_tkeep[p]  = {KEEP_W{1'b0}};
//             s_axis_tuser[p]  = {TUSER_W{1'b0}};
//         end
//         s_axis_tvalid = 0;
//         s_axis_tlast  = 0;
//         m_axis_tready = {NUM_PORTS{1'b1}};
//     end

//     // ================================================================
//     // Test Scenarios
//     // ================================================================
//     reg [DATA_W-1:0] hdr_beat;

//     initial begin
//         $display("========================================");
//         $display("  AllReduce + Switch Datapath Testbench");
//         $display("========================================");

//         wait(rst_n == 1);
//         repeat(200) @(posedge clk);

//         // ==========================================================
//         // Step 0: Backdoor write hash connection table
//         // ==========================================================
//         $display("\n--- Step 0: Configure hash connection table ---");

//         @(posedge clk);
//         full_hit_key_0 = {hit_dst_mac_0, hit_src_mac_0, hit_src_ip_0, hit_dst_ip_0, hit_src_port_0, hit_dst_port_0};
//         `HASH_TBL[hit_hash_value_0][0] = {hit_root_info_0, full_hit_key_0, 1'b1};
//         $display("  Connection 0: hash=0x%02h, root_info=%0b, key=0x%048h",
//                  hit_hash_value_0, hit_root_info_0, full_hit_key_0);

//         @(posedge clk);
//         full_hit_key_1 = {hit_dst_mac_1, hit_src_mac_1, hit_src_ip_1, hit_dst_ip_1, hit_src_port_1, hit_dst_port_1};
//         `HASH_TBL[hit_hash_value_1][0] = {hit_root_info_1, full_hit_key_1, 1'b1};
//         $display("  Connection 1: hash=0x%02h, root_info=%0b, key=0x%048h",
//                  hit_hash_value_1, hit_root_info_1, full_hit_key_1);

//         repeat(2) @(posedge clk);

//         // ==========================================================
//         // TEST 1: Pass-through (hash miss)
//         //   Send from Port0 with unknown MAC → hash miss → direct pass-through
//         //   OPL does MAC lookup → broadcast (unknown dst_mac)
//         //   Expected: packet appears on all egress ports
//         // ==========================================================
// //        $display("\n--- TEST 1: Pass-through L2 packet (hash miss) from Port0 ---");
// //        build_header_beat(
// //            48'hFF_FF_FF_FF_FF_FF,  // dst_mac (broadcast)
// //            48'hDE_AD_BE_EF_00_00,  // src_mac (not in hash table)
// //            32'h0A000099,           // dst_ip
// //            32'h0A000001,           // src_ip
// //            16'd9999, 16'd8888,     // UDP ports (not matching hash entries)
// //            8'hFF,                  // opcode (invalid → hash miss guaranteed)
// //            32'h00000000,           // QPN
// //            32'h00000000,           // PSN
// //            16'd64,                 // payload_len
// //            hdr_beat
// //        );
// //        send_packet_1beat(0, hdr_beat, {KEEP_W{1'b1}},
// //                          build_tuser(8'h01, 16'd128));

// //        repeat(5) @(posedge clk);

// //        // ==========================================================
// //        // TEST 2: AllReduce aggregation (noroot connection, 2 child ports)
// //        //   Connection 1: root_info=0 → this node is NOT root
// //        //   Port0 sends OPCODE_FIRST with PSN=0 → Typer: TYPE_NOROOT_DATA_UP
// //        //   Port1 sends same PSN=0 → aggregation completes
// //        //   Expected: aggregated result sent to parent port (Port2, cfg_parent_port=0x04)
// //        //   Wrapper route_type = ROUTE_TO_PARENT → TUSER[31:24] = 0x04
// //        // ==========================================================
//         $display("\n--- TEST 2: AllReduce from Port0 (child, connection 1, PSN=0) ---");
//         build_header_beat(
//             hit_dst_mac_1, hit_src_mac_1,
//             hit_dst_ip_1, hit_src_ip_1,
//             hit_dst_port_1, hit_src_port_1,
//             OPCODE_FIRST,
//             32'h00000001,           // QPN
//             32'h00000000,           // PSN = 0
//             16'd1024,               // payload_len
//             hdr_beat
//         );
//         send_packet_multi(0, hdr_beat,
//                           build_tuser(8'h01, 16'd1078),
//                           16);

//         repeat(5) @(posedge clk);

//         $display("\n--- TEST 2b: AllReduce from Port1 (child, same connection, same PSN=0) ---");
//         build_header_beat(
//             hit_dst_mac_1, hit_src_mac_1,
//             hit_dst_ip_1, hit_src_ip_1,
//             hit_dst_port_1, hit_src_port_1,
//             OPCODE_FIRST,
//             32'h00000001,
//             32'h00000000,           // same PSN = 0
//             16'd1024,
//             hdr_beat
//         );
//         send_packet_multi(1, hdr_beat,
//                           build_tuser(8'h02, 16'd1078),
//                           16);

//         repeat(50) @(posedge clk);

// //        // ==========================================================
// //        // TEST 3: AllReduce root connection (root_info=1)
// //        //   Connection 0: root_info=1 → this node IS root
// //        //   Port0 sends data → Typer: TYPE_ROOT_DATA_UP
// //        //   Port1 sends same PSN → aggregation completes
// //        //   Expected: aggregated result broadcast to children (ROUTE_TO_CHILDREN_ALL)
// //        //   Wrapper → TUSER[31:24] = cfg_child_port_mask = 0x03 (Port0|Port1)
// //        // ==========================================================
// //        $display("\n--- TEST 3: Root aggregation from Port0 (connection 0, PSN=0) ---");
// //        build_header_beat(
// //            hit_dst_mac_0, hit_src_mac_0,
// //            hit_dst_ip_0, hit_src_ip_0,
// //            hit_dst_port_0, hit_src_port_0,
// //            OPCODE_FIRST,
// //            32'h00000001,
// //            32'h00000003,
// //            16'd1024,
// //            hdr_beat
// //        );
// //        send_packet_multi(0, hdr_beat,
// //                          build_tuser(8'h01, 16'd1078),
// //                          16);

// //        repeat(5) @(posedge clk);

// //        $display("\n--- TEST 3b: Root aggregation from Port1 (same connection, same PSN) ---");
// //        build_header_beat(
// //            hit_dst_mac_0, hit_src_mac_0,
// //            hit_dst_ip_0, hit_src_ip_0,
// //            hit_dst_port_0, hit_src_port_0,
// //            OPCODE_FIRST,
// //            32'h00000001,
// //            32'h00000003,
// //            16'd1024,
// //            hdr_beat
// //        );
// //        send_packet_multi(1, hdr_beat,
// //                          build_tuser(8'h02, 16'd1078),
// //                          16);

// //        repeat(50) @(posedge clk);

// //        // ==========================================================
// //        // TEST 4: Down broadcast from parent port (Port2)
// //        //   Connection 1: root_info=0, Port2 = FAN_IN = parent
// //        //   Typer: ingress_port=2 == FAN_IN → TYPE_DATA_DOWN
// //        //   Expected: down_broadcast → ROUTE_TO_CHILDREN_ALL
// //        // ==========================================================
// //        $display("\n--- TEST 4: Data from parent Port2 (TYPE_DATA_DOWN) ---");
// //        build_header_beat(
// //            hit_dst_mac_1, hit_src_mac_1,
// //            hit_dst_ip_1, hit_src_ip_1,
// //            hit_dst_port_1, hit_src_port_1,
// //            OPCODE_FIRST,
// //            32'h00000001,
// //            32'h00000005,           // different PSN
// //            16'd1024,
// //            hdr_beat
// //        );
// //        send_packet_multi(0, hdr_beat,
// //                          build_tuser(8'h01, 16'd1078),
// //                          16);

// //        repeat(10) @(posedge clk);
        
// //        build_header_beat(
// //            hit_dst_mac_1, hit_src_mac_1,
// //            hit_dst_ip_1, hit_src_ip_1,
// //            hit_dst_port_1, hit_src_port_1,
// //            OPCODE_FIRST,
// //            32'h00000001,
// //            32'h00000005,           // different PSN
// //            16'd1024,
// //            hdr_beat
// //        );
// //        send_packet_multi(1, hdr_beat,
// //                          build_tuser(8'h02, 16'd1078),
// //                          16);

// //        repeat(50) @(posedge clk);
        
// //        build_header_beat(
// //            hit_dst_mac_1, hit_src_mac_1,
// //            hit_dst_ip_1, hit_src_ip_1,
// //            hit_dst_port_1, hit_src_port_1,
// //            OPCODE_FIRST,
// //            32'h00000001,
// //            32'h00000005,           // different PSN
// //            16'd1024,
// //            hdr_beat
// //        );
// //        send_packet_multi(2, hdr_beat,
// //                          build_tuser(8'h04, 16'd1078),
// //                          16);

// //        repeat(50) @(posedge clk);

//         // ==========================================================
//         // TEST 5: ACK from child Port0 to parent
//         //   Connection 1: root_info=0
//         //   Typer: ingress_port=0 != FAN_IN, opcode=ACK → TYPE_ACK_UP
//         //   Expected: ROUTE_TO_PARENT → dst_port = cfg_parent_port = 0x04 (Port2)
//         // ==========================================================
// //        $display("\n--- TEST 5: ACK from child Port0 (TYPE_ACK_UP) ---");
// //        build_header_beat(
// //            hit_dst_mac_1, hit_src_mac_1,
// //            hit_dst_ip_1, hit_src_ip_1,
// //            hit_dst_port_1, hit_src_port_1,
// //            OPCODE_ACK,
// //            32'h00000001,
// //            32'h00000000,
// //            16'd0,
// //            hdr_beat
// //        );
// //        send_packet_1beat(0, hdr_beat, {KEEP_W{1'b1}},
// //                          build_tuser(8'h01, 16'd58));

// //        repeat(50) @(posedge clk);

//         // ----------------------------------------------------------
//         // Summary
//         // ----------------------------------------------------------
//         $display("\n========================================");
//         $display("  Test Complete. Egress packet counts:");
//         for (p = 0; p < NUM_PORTS; p = p + 1)
//             $display("    Port%0d: %0d packets", p, egress_pkt_count[p]);
//         $display("========================================");

//         #200;
//         $finish;
//     end

//     // ================================================================
//     // Pipeline stage monitors (internal signals)
//     // ================================================================

//     // Monitor: CDC FIFO in (input_arbiter 322MHz -> allreduce 250MHz)
//     always @(posedge clk) begin
//         if (u_dut.s_axis_opl_tvalid && u_dut.s_axis_opl_tready)
//             $display("[%0t] CDC_IN wr: tdata[31:0]=0x%08h tlast=%0b full=%0b",
//                      $time,
//                      u_dut.s_axis_opl_tdata[31:0],
//                      u_dut.s_axis_opl_tlast,
//                      u_dut.cdc_in_full);
//         if (u_dut.ar_s_tvalid && u_dut.ar_s_tready)
//             $display("[%0t] CDC_IN rd: tdata[31:0]=0x%08h tlast=%0b empty=%0b",
//                      $time,
//                      u_dut.ar_s_tdata[31:0],
//                      u_dut.ar_s_tlast,
//                      u_dut.cdc_in_empty);
//     end

//     // Monitor: CDC FIFO out (allreduce 250MHz -> OPL 322MHz)
//     always @(posedge clk) begin
//         if (u_dut.ar_m_tvalid && u_dut.ar_m_tready)
//             $display("[%0t] CDC_OUT wr: tdata[31:0]=0x%08h tuser[31:24]=0x%02h tlast=%0b full=%0b",
//                      $time,
//                      u_dut.ar_m_tdata[31:0],
//                      u_dut.ar_m_tuser[31:24],
//                      u_dut.ar_m_tlast,
//                      u_dut.cdc_out_full);
//         if (u_dut.allreduce_to_opl_tvalid && u_dut.allreduce_to_opl_tready)
//             $display("[%0t] CDC_OUT rd: tdata[31:0]=0x%08h tuser[31:24]=0x%02h tlast=%0b empty=%0b",
//                      $time,
//                      u_dut.allreduce_to_opl_tdata[31:0],
//                      u_dut.allreduce_to_opl_tuser[31:24],
//                      u_dut.allreduce_to_opl_tlast,
//                      u_dut.cdc_out_empty);
//     end

//     // Monitor: parser hash hit
//     always @(posedge clk) begin
//         if (u_dut.u_allreduce_wrapper.u_allreduce.allreduce_parser.s4_valid) begin
//             $display("[%0t] PARSER s4: hit=%0b root=%0b agg_en=%0b egress_en=%0b opcode=0x%02h psn=%0d ingress=%0d",
//                      $time,
//                      u_dut.u_allreduce_wrapper.u_allreduce.allreduce_parser.s4_lookup_hit,
//                      u_dut.u_allreduce_wrapper.u_allreduce.allreduce_parser.s4_root_info,
//                      u_dut.u_allreduce_wrapper.u_allreduce.allreduce_parser.s4_aggregate_en,
//                      u_dut.u_allreduce_wrapper.u_allreduce.allreduce_parser.s4_egress_en,
//                      u_dut.u_allreduce_wrapper.u_allreduce.allreduce_parser.s4_opcode,
//                      u_dut.u_allreduce_wrapper.u_allreduce.allreduce_parser.s4_psn_out,
//                      u_dut.u_allreduce_wrapper.u_allreduce.allreduce_parser.s4_ingress_port);
//         end
//     end

//     // Monitor: Typer classification
//     always @(posedge clk) begin
//         if (u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_typer.s2_valid) begin
//             $display("[%0t] TYPER: root_up=%0b noroot_up=%0b data_down=%0b ack_up=%0b ack_down=%0b metadata=0x%06h",
//                      $time,
//                      u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_typer.data_root_up_en,
//                      u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_typer.data_noroot_up_en,
//                      u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_typer.data_down_en,
//                      u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_typer.ack_up_en,
//                      u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_typer.ack_down_en,
//                      u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_typer.metadata_with_type);
//         end
//     end

//     // Monitor: Typer -> down_broadcast handshake
//     always @(posedge clk) begin
//         if (u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.typer_to_down_broadcast_valid_r) begin
//             $display("[%0t] TYPER->DOWN_BC: valid=1 ready=%0b",
//                      $time,
//                      u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.down_broadcast_to_typer_in_ready);
//         end
//     end

//     // Monitor: down_broadcast_checkor pipeline
//     always @(posedge clk) begin
//         if (u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_down_broadcast_checkor_arrival_updater.s1_valid)
//             $display("[%0t] DOWN_BC s1: psn=%0d ingress=%0d root=%0b",
//                      $time,
//                      u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_down_broadcast_checkor_arrival_updater.s1_idx_psn,
//                      u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_down_broadcast_checkor_arrival_updater.s1_ingress_port,
//                      u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_down_broadcast_checkor_arrival_updater.s1_root_info);
//         if (u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_down_broadcast_checkor_arrival_updater.s4_valid)
//             $display("[%0t] DOWN_BC s4: need_bc=%0b first_trans=%0b",
//                      $time,
//                      u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_down_broadcast_checkor_arrival_updater.s4_need_broadcast,
//                      u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_down_broadcast_checkor_arrival_updater.s4_FAN_first_trans);
//     end

//     // Monitor: down_broadcast -> buffer handshake
//     always @(posedge clk) begin
//         if (u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.down_broadcast_to_buffer_valid)
//             $display("[%0t] DOWN_BC->BUFFER: valid=1 ready=%0b copy_en=%0b",
//                      $time,
//                      u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.buffer_to_down_broadcast_ready,
//                      u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.down_broadcast_to_buffer_copy_buffer_en);
//     end

//     // Monitor: buffer -> deparser down_broadcast
//     always @(posedge clk) begin
//         if (u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.buffer_to_deparser_down_down_broadcast_ok_en)
//             $display("[%0t] BUFFER->DEPARSER: down_broadcast_ok_en fired", $time);
//     end

//     // Monitor: deparser state transitions
//     reg [2:0] prev_deparser_state;
//     always @(posedge clk) begin
//         prev_deparser_state <= u_dut.u_allreduce_wrapper.u_allreduce.allreduce_deparser.current_state;
//         if (u_dut.u_allreduce_wrapper.u_allreduce.allreduce_deparser.current_state != prev_deparser_state) begin
//             $display("[%0t] DEPARSER state: %0d -> %0d  route_type=%0d is_agg=%0b",
//                      $time,
//                      prev_deparser_state,
//                      u_dut.u_allreduce_wrapper.u_allreduce.allreduce_deparser.current_state,
//                      u_dut.u_allreduce_wrapper.u_allreduce.allreduce_deparser.latched_route_type,
//                      u_dut.u_allreduce_wrapper.u_allreduce.allreduce_deparser.m_axis_is_aggregated);
//         end
//     end

//     // Monitor: aggregator output enables
//     always @(posedge clk) begin
//         if (u_dut.u_allreduce_wrapper.u_allreduce.aggregator_to_deparser_FAN_first_trans_en_out)
//             $display("[%0t] AGGREGATOR: FAN_first_trans_en fired", $time);
//         if (u_dut.u_allreduce_wrapper.u_allreduce.aggregator_to_deparser_FAN_retrans_en_out)
//             $display("[%0t] AGGREGATOR: FAN_retrans_en fired", $time);
//         if (u_dut.u_allreduce_wrapper.u_allreduce.aggregator_to_deparser_down_broadcast_en_out)
//             $display("[%0t] AGGREGATOR: down_broadcast_en fired", $time);
//         if (u_dut.u_allreduce_wrapper.u_allreduce.aggregator_to_deparser_ack_build_en_out)
//             $display("[%0t] AGGREGATOR: ack_build_en fired", $time);
//         if (u_dut.u_allreduce_wrapper.u_allreduce.aggregator_to_deparser_port_retrans_en_out)
//             $display("[%0t] AGGREGATOR: port_retrans_en fired", $time);
//         if (u_dut.u_allreduce_wrapper.u_allreduce.aggregator_to_deparser_ack_down_en_out)
//             $display("[%0t] AGGREGATOR: ack_down_en fired", $time);
//     end

//     // Monitor: wrapper output tuser dst_port
//     always @(posedge clk) begin
//         if (u_dut.u_allreduce_wrapper.m_axis_tvalid && u_dut.u_allreduce_wrapper.m_axis_tready) begin
//             $display("[%0t] WRAPPER out: tuser[31:24]=0x%02h tuser[23:16]=0x%02h is_agg=%0b route=%0d tlast=%0b",
//                      $time,
//                      u_dut.u_allreduce_wrapper.m_axis_tuser[31:24],
//                      u_dut.u_allreduce_wrapper.m_axis_tuser[23:16],
//                      u_dut.u_allreduce_wrapper.u_allreduce.allreduce_deparser.m_axis_is_aggregated,
//                      u_dut.u_allreduce_wrapper.u_allreduce.allreduce_deparser.m_axis_route_type,
//                      u_dut.u_allreduce_wrapper.m_axis_tlast);
//         end
//     end

//     // Monitor: OPL dst_port decision
//     always @(posedge clk) begin
//         if (u_dut.u_output_port_lookup.m_axis_tvalid &&
//             u_dut.u_output_port_lookup.m_axis_tready &&
//             u_dut.u_output_port_lookup.m_axis_tlast) begin
//             $display("[%0t] OPL out: dst_port=0x%02h (tuser[31:24])",
//                      $time,
//                      u_dut.u_output_port_lookup.m_axis_tuser[31:24]);
//         end
//     end

//     // ================================================================
//     // Waveform dump
//     // ================================================================
//     initial begin
//         $dumpfile("tb_allreduce_switch.vcd");
//         $dumpvars(0, tb_allreduce_switch_datapath);
//     end

// endmodule


module tb_allreduce_switch_datapath;

    // ================================================================
    // Parameters
    // ================================================================
    localparam DATA_W   = 512;
    localparam KEEP_W   = 64;
    localparam TUSER_W  = 128;
    localparam NUM_PORTS = 4;
    localparam CLK_PERIOD = 3.103;  // 322 MHz

    // RoCEv2 opcodes (matches Typer.v)
    localparam [7:0] OPCODE_SEND_ONLY = 8'h04;
    localparam [7:0] OPCODE_ACK       = 8'h11;

    // ================================================================
    // Clock & Reset
    // ================================================================
    reg clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg rst_n = 0;
    initial begin
        #100;
        rst_n = 1;
    end

    // ================================================================
    // DUT signals
    // ================================================================
    // Ingress (4 ports)
    reg  [DATA_W-1:0]   s_axis_tdata  [0:NUM_PORTS-1];
    reg  [KEEP_W-1:0]   s_axis_tkeep  [0:NUM_PORTS-1];
    reg  [TUSER_W-1:0]  s_axis_tuser  [0:NUM_PORTS-1];
    reg  [NUM_PORTS-1:0] s_axis_tvalid;
    wire [NUM_PORTS-1:0] s_axis_tready;
    reg  [NUM_PORTS-1:0] s_axis_tlast;

    // Egress (4 ports)
    wire [DATA_W-1:0]   m_axis_tdata  [0:NUM_PORTS-1];
    wire [KEEP_W-1:0]   m_axis_tkeep  [0:NUM_PORTS-1];
    wire [TUSER_W-1:0]  m_axis_tuser  [0:NUM_PORTS-1];
    wire [NUM_PORTS-1:0] m_axis_tvalid;
    reg  [NUM_PORTS-1:0] m_axis_tready;
    wire [NUM_PORTS-1:0] m_axis_tlast;

    // ================================================================
    // DUT instantiation
    // ================================================================
    nf_datapath_4port #(
        .C_S_AXI_DATA_WIDTH  (32),
        .C_S_AXI_ADDR_WIDTH  (32),
        .C_BASEADDR          (32'h0),
        .C_M_AXIS_DATA_WIDTH (DATA_W),
        .C_S_AXIS_DATA_WIDTH (DATA_W),
        .C_M_AXIS_TUSER_WIDTH(TUSER_W),
        .C_S_AXIS_TUSER_WIDTH(TUSER_W),
        .NUM_QUEUES          (NUM_PORTS)
    ) u_dut (
        .axis_aclk   (clk),
        .axis_resetn (rst_n),
        .axi_aclk    (clk),
        .axi_resetn  (rst_n),
        .allreduce_clk   (clk),
        .allreduce_rst_n (rst_n),

        // AXI-Lite: tie off
        .S0_AXI_AWADDR(32'h0),.S0_AXI_AWVALID(1'b0),.S0_AXI_WDATA(32'h0),
        .S0_AXI_WSTRB(4'h0),.S0_AXI_WVALID(1'b0),.S0_AXI_BREADY(1'b1),
        .S0_AXI_ARADDR(32'h0),.S0_AXI_ARVALID(1'b0),.S0_AXI_RREADY(1'b1),
        .S0_AXI_ARREADY(),.S0_AXI_RDATA(),.S0_AXI_RRESP(),
        .S0_AXI_RVALID(),.S0_AXI_WREADY(),.S0_AXI_BRESP(),
        .S0_AXI_BVALID(),.S0_AXI_AWREADY(),

        .S1_AXI_AWADDR(32'h0),.S1_AXI_AWVALID(1'b0),.S1_AXI_WDATA(32'h0),
        .S1_AXI_WSTRB(4'h0),.S1_AXI_WVALID(1'b0),.S1_AXI_BREADY(1'b1),
        .S1_AXI_ARADDR(32'h0),.S1_AXI_ARVALID(1'b0),.S1_AXI_RREADY(1'b1),
        .S1_AXI_ARREADY(),.S1_AXI_RDATA(),.S1_AXI_RRESP(),
        .S1_AXI_RVALID(),.S1_AXI_WREADY(),.S1_AXI_BRESP(),
        .S1_AXI_BVALID(),.S1_AXI_AWREADY(),

        .S2_AXI_AWADDR(32'h0),.S2_AXI_AWVALID(1'b0),.S2_AXI_WDATA(32'h0),
        .S2_AXI_WSTRB(4'h0),.S2_AXI_WVALID(1'b0),.S2_AXI_BREADY(1'b1),
        .S2_AXI_ARADDR(32'h0),.S2_AXI_ARVALID(1'b0),.S2_AXI_RREADY(1'b1),
        .S2_AXI_ARREADY(),.S2_AXI_RDATA(),.S2_AXI_RRESP(),
        .S2_AXI_RVALID(),.S2_AXI_WREADY(),.S2_AXI_BRESP(),
        .S2_AXI_BVALID(),.S2_AXI_AWREADY(),

        // PLACEHOLDER_DUT_PORTS
        // Ingress
        .s_axis_0_tdata (s_axis_tdata[0]), .s_axis_0_tkeep (s_axis_tkeep[0]),
        .s_axis_0_tuser (s_axis_tuser[0]), .s_axis_0_tvalid(s_axis_tvalid[0]),
        .s_axis_0_tready(s_axis_tready[0]),.s_axis_0_tlast (s_axis_tlast[0]),

        .s_axis_1_tdata (s_axis_tdata[1]), .s_axis_1_tkeep (s_axis_tkeep[1]),
        .s_axis_1_tuser (s_axis_tuser[1]), .s_axis_1_tvalid(s_axis_tvalid[1]),
        .s_axis_1_tready(s_axis_tready[1]),.s_axis_1_tlast (s_axis_tlast[1]),

        .s_axis_2_tdata (s_axis_tdata[2]), .s_axis_2_tkeep (s_axis_tkeep[2]),
        .s_axis_2_tuser (s_axis_tuser[2]), .s_axis_2_tvalid(s_axis_tvalid[2]),
        .s_axis_2_tready(s_axis_tready[2]),.s_axis_2_tlast (s_axis_tlast[2]),

        .s_axis_3_tdata (s_axis_tdata[3]), .s_axis_3_tkeep (s_axis_tkeep[3]),
        .s_axis_3_tuser (s_axis_tuser[3]), .s_axis_3_tvalid(s_axis_tvalid[3]),
        .s_axis_3_tready(s_axis_tready[3]),.s_axis_3_tlast (s_axis_tlast[3]),

        // Egress
        .m_axis_0_tdata (m_axis_tdata[0]), .m_axis_0_tkeep (m_axis_tkeep[0]),
        .m_axis_0_tuser (m_axis_tuser[0]), .m_axis_0_tvalid(m_axis_tvalid[0]),
        .m_axis_0_tready(m_axis_tready[0]),.m_axis_0_tlast (m_axis_tlast[0]),

        .m_axis_1_tdata (m_axis_tdata[1]), .m_axis_1_tkeep (m_axis_tkeep[1]),
        .m_axis_1_tuser (m_axis_tuser[1]), .m_axis_1_tvalid(m_axis_tvalid[1]),
        .m_axis_1_tready(m_axis_tready[1]),.m_axis_1_tlast (m_axis_tlast[1]),

        .m_axis_2_tdata (m_axis_tdata[2]), .m_axis_2_tkeep (m_axis_tkeep[2]),
        .m_axis_2_tuser (m_axis_tuser[2]), .m_axis_2_tvalid(m_axis_tvalid[2]),
        .m_axis_2_tready(m_axis_tready[2]),.m_axis_2_tlast (m_axis_tlast[2]),

        .m_axis_3_tdata (m_axis_tdata[3]), .m_axis_3_tkeep (m_axis_tkeep[3]),
        .m_axis_3_tuser (m_axis_tuser[3]), .m_axis_3_tvalid(m_axis_tvalid[3]),
        .m_axis_3_tready(m_axis_tready[3]),.m_axis_3_tlast (m_axis_tlast[3])
    );

    // ================================================================
    // Helper: build TUSER
    // ================================================================
    function [TUSER_W-1:0] build_tuser;
        input [7:0] src_port_1hot;
        input [15:0] pkt_len;
        begin
            build_tuser = {TUSER_W{1'b0}};
            build_tuser[23:16] = src_port_1hot;
            build_tuser[15:0]  = pkt_len;
        end
    endfunction

    // ================================================================
    // Helper: build Ethernet + IP + UDP + BTH header in 512-bit beat
    //   Byte layout (little-endian in 512-bit word):
    //   [0:5]   dst_mac    [6:11]  src_mac    [12:13] eth_type=0x0800
    //   [14:33] IP header  [34:41] UDP header [42:53] BTH header
    //   [54:63] first 10 bytes of payload (or AETH+padding for ACK)
    // ================================================================
    task build_header_beat;
        input [47:0] dst_mac;
        input [47:0] src_mac;
        input [31:0] dst_ip;
        input [31:0] src_ip;
        input [15:0] dst_udp_port;
        input [15:0] src_udp_port;
        input [7:0]  opcode;
        input [31:0] qpn;
        input [31:0] psn;
        input [15:0] payload_len;
        output [DATA_W-1:0] beat;
        reg [15:0] udp_total_len;
        reg [15:0] ip_total_len;
        begin
            beat = {DATA_W{1'b0}};
            udp_total_len = 16'd8 + 16'd12 + payload_len;
            ip_total_len  = 16'd20 + udp_total_len;

            // Ethernet (wire byte 0~13): host MSB -> wire byte 0 -> beat LSB
            beat[  7:  0] = dst_mac[47:40];
            beat[ 15:  8] = dst_mac[39:32];
            beat[ 23: 16] = dst_mac[31:24];
            beat[ 31: 24] = dst_mac[23:16];
            beat[ 39: 32] = dst_mac[15: 8];
            beat[ 47: 40] = dst_mac[ 7: 0];
            beat[ 55: 48] = src_mac[47:40];
            beat[ 63: 56] = src_mac[39:32];
            beat[ 71: 64] = src_mac[31:24];
            beat[ 79: 72] = src_mac[23:16];
            beat[ 87: 80] = src_mac[15: 8];
            beat[ 95: 88] = src_mac[ 7: 0];
            beat[103: 96] = 8'h08;
            beat[111:104] = 8'h00;

            // IP Header (wire byte 14~33)
            beat[119:112] = 8'h45;
            beat[127:120] = 8'h00;
            beat[135:128] = ip_total_len[15:8];
            beat[143:136] = ip_total_len[7:0];
            beat[151:144] = 8'h11;
            beat[159:152] = 8'h11;
            beat[167:160] = 8'h40;
            beat[175:168] = 8'h00;
            beat[183:176] = 8'h40;
            beat[191:184] = 8'h11;
            beat[199:192] = 8'h00;
            beat[207:200] = 8'h00;
            beat[215:208] = src_ip[31:24];
            beat[223:216] = src_ip[23:16];
            beat[231:224] = src_ip[15: 8];
            beat[239:232] = src_ip[ 7: 0];
            beat[247:240] = dst_ip[31:24];
            beat[255:248] = dst_ip[23:16];
            beat[263:256] = dst_ip[15: 8];
            beat[271:264] = dst_ip[ 7: 0];

            // UDP Header (wire byte 34~41)
            beat[279:272] = src_udp_port[15:8];
            beat[287:280] = src_udp_port[7:0];
            beat[295:288] = dst_udp_port[15:8];
            beat[303:296] = dst_udp_port[7:0];
            beat[311:304] = udp_total_len[15:8];
            beat[319:312] = udp_total_len[7:0];
            beat[327:320] = 8'h00;
            beat[335:328] = 8'h00;

            // BTH Header (wire byte 42~53)
            beat[343:336] = opcode;
            beat[351:344] = 8'h00;
            beat[359:352] = 8'hFF;
            beat[367:360] = 8'hFF;
            beat[375:368] = qpn[31:24];
            beat[383:376] = qpn[23:16];
            beat[391:384] = qpn[15: 8];
            beat[399:392] = qpn[ 7: 0];
            beat[407:400] = psn[31:24];
            beat[415:408] = psn[23:16];
            beat[423:416] = psn[15: 8];
            beat[431:424] = psn[ 7: 0];

            // Payload first 10 bytes (wire byte 54~63)
            beat[432 +: 80] = 80'h1111_2222_3333_4444_5555;


        end
    endtask

    // ================================================================
    // Task: send single-beat packet on a given port
    // ================================================================
    task send_packet_1beat;
        input integer port;
        input [DATA_W-1:0] data;
        input [KEEP_W-1:0] keep;
        input [TUSER_W-1:0] tuser;
        begin
            @(posedge clk);
            s_axis_tdata[port]  <= data;
            s_axis_tkeep[port]  <= keep;
            s_axis_tuser[port]  <= tuser;
            s_axis_tvalid[port] <= 1'b1;
            s_axis_tlast[port]  <= 1'b1;
            @(posedge clk);
            while (!s_axis_tready[port]) @(posedge clk);
            s_axis_tvalid[port] <= 1'b0;
            s_axis_tlast[port]  <= 1'b0;
        end
    endtask

    // ================================================================
    // Task: send multi-beat packet (header + N payload beats)
    // ================================================================
    task send_packet_multi;
        input integer port;
        input [DATA_W-1:0] header_beat;
        input [TUSER_W-1:0] tuser;
        input integer num_payload_beats;
        integer i;
        begin
            // Beat 0: header
            @(posedge clk);
            s_axis_tdata[port]  <= header_beat;
            s_axis_tkeep[port]  <= {KEEP_W{1'b1}};
            s_axis_tuser[port]  <= tuser;
            s_axis_tvalid[port] <= 1'b1;
            s_axis_tlast[port]  <= (num_payload_beats == 0) ? 1'b1 : 1'b0;
            @(posedge clk);
            while (!s_axis_tready[port]) @(posedge clk);

            // Payload beats
            for (i = 0; i < num_payload_beats; i = i + 1) begin
                s_axis_tdata[port] <= {16{32'h0000_0001 + i}};
                s_axis_tkeep[port] <= {KEEP_W{1'b1}};
                s_axis_tlast[port] <= (i == num_payload_beats - 1) ? 1'b1 : 1'b0;
                @(posedge clk);
                while (!s_axis_tready[port]) @(posedge clk);
            end

            s_axis_tvalid[port] <= 1'b0;
            s_axis_tlast[port]  <= 1'b0;
        end
    endtask

    // ================================================================
    // Egress monitor: capture and log packets on all output ports
    // ================================================================
    reg [31:0] egress_pkt_count [0:NUM_PORTS-1];
    reg [DATA_W-1:0] egress_first_beat [0:NUM_PORTS-1];
    reg [7:0] egress_dst_port [0:NUM_PORTS-1];

    reg [31:0] egress_beat_count [0:NUM_PORTS-1];

    genvar gi;
    generate
        for (gi = 0; gi < NUM_PORTS; gi = gi + 1) begin : gen_monitor
            always @(posedge clk) begin
                if (!rst_n) begin
                    egress_pkt_count[gi] <= 0;
                    egress_beat_count[gi] <= 0;
                end else if (m_axis_tvalid[gi] && m_axis_tready[gi]) begin
                    egress_beat_count[gi] <= egress_beat_count[gi] + 1;

                    // Print every beat (完整 tdata, 用于 ICRC 离线对照)
                    $display("[%0t] EGRESS Port%0d beat%0d: tdata=0x%0128h tkeep=0x%016h tlast=%0b tuser[31:24]=0x%02h tuser[23:16]=0x%02h",
                             $time, gi, egress_beat_count[gi],
                             m_axis_tdata[gi],
                             m_axis_tkeep[gi], m_axis_tlast[gi],
                             m_axis_tuser[gi][31:24], m_axis_tuser[gi][23:16]);

                    if (m_axis_tlast[gi]) begin
                        egress_pkt_count[gi] <= egress_pkt_count[gi] + 1;
                        egress_beat_count[gi] <= 0;
                        $display("[%0t] EGRESS Port%0d: === pkt #%0d complete (%0d beats) ===",
                                 $time, gi, egress_pkt_count[gi], egress_beat_count[gi] + 1);
                    end
                    if (!m_axis_tlast[gi] || (m_axis_tlast[gi] && egress_pkt_count[gi] == 0))
                        egress_first_beat[gi] <= m_axis_tdata[gi];
                end
            end
        end
    endgenerate

    // ================================================================
    // Hash Connection Table Backdoor Config
    // ================================================================
    // Key format: {dst_mac, src_mac, src_ip, dst_ip, src_port, dst_port} = 192 bits
    // Table entry: {root_info[1], key[192], valid[1]} = 194 bits
    //
    // Connection 0: root_info=1 (this node is root for this connection)
    //   Used for root_up → port_retrans / down_broadcast scenarios
    localparam HASH_KEY_WIDTH = 160;
    localparam HASH_WIDTH     = 8;

    // 使用 hash_connection_table 内部静态 entry 的值 (160-bit key)
    reg [47:0] hit_src_mac_0  = 48'hB8599F011122;   // worker1 MAC
    reg [47:0] hit_dst_mac_0  = 48'h020000000307;   // FPGA root MAC
    reg [31:0] hit_src_ip_0   = 32'hC0A80305;       // 192.168.3.5
    reg [31:0] hit_dst_ip_0   = 32'hC0A80307;       // 192.168.3.7
    reg [15:0] hit_src_port_0 = 16'd4791;
    reg [15:0] hit_dst_port_0 = 16'd4791;
    reg        hit_root_info_0 = 1'b1;

    wire [HASH_WIDTH-1:0] hit_hash_value_0;
    reg [HASH_KEY_WIDTH-1:0] full_hit_key_0;

    hash_function #(
        .KEY_WIDTH(HASH_KEY_WIDTH),
        .HASH_WIDTH(HASH_WIDTH)
    ) tb_hash_func_0 (
        .key_in({hit_dst_mac_0, hit_src_mac_0, hit_src_ip_0, hit_dst_ip_0}),
        .hash_out(hit_hash_value_0)
    );

    // Connection 1: root_info=1 (this node is root, worker2)
    reg [47:0] hit_src_mac_1  = 48'hB8599F011258;   // worker2 MAC
    reg [47:0] hit_dst_mac_1  = 48'h020000000307;   // FPGA root MAC
    reg [31:0] hit_src_ip_1   = 32'hC0A80306;       // 192.168.3.6
    reg [31:0] hit_dst_ip_1   = 32'hC0A80307;       // 192.168.3.7
    reg [15:0] hit_src_port_1 = 16'd4791;
    reg [15:0] hit_dst_port_1 = 16'd4791;
    reg        hit_root_info_1 = 1'b1;

    wire [HASH_WIDTH-1:0] hit_hash_value_1;
    reg [HASH_KEY_WIDTH-1:0] full_hit_key_1;

    hash_function #(
        .KEY_WIDTH(HASH_KEY_WIDTH),
        .HASH_WIDTH(HASH_WIDTH)
    ) tb_hash_func_1 (
        .key_in({hit_dst_mac_1, hit_src_mac_1, hit_src_ip_1, hit_dst_ip_1}),
        .hash_out(hit_hash_value_1)
    );

    // Hierarchical path to hash connection table inside DUT
    // nf_datapath_4port → allreduce_offload_wrapper → allreduce_offload_top → parser → hash_connection_table
    `define HASH_TBL u_dut.u_allreduce_wrapper.u_allreduce.allreduce_parser.u_connection_table.table_mem

    // ================================================================
    // Init
    // ================================================================
    localparam [7:0] OPCODE_FIRST = 8'h0;
    integer p;
    initial begin
        for (p = 0; p < NUM_PORTS; p = p + 1) begin
            s_axis_tdata[p]  = {DATA_W{1'b0}};
            s_axis_tkeep[p]  = {KEEP_W{1'b0}};
            s_axis_tuser[p]  = {TUSER_W{1'b0}};
        end
        s_axis_tvalid = 0;
        s_axis_tlast  = 0;
        m_axis_tready = {NUM_PORTS{1'b1}};
    end

    // ================================================================
    // Test Scenarios
    // ================================================================
    reg [DATA_W-1:0] hdr_beat;

    initial begin
        $display("========================================");
        $display("  AllReduce + Switch Datapath Testbench");
        $display("========================================");

        wait(rst_n == 1);
        repeat(20) @(posedge clk);

        // ==========================================================
        // Step 0: 验证 hash connection table 静态 entry
        // hash_connection_table.v 内部 initial 块已预装 2 个 160-bit entry
        // 不需要 backdoor write, 只打印确认
        // ==========================================================
        $display("\n--- Step 0: Verify hash connection table (static entries) ---");

        @(posedge clk);
        full_hit_key_0 = {hit_dst_mac_0, hit_src_mac_0, hit_src_ip_0, hit_dst_ip_0};
        $display("  Connection 0: hash=0x%02h, root_info=%0b, key=0x%040h",
                 hit_hash_value_0, hit_root_info_0, full_hit_key_0);

        @(posedge clk);
        full_hit_key_1 = {hit_dst_mac_1, hit_src_mac_1, hit_src_ip_1, hit_dst_ip_1};
        $display("  Connection 1: hash=0x%02h, root_info=%0b, key=0x%040h",
                 hit_hash_value_1, hit_root_info_1, full_hit_key_1);

        repeat(50) @(posedge clk);

        // ==========================================================
        // TEST 1: Pass-through (hash miss)
        //   Send from Port0 with unknown MAC → hash miss → direct pass-through
        //   OPL does MAC lookup → broadcast (unknown dst_mac)
        //   Expected: packet appears on all egress ports
        // ==========================================================
//        $display("\n--- TEST 1: Pass-through L2 packet (hash miss) from Port0 ---");
//        build_header_beat(
//            48'hFF_FF_FF_FF_FF_FF,  // dst_mac (broadcast)
//            48'hDE_AD_BE_EF_00_00,  // src_mac (not in hash table)
//            32'h0A000099,           // dst_ip
//            32'h0A000001,           // src_ip
//            16'd9999, 16'd8888,     // UDP ports (not matching hash entries)
//            8'hFF,                  // opcode (invalid → hash miss guaranteed)
//            32'h00000000,           // QPN
//            32'h00000000,           // PSN
//            16'd64,                 // payload_len
//            hdr_beat
//        );
//        send_packet_1beat(0, hdr_beat, {KEEP_W{1'b1}},
//                          build_tuser(8'h01, 16'd128));

//        repeat(200) @(posedge clk);

        // ==========================================================
        // TEST 2: Root AllReduce aggregation (both connections root_info=1)
        //   Connection 0 (worker1): Port0 sends OPCODE_FIRST with PSN=0
        //   Connection 1 (worker2): Port1 sends same PSN=0
        //   Both root_info=1 → Typer: TYPE_ROOT_DATA_UP
        //   After FAN_IN=2 到齐 → broadcast to CHILDREN_ALL
        //   Expected: aggregated result on Port0+Port1 (cfg_child_port_mask=0x03)
        //   Wrapper route_type = ROUTE_TO_CHILDREN_ALL → TUSER[31:24] = 0x03
        // ==========================================================
        $display("\n--- TEST 2: Root AllReduce from Port0 (worker1, connection 0, PSN=0) ---");
        build_header_beat(
            hit_dst_mac_0, hit_src_mac_0,
            hit_dst_ip_0, hit_src_ip_0,
            hit_dst_port_0, hit_src_port_0,
            OPCODE_FIRST,
            32'h00000001,           // QPN
            32'h00000000,           // PSN = 0
            16'd1024,               // payload_len
            hdr_beat
        );
        send_packet_multi(0, hdr_beat,
                          build_tuser(8'h01, 16'd1078),
                          16);

        repeat(50) @(posedge clk);

        $display("\n--- TEST 2b: Root AllReduce from Port1 (worker2, connection 1, PSN=0) ---");
        build_header_beat(
            hit_dst_mac_1, hit_src_mac_1,
            hit_dst_ip_1, hit_src_ip_1,
            hit_dst_port_1, hit_src_port_1,
            OPCODE_FIRST,
            32'h00000001,
            32'h00000000,           // same PSN = 0
            16'd1024,
            hdr_beat
        );
        send_packet_multi(1, hdr_beat,
                          build_tuser(8'h02, 16'd1078),
                          16);

        repeat(500) @(posedge clk);

        // ==========================================================
        // TEST 3: Root aggregation with PSN=1 (second round)
        //   Same as TEST 2 but PSN=1, verifies PSN tracking
        // ==========================================================
//        $display("\n--- TEST 3: Root aggregation from Port0 (connection 0, PSN=1) ---");
//        build_header_beat(
//            hit_dst_mac_0, hit_src_mac_0,
//            hit_dst_ip_0, hit_src_ip_0,
//            hit_dst_port_0, hit_src_port_0,
//            OPCODE_FIRST,
//            32'h00000001,
//            32'h00000001,           // PSN = 1
//            16'd1024,
//            hdr_beat
//        );
//        send_packet_multi(0, hdr_beat,
//                          build_tuser(8'h01, 16'd1078),
//                          16);

//        repeat(50) @(posedge clk);

//        $display("\n--- TEST 3b: Root aggregation from Port1 (connection 1, PSN=1) ---");
//        build_header_beat(
//            hit_dst_mac_1, hit_src_mac_1,
//            hit_dst_ip_1, hit_src_ip_1,
//            hit_dst_port_1, hit_src_port_1,
//            OPCODE_FIRST,
//            32'h00000001,
//            32'h00000001,           // same PSN = 1
//            16'd1024,
//            hdr_beat
//        );
//        send_packet_multi(1, hdr_beat,
//                          build_tuser(8'h02, 16'd1078),
//                          16);

//        repeat(500) @(posedge clk);

        // ==========================================================
        // TEST 4: ACK packet from Port0 (TYPE_ACK_UP, T3 echo 验证)
        //   opcode=0x11, root_info=1 → Typer: TYPE_ACK_DOWN
        //   Expected: deparser 重构 ACK → ROUTE_TO_CHILD_SINGLE → 回 Port0
        // ==========================================================
        $display("\n--- TEST 4: ACK from Port0 (opcode=0x11, connection 0) ---");
        build_header_beat(
            hit_dst_mac_0, hit_src_mac_0,
            hit_dst_ip_0, hit_src_ip_0,
            hit_dst_port_0, hit_src_port_0,
            8'h11,                  // OPCODE_ACK
            32'h00000001,
            32'h00000000,           // PSN = 0
            16'd4,                  // AETH only (4 bytes)
            hdr_beat
        );
        send_packet_1beat(0, hdr_beat, {KEEP_W{1'b1}},
                          build_tuser(8'h01, 16'd62));

        repeat(500) @(posedge clk);

        // ==========================================================
        // TEST 5: ACK from child Port1 (worker2 RNIC 回的 transport ACK)
        //   opcode=0x11, ingress_port=1 < FAN_IN → TYPE_ACK_UP
        //   Expected: deparser 重构 ACK → ROUTE_TO_CHILD_SINGLE → 回 Port1
        // ==========================================================
//        $display("\n--- TEST 5: ACK from child Port1 (TYPE_ACK_UP) ---");
//        build_header_beat(
//            hit_dst_mac_1, hit_src_mac_1,
//            hit_dst_ip_1, hit_src_ip_1,
//            hit_dst_port_1, hit_src_port_1,
//            8'h11,                  // OPCODE_ACK
//            32'h00000001,
//            32'h00000000,
//            16'd4,                  // AETH only
//            hdr_beat
//        );
//        send_packet_1beat(1, hdr_beat, {KEEP_W{1'b1}},
//                          build_tuser(8'h02, 16'd62));

//        repeat(300) @(posedge clk);

        // ----------------------------------------------------------
        // Summary
        // ----------------------------------------------------------
        $display("\n========================================");
        $display("  Test Complete. Egress packet counts:");
        for (p = 0; p < NUM_PORTS; p = p + 1)
            $display("    Port%0d: %0d packets", p, egress_pkt_count[p]);
        $display("========================================");

        #1000;
        $finish;
    end

    // ================================================================
    // Pipeline stage monitors (internal signals)
    // ================================================================

    // Monitor: parser hash hit
    always @(posedge clk) begin
        if (u_dut.u_allreduce_wrapper.u_allreduce.allreduce_parser.s4_valid) begin
            $display("[%0t] PARSER s4: hit=%0b root=%0b agg_en=%0b egress_en=%0b opcode=0x%02h psn=%0d ingress=%0d",
                     $time,
                     u_dut.u_allreduce_wrapper.u_allreduce.allreduce_parser.s4_lookup_hit,
                     u_dut.u_allreduce_wrapper.u_allreduce.allreduce_parser.s4_root_info,
                     u_dut.u_allreduce_wrapper.u_allreduce.allreduce_parser.s4_aggregate_en,
                     u_dut.u_allreduce_wrapper.u_allreduce.allreduce_parser.s4_egress_en,
                     u_dut.u_allreduce_wrapper.u_allreduce.allreduce_parser.s4_opcode,
                     u_dut.u_allreduce_wrapper.u_allreduce.allreduce_parser.s4_psn_out,
                     u_dut.u_allreduce_wrapper.u_allreduce.allreduce_parser.s4_ingress_port);
        end
    end

    // Monitor: Typer classification
    always @(posedge clk) begin
        if (u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_typer.s2_valid) begin
            $display("[%0t] TYPER: root_up=%0b noroot_up=%0b data_down=%0b ack_up=%0b ack_down=%0b metadata=0x%06h",
                     $time,
                     u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_typer.data_root_up_en,
                     u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_typer.data_noroot_up_en,
                     u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_typer.data_down_en,
                     u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_typer.ack_up_en,
                     u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_typer.ack_down_en,
                     u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_typer.metadata_with_type);
        end
    end

    // Monitor: Typer -> down_broadcast handshake
    always @(posedge clk) begin
        if (u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.typer_to_down_broadcast_valid_r) begin
            $display("[%0t] TYPER->DOWN_BC: valid_r=1 ready=%0b metadata=0x%06h",
                     $time,
                     u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.down_broadcast_to_typer_in_ready,
                     u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.typer_metadata_to_down_broadcast_r);
        end
    end

    // Monitor: down_broadcast_checkor internal pipeline
    always @(posedge clk) begin
        if (u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_down_broadcast_checkor_arrival_updater.s1_valid)
            $display("[%0t] DOWN_BC s1: valid=1 psn=%0d ingress=%0d root=%0b",
                     $time,
                     u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_down_broadcast_checkor_arrival_updater.s1_idx_psn,
                     u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_down_broadcast_checkor_arrival_updater.s1_ingress_port,
                     u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_down_broadcast_checkor_arrival_updater.s1_root_info);
        if (u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_down_broadcast_checkor_arrival_updater.s4_valid)
            $display("[%0t] DOWN_BC s4: valid=1 need_bc=%0b",
                     $time,
                     u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.allreduce_down_broadcast_checkor_arrival_updater.s4_need_broadcast);
    end

    // Monitor: down_broadcast -> buffer handshake
    always @(posedge clk) begin
        if (u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.down_broadcast_to_buffer_valid) begin
            $display("[%0t] DOWN_BC->BUFFER: valid=1 ready=%0b copy_en=%0b metadata=0x%06h",
                     $time,
                     u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.buffer_to_down_broadcast_ready,
                     u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.down_broadcast_to_buffer_copy_buffer_en,
                     u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.down_broadcast_to_buffer_metadata_out);
        end
    end

    // Monitor: buffer controller -> deparser (down_broadcast output)
    always @(posedge clk) begin
        if (u_dut.u_allreduce_wrapper.u_allreduce.u_aggregator.buffer_to_deparser_down_down_broadcast_ok_en)
            $display("[%0t] BUFFER->DEPARSER: down_broadcast_ok_en fired", $time);
    end

    // Monitor: deparser state transitions
    reg [2:0] prev_deparser_state;
    always @(posedge clk) begin
        prev_deparser_state <= u_dut.u_allreduce_wrapper.u_allreduce.allreduce_deparser.current_state;
        if (u_dut.u_allreduce_wrapper.u_allreduce.allreduce_deparser.current_state != prev_deparser_state) begin
            $display("[%0t] DEPARSER state: %0d -> %0d  route_type=%0d is_agg=%0b",
                     $time,
                     prev_deparser_state,
                     u_dut.u_allreduce_wrapper.u_allreduce.allreduce_deparser.current_state,
                     u_dut.u_allreduce_wrapper.u_allreduce.allreduce_deparser.latched_route_type,
                     u_dut.u_allreduce_wrapper.u_allreduce.allreduce_deparser.m_axis_is_aggregated);
        end
    end

    // Monitor: aggregator output enables
    always @(posedge clk) begin
        if (u_dut.u_allreduce_wrapper.u_allreduce.aggregator_to_deparser_FAN_first_trans_en_out)
            $display("[%0t] AGGREGATOR: FAN_first_trans_en fired", $time);
        if (u_dut.u_allreduce_wrapper.u_allreduce.aggregator_to_deparser_FAN_retrans_en_out)
            $display("[%0t] AGGREGATOR: FAN_retrans_en fired", $time);
        if (u_dut.u_allreduce_wrapper.u_allreduce.aggregator_to_deparser_down_broadcast_en_out)
            $display("[%0t] AGGREGATOR: down_broadcast_en fired", $time);
        if (u_dut.u_allreduce_wrapper.u_allreduce.aggregator_to_deparser_ack_build_en_out)
            $display("[%0t] AGGREGATOR: ack_build_en fired", $time);
        if (u_dut.u_allreduce_wrapper.u_allreduce.aggregator_to_deparser_port_retrans_en_out)
            $display("[%0t] AGGREGATOR: port_retrans_en fired", $time);
        if (u_dut.u_allreduce_wrapper.u_allreduce.aggregator_to_deparser_ack_down_en_out)
            $display("[%0t] AGGREGATOR: ack_down_en fired", $time);
    end

    // Monitor: wrapper output tuser dst_port
    always @(posedge clk) begin
        if (u_dut.u_allreduce_wrapper.m_axis_tvalid && u_dut.u_allreduce_wrapper.m_axis_tready) begin
            $display("[%0t] WRAPPER out: tuser[31:24]=0x%02h tuser[23:16]=0x%02h is_agg=%0b route=%0d tlast=%0b",
                     $time,
                     u_dut.u_allreduce_wrapper.m_axis_tuser[31:24],
                     u_dut.u_allreduce_wrapper.m_axis_tuser[23:16],
                     u_dut.u_allreduce_wrapper.u_allreduce.allreduce_deparser.m_axis_is_aggregated,
                     u_dut.u_allreduce_wrapper.u_allreduce.allreduce_deparser.m_axis_route_type,
                     u_dut.u_allreduce_wrapper.m_axis_tlast);
        end
    end

    // Monitor: OPL dst_port decision
    always @(posedge clk) begin
        if (u_dut.u_output_port_lookup.m_axis_tvalid &&
            u_dut.u_output_port_lookup.m_axis_tready &&
            u_dut.u_output_port_lookup.m_axis_tlast) begin
            $display("[%0t] OPL out: dst_port=0x%02h (tuser[31:24])",
                     $time,
                     u_dut.u_output_port_lookup.m_axis_tuser[31:24]);
        end
    end

    // ================================================================
    // Waveform dump
    // ================================================================
    initial begin
        $dumpfile("tb_allreduce_switch.vcd");
        $dumpvars(0, tb_allreduce_switch_datapath);
    end

endmodule