`timescale 1ns / 1ps
`include "moe_defs.vh"

module moe_dispatch_egress_builder #(
    parameter AXIS_DATA_WIDTH = 512,
    parameter AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8,
    parameter AXIS_TUSER_WIDTH = 128,
    parameter NUM_EXPERTS = 2,
    parameter OWNER_WIDTH = 8,
    parameter GLOBAL_SEQ_WIDTH = 32,
    parameter EXPERT_BITMAP_WIDTH = 64,
    parameter PORT_MASK_WIDTH = 8,
    parameter PAYLOAD_WIDTH = 512,
    parameter ROCE_PAYLOAD_BYTES = 1024,
    parameter ROCE_PAYLOAD_BITS = ROCE_PAYLOAD_BYTES * 8
) (
    input wire clk,
    input wire rst_n,

    input wire dispatch_valid,
    output wire dispatch_ready,
    input wire [OWNER_WIDTH-1:0] dispatch_owner_rank,
    input wire [GLOBAL_SEQ_WIDTH-1:0] dispatch_global_seq,
    input wire [EXPERT_BITMAP_WIDTH-1:0] dispatch_expert_bitmap,
    input wire [PAYLOAD_WIDTH-1:0] dispatch_payload_data,

    input wire [47:0] cfg_fpga_mac,
    input wire [31:0] cfg_fpga_ip,
    input wire [15:0] cfg_fpga_udp_port,
    input wire [47:0] cfg_expert0_mac,
    input wire [31:0] cfg_expert0_ip,
    input wire [23:0] cfg_expert0_qp,
    input wire [15:0] cfg_expert0_udp_port,
    input wire [47:0] cfg_expert1_mac,
    input wire [31:0] cfg_expert1_ip,
    input wire [23:0] cfg_expert1_qp,
    input wire [15:0] cfg_expert1_udp_port,
    input wire [NUM_EXPERTS*PORT_MASK_WIDTH-1:0] cfg_expert_port_mask_flat,
    input wire [31:0] cfg_dispatch_psn,

    output reg [AXIS_DATA_WIDTH-1:0] m_axis_tdata,
    output reg [AXIS_KEEP_WIDTH-1:0] m_axis_tkeep,
    output reg [AXIS_TUSER_WIDTH-1:0] m_axis_tuser,
    output reg m_axis_tvalid,
    output reg m_axis_tlast,
    input wire m_axis_tready
);
    localparam S_IDLE = 2'd0;
    localparam S_HEADER = 2'd1;
    localparam S_PAYLOAD = 2'd2;
    localparam [7:0] OPCODE_SEND_ONLY = 8'h04;
    localparam [15:0] ROCE_PAYLOAD_BYTES_CAST = ROCE_PAYLOAD_BYTES;
    localparam [15:0] ROCE_AXIS_PKT_BYTES = 16'd14 + 16'd20 + 16'd8 + 16'd12 +
                                            ROCE_PAYLOAD_BYTES_CAST + 16'd4;

    reg [1:0] state;
    reg [3:0] payload_beat_count;

    reg [OWNER_WIDTH-1:0] owner_rank_r;
    reg [GLOBAL_SEQ_WIDTH-1:0] global_seq_r;
    reg [EXPERT_BITMAP_WIDTH-1:0] expert_bitmap_r;
    reg [PAYLOAD_WIDTH-1:0] payload_data_r;
    reg [31:0] psn_r;

    function [PORT_MASK_WIDTH-1:0] select_expert_port_mask;
        input [EXPERT_BITMAP_WIDTH-1:0] expert_bitmap;
        input [NUM_EXPERTS*PORT_MASK_WIDTH-1:0] port_mask_flat;
        integer expert_idx;
        begin
            select_expert_port_mask = {PORT_MASK_WIDTH{1'b0}};
            for (expert_idx = 0; expert_idx < NUM_EXPERTS; expert_idx = expert_idx + 1) begin
                if (expert_bitmap[expert_idx]) begin
                    select_expert_port_mask =
                        select_expert_port_mask |
                        port_mask_flat[(expert_idx+1)*PORT_MASK_WIDTH-1 -: PORT_MASK_WIDTH];
                end
            end
        end
    endfunction

    wire [PORT_MASK_WIDTH-1:0] selected_port_mask =
        select_expert_port_mask(expert_bitmap_r, cfg_expert_port_mask_flat);

    wire [47:0] dst_mac =
        expert_bitmap_r[1] ? cfg_expert1_mac : cfg_expert0_mac;
    wire [31:0] dst_ip =
        expert_bitmap_r[1] ? cfg_expert1_ip : cfg_expert0_ip;
    wire [23:0] dst_qp =
        expert_bitmap_r[1] ? cfg_expert1_qp : cfg_expert0_qp;
    wire [15:0] dst_udp_port =
        expert_bitmap_r[1] ? cfg_expert1_udp_port : cfg_expert0_udp_port;

    reg [ROCE_PAYLOAD_BITS-1:0] roce_payload;
    always @(*) begin
        roce_payload = {ROCE_PAYLOAD_BITS{1'b0}};
        roce_payload[15:0] = `MOE_MAGIC;
        roce_payload[23:16] = 8'h01;
        roce_payload[31:24] = `MOE_OP_DISPATCH;
        roce_payload[39:32] = owner_rank_r;
        roce_payload[47:40] = expert_bitmap_r[7:0];
        roce_payload[79:48] = global_seq_r;
        roce_payload[80 +: PAYLOAD_WIDTH] = payload_data_r;
    end

    function [AXIS_DATA_WIDTH-1:0] select_payload_beat;
        input [3:0] beat_index;
        begin
            case (beat_index)
                4'd0:    select_payload_beat = roce_payload[  80 +: AXIS_DATA_WIDTH];
                4'd1:    select_payload_beat = roce_payload[ 592 +: AXIS_DATA_WIDTH];
                4'd2:    select_payload_beat = roce_payload[1104 +: AXIS_DATA_WIDTH];
                4'd3:    select_payload_beat = roce_payload[1616 +: AXIS_DATA_WIDTH];
                4'd4:    select_payload_beat = roce_payload[2128 +: AXIS_DATA_WIDTH];
                4'd5:    select_payload_beat = roce_payload[2640 +: AXIS_DATA_WIDTH];
                4'd6:    select_payload_beat = roce_payload[3152 +: AXIS_DATA_WIDTH];
                4'd7:    select_payload_beat = roce_payload[3664 +: AXIS_DATA_WIDTH];
                4'd8:    select_payload_beat = roce_payload[4176 +: AXIS_DATA_WIDTH];
                4'd9:    select_payload_beat = roce_payload[4688 +: AXIS_DATA_WIDTH];
                4'd10:   select_payload_beat = roce_payload[5200 +: AXIS_DATA_WIDTH];
                4'd11:   select_payload_beat = roce_payload[5712 +: AXIS_DATA_WIDTH];
                4'd12:   select_payload_beat = roce_payload[6224 +: AXIS_DATA_WIDTH];
                4'd13:   select_payload_beat = roce_payload[6736 +: AXIS_DATA_WIDTH];
                4'd14:   select_payload_beat = roce_payload[7248 +: AXIS_DATA_WIDTH];
                4'd15:   select_payload_beat = {{80{1'b0}}, roce_payload[8191:7760]};
                default: select_payload_beat = {AXIS_DATA_WIDTH{1'b0}};
            endcase
        end
    endfunction

    wire [15:0] ip_total_len = 16'd20 + 16'd8 + 16'd12 + ROCE_PAYLOAD_BYTES_CAST + 16'd4;
    wire [15:0] udp_len = 16'd8 + 16'd12 + ROCE_PAYLOAD_BYTES_CAST + 16'd4;
    wire [31:0] ip_sum_pre = 16'h4500 + ip_total_len + 16'h1111 + 16'h4000
                            + 16'h4011 + 16'h0000
                            + cfg_fpga_ip[31:16] + cfg_fpga_ip[15:0]
                            + dst_ip[31:16] + dst_ip[15:0];
    wire [16:0] ip_sum_fold = ip_sum_pre[15:0] + ip_sum_pre[31:16];
    wire [15:0] ip_checksum = ~(ip_sum_fold[15:0] + {15'd0, ip_sum_fold[16]});
    wire [31:0] target_psn = psn_r | 32'h80000000;

    reg [AXIS_DATA_WIDTH-1:0] header_beat;
    always @(*) begin
        header_beat = {AXIS_DATA_WIDTH{1'b0}};

        header_beat[  7:  0] = dst_mac[47:40];
        header_beat[ 15:  8] = dst_mac[39:32];
        header_beat[ 23: 16] = dst_mac[31:24];
        header_beat[ 31: 24] = dst_mac[23:16];
        header_beat[ 39: 32] = dst_mac[15: 8];
        header_beat[ 47: 40] = dst_mac[ 7: 0];
        header_beat[ 55: 48] = cfg_fpga_mac[47:40];
        header_beat[ 63: 56] = cfg_fpga_mac[39:32];
        header_beat[ 71: 64] = cfg_fpga_mac[31:24];
        header_beat[ 79: 72] = cfg_fpga_mac[23:16];
        header_beat[ 87: 80] = cfg_fpga_mac[15: 8];
        header_beat[ 95: 88] = cfg_fpga_mac[ 7: 0];
        header_beat[103: 96] = 8'h08;
        header_beat[111:104] = 8'h00;

        header_beat[119:112] = 8'h45;
        header_beat[127:120] = 8'h00;
        header_beat[135:128] = ip_total_len[15:8];
        header_beat[143:136] = ip_total_len[7:0];
        header_beat[151:144] = 8'h11;
        header_beat[159:152] = 8'h11;
        header_beat[167:160] = 8'h40;
        header_beat[175:168] = 8'h00;
        header_beat[183:176] = 8'h40;
        header_beat[191:184] = 8'h11;
        header_beat[199:192] = ip_checksum[15:8];
        header_beat[207:200] = ip_checksum[7:0];
        header_beat[215:208] = cfg_fpga_ip[31:24];
        header_beat[223:216] = cfg_fpga_ip[23:16];
        header_beat[231:224] = cfg_fpga_ip[15:8];
        header_beat[239:232] = cfg_fpga_ip[7:0];
        header_beat[247:240] = dst_ip[31:24];
        header_beat[255:248] = dst_ip[23:16];
        header_beat[263:256] = dst_ip[15:8];
        header_beat[271:264] = dst_ip[7:0];

        header_beat[279:272] = cfg_fpga_udp_port[15:8];
        header_beat[287:280] = cfg_fpga_udp_port[7:0];
        header_beat[295:288] = dst_udp_port[15:8];
        header_beat[303:296] = dst_udp_port[7:0];
        header_beat[311:304] = udp_len[15:8];
        header_beat[319:312] = udp_len[7:0];
        header_beat[327:320] = 8'h00;
        header_beat[335:328] = 8'h00;

        header_beat[343:336] = OPCODE_SEND_ONLY;
        header_beat[351:344] = 8'h00;
        header_beat[359:352] = 8'hFF;
        header_beat[367:360] = 8'hFF;
        header_beat[375:368] = 8'h00;
        header_beat[383:376] = dst_qp[23:16];
        header_beat[391:384] = dst_qp[15:8];
        header_beat[399:392] = dst_qp[7:0];
        header_beat[407:400] = target_psn[31:24];
        header_beat[415:408] = target_psn[23:16];
        header_beat[423:416] = target_psn[15:8];
        header_beat[431:424] = target_psn[7:0];
        header_beat[511:432] = roce_payload[79:0];
    end

    assign dispatch_ready = (state == S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            payload_beat_count <= 4'd0;
            owner_rank_r <= {OWNER_WIDTH{1'b0}};
            global_seq_r <= {GLOBAL_SEQ_WIDTH{1'b0}};
            expert_bitmap_r <= {EXPERT_BITMAP_WIDTH{1'b0}};
            payload_data_r <= {PAYLOAD_WIDTH{1'b0}};
            psn_r <= 32'd0;
            m_axis_tdata <= {AXIS_DATA_WIDTH{1'b0}};
            m_axis_tkeep <= {AXIS_KEEP_WIDTH{1'b0}};
            m_axis_tuser <= {AXIS_TUSER_WIDTH{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
        end
        else begin
            case (state)
                S_IDLE: begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast <= 1'b0;
                    m_axis_tkeep <= {AXIS_KEEP_WIDTH{1'b0}};

                    if (dispatch_valid && dispatch_ready) begin
                        owner_rank_r <= dispatch_owner_rank;
                        global_seq_r <= dispatch_global_seq;
                        expert_bitmap_r <= dispatch_expert_bitmap;
                        payload_data_r <= dispatch_payload_data;
                        psn_r <= cfg_dispatch_psn;
                        payload_beat_count <= 4'd0;
                        state <= S_HEADER;
                    end
                end

                S_HEADER: begin
                    m_axis_tvalid <= 1'b1;
                    m_axis_tuser <= {AXIS_TUSER_WIDTH{1'b0}};
                    m_axis_tuser[32] <= 1'b1;
                    m_axis_tuser[33] <= 1'b1;
                    m_axis_tuser[31:24] <= selected_port_mask;
                    m_axis_tuser[15:0] <= ROCE_AXIS_PKT_BYTES;

                    if (m_axis_tvalid && m_axis_tready) begin
                        state <= S_PAYLOAD;
                        payload_beat_count <= 4'd0;
                        m_axis_tdata <= select_payload_beat(4'd0);
                        m_axis_tkeep <= {AXIS_KEEP_WIDTH{1'b1}};
                        m_axis_tlast <= 1'b0;
                    end
                    else begin
                        m_axis_tlast <= 1'b0;
                        m_axis_tkeep <= {AXIS_KEEP_WIDTH{1'b1}};
                        m_axis_tdata <= header_beat;
                    end
                end

                S_PAYLOAD: begin
                    m_axis_tvalid <= 1'b1;
                    m_axis_tuser[32] <= 1'b1;
                    m_axis_tuser[33] <= 1'b1;
                    m_axis_tuser[31:24] <= selected_port_mask;
                    m_axis_tuser[15:0] <= ROCE_AXIS_PKT_BYTES;

                    if (m_axis_tvalid && m_axis_tready) begin
                        if (payload_beat_count == 4'd15) begin
                            state <= S_IDLE;
                            payload_beat_count <= 4'd0;
                            m_axis_tvalid <= 1'b0;
                            m_axis_tlast <= 1'b0;
                            m_axis_tkeep <= {AXIS_KEEP_WIDTH{1'b0}};
                        end
                        else begin
                            payload_beat_count <= payload_beat_count + 4'd1;
                            m_axis_tdata <= select_payload_beat(payload_beat_count + 4'd1);
                            if ((payload_beat_count + 4'd1) == 4'd15) begin
                                m_axis_tkeep <= {{(AXIS_KEEP_WIDTH-58){1'b0}}, {58{1'b1}}};
                                m_axis_tlast <= 1'b1;
                            end
                            else begin
                                m_axis_tkeep <= {AXIS_KEEP_WIDTH{1'b1}};
                                m_axis_tlast <= 1'b0;
                            end
                        end
                    end
                    else if (payload_beat_count == 4'd15) begin
                        m_axis_tdata <= select_payload_beat(payload_beat_count);
                        m_axis_tkeep <= {{(AXIS_KEEP_WIDTH-58){1'b0}}, {58{1'b1}}};
                        m_axis_tlast <= 1'b1;
                    end
                    else begin
                        m_axis_tdata <= select_payload_beat(payload_beat_count);
                        m_axis_tkeep <= {AXIS_KEEP_WIDTH{1'b1}};
                        m_axis_tlast <= 1'b0;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
