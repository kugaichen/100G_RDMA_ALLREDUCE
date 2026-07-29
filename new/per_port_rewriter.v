`timescale 1ns / 1ps

module per_port_rewriter #(
    parameter AXIS_DATA_WIDTH  = 512,
    parameter AXIS_KEEP_WIDTH  = 64,
    parameter AXIS_TUSER_WIDTH = 128,
    parameter [7:0] LOCAL_PORT_ONEHOT = 8'h01,
    parameter FIFO_DEPTH = 32
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire [7:0]                   cfg_child_port_mask,
    input  wire [47:0]                  cfg_dst_mac,
    input  wire [47:0]                  cfg_src_mac,
    input  wire [31:0]                  cfg_dst_ip,
    input  wire [31:0]                  cfg_src_ip,
    input  wire [23:0]                  cfg_dst_qp,
    input  wire [15:0]                  cfg_src_port,
    input  wire [15:0]                  cfg_dst_port,

    input  wire [AXIS_DATA_WIDTH-1:0]   s_axis_tdata,
    input  wire [AXIS_KEEP_WIDTH-1:0]   s_axis_tkeep,
    input  wire [AXIS_TUSER_WIDTH-1:0]  s_axis_tuser,
    input  wire                         s_axis_tvalid,
    input  wire                         s_axis_tlast,
    output wire                         s_axis_tready,

    output reg  [AXIS_DATA_WIDTH-1:0]   m_axis_tdata,
    output reg  [AXIS_KEEP_WIDTH-1:0]   m_axis_tkeep,
    output reg  [AXIS_TUSER_WIDTH-1:0]  m_axis_tuser,
    output reg                          m_axis_tvalid,
    output reg                          m_axis_tlast,
    input  wire                         m_axis_tready
);

    localparam integer TUSER_FLAG_AR_GEN        = 32;
    localparam integer TUSER_FLAG_CHILD_REWRITE = 33;

    wire local_port_is_child = |(LOCAL_PORT_ONEHOT & cfg_child_port_mask);
    wire tuser_ar_gen        = s_axis_tuser[TUSER_FLAG_AR_GEN];
    wire tuser_child_rewrite = s_axis_tuser[TUSER_FLAG_CHILD_REWRITE];

    reg is_first_beat;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            is_first_beat <= 1'b1;
        else if (s_axis_tvalid && s_axis_tready)
            is_first_beat <= s_axis_tlast;
    end

    wire do_rewrite = tuser_ar_gen && tuser_child_rewrite && local_port_is_child && is_first_beat;

    wire [15:0] ip_total_len_in = {s_axis_tdata[135:128], s_axis_tdata[143:136]};

    wire [31:0] ip_sum_pre = 16'h4500 + ip_total_len_in
                           + 16'h1111 + 16'h4000
                           + 16'h4011 + 16'h0000
                           + cfg_src_ip[31:16] + cfg_src_ip[15:0]
                           + cfg_dst_ip[31:16] + cfg_dst_ip[15:0];
    wire [16:0] ip_sum_fold  = ip_sum_pre[15:0] + ip_sum_pre[31:16];
    wire [15:0] ip_checksum  = ~(ip_sum_fold[15:0] + {15'd0, ip_sum_fold[16]});

    reg [AXIS_DATA_WIDTH-1:0] tdata_out;
    always @(*) begin
        tdata_out = s_axis_tdata;
        if (do_rewrite) begin
            tdata_out[  7:  0] = cfg_dst_mac[47:40];
            tdata_out[ 15:  8] = cfg_dst_mac[39:32];
            tdata_out[ 23: 16] = cfg_dst_mac[31:24];
            tdata_out[ 31: 24] = cfg_dst_mac[23:16];
            tdata_out[ 39: 32] = cfg_dst_mac[15: 8];
            tdata_out[ 47: 40] = cfg_dst_mac[ 7: 0];
            tdata_out[ 55: 48] = cfg_src_mac[47:40];
            tdata_out[ 63: 56] = cfg_src_mac[39:32];
            tdata_out[ 71: 64] = cfg_src_mac[31:24];
            tdata_out[ 79: 72] = cfg_src_mac[23:16];
            tdata_out[ 87: 80] = cfg_src_mac[15: 8];
            tdata_out[ 95: 88] = cfg_src_mac[ 7: 0];
            tdata_out[199:192] = ip_checksum[15:8];
            tdata_out[207:200] = ip_checksum[ 7:0];
            tdata_out[215:208] = cfg_src_ip[31:24];
            tdata_out[223:216] = cfg_src_ip[23:16];
            tdata_out[231:224] = cfg_src_ip[15: 8];
            tdata_out[239:232] = cfg_src_ip[ 7: 0];
            tdata_out[247:240] = cfg_dst_ip[31:24];
            tdata_out[255:248] = cfg_dst_ip[23:16];
            tdata_out[263:256] = cfg_dst_ip[15: 8];
            tdata_out[271:264] = cfg_dst_ip[ 7: 0];
            tdata_out[279:272] = cfg_src_port[15:8];
            tdata_out[287:280] = cfg_src_port[ 7:0];
            tdata_out[295:288] = cfg_dst_port[15:8];
            tdata_out[303:296] = cfg_dst_port[ 7:0];
            tdata_out[375:368] = 8'h00;
            tdata_out[383:376] = cfg_dst_qp[23:16];
            tdata_out[391:384] = cfg_dst_qp[15: 8];
            tdata_out[399:392] = cfg_dst_qp[ 7: 0];
        end
    end

    // Reflected IEEE CRC-32 state after the 8-byte all-ones dummy LRH.
    localparam [31:0] CRC_INIT = 32'hDEBB20E3;
    localparam ST_IDLE   = 2'd0;
    localparam ST_INGEST = 2'd1;
    localparam ST_DRAIN  = 2'd2;
    localparam ST_FINALIZE = 2'd3;
    reg [1:0] state;

    wire [15:0] ethertype_be    = {tdata_out[103:96],  tdata_out[111:104]};
    wire [7:0]  ip_proto_b      =  tdata_out[191:184];
    wire [15:0] udp_dst_port_be = {tdata_out[295:288], tdata_out[303:296]};
    wire is_roce_first = (ethertype_be == 16'h0800)
                      && (ip_proto_b  == 8'h11)
                      && (udp_dst_port_be == 16'd4791);

    reg [AXIS_DATA_WIDTH-1:0] crc_data_q;
    reg                       crc_pending;
    reg                       pending_first;
    reg                       pending_last;
    reg                       pending_roce_first;
    reg                       final_pending;
    reg                       packet_ready;

    reg [AXIS_DATA_WIDTH-1:0] masked_first;
    always @(*) begin
        masked_first = crc_data_q;
        masked_first[8*15+7 : 8*15] = 8'hFF;
        masked_first[8*22+7 : 8*22] = 8'hFF;
        masked_first[8*24+7 : 8*24] = 8'hFF;
        masked_first[8*25+7 : 8*25] = 8'hFF;
        masked_first[8*40+7 : 8*40] = 8'hFF;
        masked_first[8*41+7 : 8*41] = 8'hFF;
        masked_first[8*46+7 : 8*46] = 8'hFF;
    end

    wire [50*8-1:0] first_50B = masked_first[8*64-1 : 8*14];
    wire [44*8-1:0] ack_44B   = masked_first[8*58-1 : 8*14];
    wire [64*8-1:0] mid_64B   = crc_data_q;
    wire [54*8-1:0] last_54B  = crc_data_q[8*54-1:0];

    reg [31:0] crc_state;
    wire [31:0] crc_out_50B, crc_out_44B, crc_out_64B, crc_out_54B;

    crc32c_50B u_crc50 (.data_in(first_50B), .crc_in(crc_state), .crc_out(crc_out_50B));
    crc32c_44B u_crc44 (.data_in(ack_44B),   .crc_in(crc_state), .crc_out(crc_out_44B));
    crc32c_64B u_crc64 (.data_in(mid_64B),   .crc_in(crc_state), .crc_out(crc_out_64B));
    crc32c_54B u_crc54 (.data_in(last_54B),  .crc_in(crc_state), .crc_out(crc_out_54B));

    localparam FIFO_W = AXIS_DATA_WIDTH + AXIS_KEEP_WIDTH + AXIS_TUSER_WIDTH + 1;
    reg [FIFO_W-1:0] fifo_mem [0:FIFO_DEPTH-1];
    reg [$clog2(FIFO_DEPTH)-1:0] wr_ptr, rd_ptr;
    reg [$clog2(FIFO_DEPTH):0]   fifo_count;
    wire fifo_full  = (fifo_count == FIFO_DEPTH);
    wire fifo_empty = (fifo_count == 0);

    reg is_roce_q;
    reg is_single_q;
    reg icrc_done;
    reg [31:0] icrc_q;

    assign s_axis_tready = ((state == ST_IDLE) || (state == ST_INGEST))
                         && !fifo_full;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (s_axis_tvalid && s_axis_tready)
                        state <= s_axis_tlast ? ST_FINALIZE : ST_INGEST;
                end
                ST_INGEST: begin
                    if (s_axis_tvalid && s_axis_tready && s_axis_tlast)
                        state <= ST_FINALIZE;
                end
                ST_FINALIZE: begin
                    if (packet_ready)
                        state <= ST_DRAIN;
                end
                ST_DRAIN: begin
                    if (m_axis_tvalid && m_axis_tready && m_axis_tlast)
                        state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr      <= 0;
            crc_state   <= CRC_INIT;
            crc_data_q  <= {AXIS_DATA_WIDTH{1'b0}};
            crc_pending <= 1'b0;
            pending_first <= 1'b0;
            pending_last <= 1'b0;
            pending_roce_first <= 1'b0;
            final_pending <= 1'b0;
            packet_ready <= 1'b0;
            is_roce_q   <= 1'b0;
            is_single_q <= 1'b0;
            icrc_done   <= 1'b0;
            icrc_q      <= 32'h0;
        end else begin
            if (state == ST_DRAIN && m_axis_tvalid && m_axis_tready && m_axis_tlast) begin
                wr_ptr    <= 0;
                crc_state <= CRC_INIT;
                crc_pending <= 1'b0;
                final_pending <= 1'b0;
                packet_ready <= 1'b0;
                icrc_done <= 1'b0;
                is_roce_q <= 1'b0;
            end

            if (crc_pending) begin
                crc_pending <= 1'b0;

                if (pending_first) begin
                    is_roce_q   <= pending_roce_first;
                    is_single_q <= pending_last;

                    if (pending_roce_first) begin
                        if (pending_last) begin
                            crc_state <= crc_out_44B;
                            final_pending <= 1'b1;
                        end else begin
                            crc_state <= crc_out_50B;
                        end
                    end else if (pending_last) begin
                        packet_ready <= 1'b1;
                    end
                end else if (is_roce_q) begin
                    if (pending_last) begin
                        crc_state <= crc_out_54B;
                        final_pending <= 1'b1;
                    end else begin
                        crc_state <= crc_out_64B;
                    end
                end else if (pending_last) begin
                    packet_ready <= 1'b1;
                end
            end

            if (final_pending) begin
                final_pending <= 1'b0;
                icrc_q        <= crc_state ^ 32'hFFFFFFFF;
                icrc_done     <= 1'b1;
                packet_ready  <= 1'b1;
            end

            if (s_axis_tvalid && s_axis_tready) begin
                fifo_mem[wr_ptr] <= {s_axis_tlast, s_axis_tuser, s_axis_tkeep, tdata_out};
                wr_ptr <= wr_ptr + 1'b1;
                crc_data_q <= tdata_out;
                pending_first <= is_first_beat;
                pending_last <= s_axis_tlast;
                pending_roce_first <= tuser_ar_gen && is_roce_first;
                crc_pending <= 1'b1;
            end
        end
    end

    wire [AXIS_DATA_WIDTH-1:0]  f_tdata = fifo_mem[rd_ptr][AXIS_DATA_WIDTH-1:0];
    wire [AXIS_KEEP_WIDTH-1:0]  f_tkeep = fifo_mem[rd_ptr][AXIS_DATA_WIDTH +: AXIS_KEEP_WIDTH];
    wire [AXIS_TUSER_WIDTH-1:0] f_tuser = fifo_mem[rd_ptr][AXIS_DATA_WIDTH+AXIS_KEEP_WIDTH +: AXIS_TUSER_WIDTH];
    wire                        f_tlast = fifo_mem[rd_ptr][AXIS_DATA_WIDTH+AXIS_KEEP_WIDTH+AXIS_TUSER_WIDTH];

    reg [AXIS_DATA_WIDTH-1:0] tdata_icrc;
    always @(*) begin
        tdata_icrc = f_tdata;
        if (f_tlast && is_roce_q && icrc_done) begin
            if (is_single_q) begin
                tdata_icrc[8*58+7 : 8*58] = icrc_q[ 7: 0];
                tdata_icrc[8*59+7 : 8*59] = icrc_q[15: 8];
                tdata_icrc[8*60+7 : 8*60] = icrc_q[23:16];
                tdata_icrc[8*61+7 : 8*61] = icrc_q[31:24];
            end else begin
                tdata_icrc[8*54+7 : 8*54] = icrc_q[ 7: 0];
                tdata_icrc[8*55+7 : 8*55] = icrc_q[15: 8];
                tdata_icrc[8*56+7 : 8*56] = icrc_q[23:16];
                tdata_icrc[8*57+7 : 8*57] = icrc_q[31:24];
            end
        end
    end

    always @(*) begin
        m_axis_tdata  = tdata_icrc;
        m_axis_tkeep  = f_tkeep;
        m_axis_tuser  = f_tuser;
        m_axis_tlast  = f_tlast;
        m_axis_tvalid = (state == ST_DRAIN) && !fifo_empty;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr     <= 0;
            fifo_count <= 0;
        end else begin
            case ({s_axis_tvalid && s_axis_tready,
                   m_axis_tvalid && m_axis_tready})
                2'b10: fifo_count <= fifo_count + 1'b1;
                2'b01: fifo_count <= fifo_count - 1'b1;
                default: ;
            endcase
            if (m_axis_tvalid && m_axis_tready) begin
                if (m_axis_tlast) rd_ptr <= 0;
                else              rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

endmodule
