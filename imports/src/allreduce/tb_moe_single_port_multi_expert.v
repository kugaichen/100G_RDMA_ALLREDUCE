`timescale 1ns / 1ps
`include "moe_defs.vh"

module tb_moe_single_port_multi_expert;
    localparam DATA_W = 512;
    localparam KEEP_W = 64;
    localparam TUSER_W = 128;
    localparam NUM_PORTS = 4;
    localparam CLK_PERIOD = 3.103;

    localparam [47:0] CFG_FPGA_MAC = 48'h020000000307;
    localparam [31:0] CFG_FPGA_IP = 32'hC0A80307;
    localparam [23:0] CFG_FPGA_QPN = 24'h000100;
    localparam [15:0] CFG_UDP_PORT = 16'd4791;
    localparam [47:0] CFG_W0_MAC = 48'h6CB31188AB3E;
    localparam [31:0] CFG_W0_IP = 32'hC0A80305;
    localparam [23:0] CFG_W0_QPN = 24'h000200;
    localparam [47:0] CFG_W1_MAC = 48'h6CB31188A94E;
    localparam [31:0] CFG_W1_IP = 32'hC0A80306;
    localparam [23:0] CFG_W1_QPN = 24'h000201;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        #100;
        rst_n = 1'b1;
    end

    reg  [DATA_W-1:0] s_axis_tdata [0:NUM_PORTS-1];
    reg  [KEEP_W-1:0] s_axis_tkeep [0:NUM_PORTS-1];
    reg  [TUSER_W-1:0] s_axis_tuser [0:NUM_PORTS-1];
    reg  [NUM_PORTS-1:0] s_axis_tvalid = {NUM_PORTS{1'b0}};
    wire [NUM_PORTS-1:0] s_axis_tready;
    reg  [NUM_PORTS-1:0] s_axis_tlast = {NUM_PORTS{1'b0}};

    wire [DATA_W-1:0] m_axis_tdata [0:NUM_PORTS-1];
    wire [KEEP_W-1:0] m_axis_tkeep [0:NUM_PORTS-1];
    wire [TUSER_W-1:0] m_axis_tuser [0:NUM_PORTS-1];
    wire [NUM_PORTS-1:0] m_axis_tvalid;
    reg  [NUM_PORTS-1:0] m_axis_tready = {NUM_PORTS{1'b1}};
    wire [NUM_PORTS-1:0] m_axis_tlast;
    reg ar_cfg_update_en = 1'b0;

    nf_datapath_4port #(
        .C_S_AXI_DATA_WIDTH(32),
        .C_S_AXI_ADDR_WIDTH(32),
        .C_BASEADDR(32'h0),
        .C_M_AXIS_DATA_WIDTH(DATA_W),
        .C_S_AXIS_DATA_WIDTH(DATA_W),
        .C_M_AXIS_TUSER_WIDTH(TUSER_W),
        .C_S_AXIS_TUSER_WIDTH(TUSER_W),
        .NUM_QUEUES(NUM_PORTS),
        .MOE_EXPERT_PORT_MASK_FLAT(16'h0101)
    ) dut (
        .axis_aclk(clk),
        .axis_resetn(rst_n),
        .axi_aclk(clk),
        .axi_resetn(rst_n),
        .allreduce_clk(clk),
        .allreduce_rst_n(rst_n),

        .ar_cfg_update_en(ar_cfg_update_en),
        .ar_cfg_parent_port(8'h00),
        .ar_cfg_child_port_mask(4'h1),
        .ar_cfg_is_root(1'b1),
        .ar_cfg_fpga_mac(CFG_FPGA_MAC),
        .ar_cfg_fpga_ip(CFG_FPGA_IP),
        .ar_cfg_fpga_qp(CFG_FPGA_QPN),
        .ar_cfg_fpga_udp_port(CFG_UDP_PORT),
        .ar_cfg_worker0_mac(CFG_W0_MAC),
        .ar_cfg_worker0_ip(CFG_W0_IP),
        .ar_cfg_worker0_qp(CFG_W0_QPN),
        .ar_cfg_worker0_udp_port(CFG_UDP_PORT),
        .ar_cfg_worker1_mac(CFG_W1_MAC),
        .ar_cfg_worker1_ip(CFG_W1_IP),
        .ar_cfg_worker1_qp(CFG_W1_QPN),
        .ar_cfg_worker1_udp_port(CFG_UDP_PORT),
        .ar_cfg_worker2_mac(48'h0),
        .ar_cfg_worker2_ip(32'h0),
        .ar_cfg_worker2_qp(24'h0),
        .ar_cfg_worker2_udp_port(16'h0),
        .ar_cfg_worker3_mac(48'h0),
        .ar_cfg_worker3_ip(32'h0),
        .ar_cfg_worker3_qp(24'h0),
        .ar_cfg_worker3_udp_port(16'h0),

        .S0_AXI_AWADDR(32'h0), .S0_AXI_AWVALID(1'b0), .S0_AXI_WDATA(32'h0),
        .S0_AXI_WSTRB(4'h0), .S0_AXI_WVALID(1'b0), .S0_AXI_BREADY(1'b1),
        .S0_AXI_ARADDR(32'h0), .S0_AXI_ARVALID(1'b0), .S0_AXI_RREADY(1'b1),
        .S0_AXI_ARREADY(), .S0_AXI_RDATA(), .S0_AXI_RRESP(), .S0_AXI_RVALID(),
        .S0_AXI_WREADY(), .S0_AXI_BRESP(), .S0_AXI_BVALID(), .S0_AXI_AWREADY(),

        .S1_AXI_AWADDR(32'h0), .S1_AXI_AWVALID(1'b0), .S1_AXI_WDATA(32'h0),
        .S1_AXI_WSTRB(4'h0), .S1_AXI_WVALID(1'b0), .S1_AXI_BREADY(1'b1),
        .S1_AXI_ARADDR(32'h0), .S1_AXI_ARVALID(1'b0), .S1_AXI_RREADY(1'b1),
        .S1_AXI_ARREADY(), .S1_AXI_RDATA(), .S1_AXI_RRESP(), .S1_AXI_RVALID(),
        .S1_AXI_WREADY(), .S1_AXI_BRESP(), .S1_AXI_BVALID(), .S1_AXI_AWREADY(),

        .S2_AXI_AWADDR(32'h0), .S2_AXI_AWVALID(1'b0), .S2_AXI_WDATA(32'h0),
        .S2_AXI_WSTRB(4'h0), .S2_AXI_WVALID(1'b0), .S2_AXI_BREADY(1'b1),
        .S2_AXI_ARADDR(32'h0), .S2_AXI_ARVALID(1'b0), .S2_AXI_RREADY(1'b1),
        .S2_AXI_ARREADY(), .S2_AXI_RDATA(), .S2_AXI_RRESP(), .S2_AXI_RVALID(),
        .S2_AXI_WREADY(), .S2_AXI_BRESP(), .S2_AXI_BVALID(), .S2_AXI_AWREADY(),

        .s_axis_0_tdata(s_axis_tdata[0]), .s_axis_0_tkeep(s_axis_tkeep[0]),
        .s_axis_0_tuser(s_axis_tuser[0]), .s_axis_0_tvalid(s_axis_tvalid[0]),
        .s_axis_0_tready(s_axis_tready[0]), .s_axis_0_tlast(s_axis_tlast[0]),
        .s_axis_1_tdata(s_axis_tdata[1]), .s_axis_1_tkeep(s_axis_tkeep[1]),
        .s_axis_1_tuser(s_axis_tuser[1]), .s_axis_1_tvalid(s_axis_tvalid[1]),
        .s_axis_1_tready(s_axis_tready[1]), .s_axis_1_tlast(s_axis_tlast[1]),
        .s_axis_2_tdata(s_axis_tdata[2]), .s_axis_2_tkeep(s_axis_tkeep[2]),
        .s_axis_2_tuser(s_axis_tuser[2]), .s_axis_2_tvalid(s_axis_tvalid[2]),
        .s_axis_2_tready(s_axis_tready[2]), .s_axis_2_tlast(s_axis_tlast[2]),
        .s_axis_3_tdata(s_axis_tdata[3]), .s_axis_3_tkeep(s_axis_tkeep[3]),
        .s_axis_3_tuser(s_axis_tuser[3]), .s_axis_3_tvalid(s_axis_tvalid[3]),
        .s_axis_3_tready(s_axis_tready[3]), .s_axis_3_tlast(s_axis_tlast[3]),

        .m_axis_0_tdata(m_axis_tdata[0]), .m_axis_0_tkeep(m_axis_tkeep[0]),
        .m_axis_0_tuser(m_axis_tuser[0]), .m_axis_0_tvalid(m_axis_tvalid[0]),
        .m_axis_0_tready(m_axis_tready[0]), .m_axis_0_tlast(m_axis_tlast[0]),
        .m_axis_1_tdata(m_axis_tdata[1]), .m_axis_1_tkeep(m_axis_tkeep[1]),
        .m_axis_1_tuser(m_axis_tuser[1]), .m_axis_1_tvalid(m_axis_tvalid[1]),
        .m_axis_1_tready(m_axis_tready[1]), .m_axis_1_tlast(m_axis_tlast[1]),
        .m_axis_2_tdata(m_axis_tdata[2]), .m_axis_2_tkeep(m_axis_tkeep[2]),
        .m_axis_2_tuser(m_axis_tuser[2]), .m_axis_2_tvalid(m_axis_tvalid[2]),
        .m_axis_2_tready(m_axis_tready[2]), .m_axis_2_tlast(m_axis_tlast[2]),
        .m_axis_3_tdata(m_axis_tdata[3]), .m_axis_3_tkeep(m_axis_tkeep[3]),
        .m_axis_3_tuser(m_axis_tuser[3]), .m_axis_3_tvalid(m_axis_tvalid[3]),
        .m_axis_3_tready(m_axis_tready[3]), .m_axis_3_tlast(m_axis_tlast[3])
    );

    task set_byte;
        inout [DATA_W-1:0] word;
        input integer byte_idx;
        input [7:0] value;
        begin
            word[byte_idx*8 +: 8] = value;
        end
    endtask

    task put_mac;
        inout [DATA_W-1:0] word;
        input integer base;
        input [47:0] mac;
        begin
            set_byte(word, base + 0, mac[47:40]);
            set_byte(word, base + 1, mac[39:32]);
            set_byte(word, base + 2, mac[31:24]);
            set_byte(word, base + 3, mac[23:16]);
            set_byte(word, base + 4, mac[15:8]);
            set_byte(word, base + 5, mac[7:0]);
        end
    endtask

    task put16;
        inout [DATA_W-1:0] word;
        input integer base;
        input [15:0] value;
        begin
            set_byte(word, base + 0, value[15:8]);
            set_byte(word, base + 1, value[7:0]);
        end
    endtask

    task put24;
        inout [DATA_W-1:0] word;
        input integer base;
        input [23:0] value;
        begin
            set_byte(word, base + 0, value[23:16]);
            set_byte(word, base + 1, value[15:8]);
            set_byte(word, base + 2, value[7:0]);
        end
    endtask

    task put32;
        inout [DATA_W-1:0] word;
        input integer base;
        input [31:0] value;
        begin
            set_byte(word, base + 0, value[31:24]);
            set_byte(word, base + 1, value[23:16]);
            set_byte(word, base + 2, value[15:8]);
            set_byte(word, base + 3, value[7:0]);
        end
    endtask

    task build_moe_first_beat;
        output [DATA_W-1:0] word;
        input [47:0] src_mac;
        input [31:0] src_ip;
        input [7:0] op_type;
        input [7:0] owner_rank;
        input [7:0] flags;
        input [31:0] seq;
        input [31:0] psn;
        reg [15:0] udp_total_len;
        reg [15:0] ip_total_len;
        begin
            word = {DATA_W{1'b0}};
            udp_total_len = 16'd8 + 16'd12 + 16'd1024 + 16'd4;
            ip_total_len = 16'd20 + udp_total_len;

            put_mac(word, 0, CFG_FPGA_MAC);
            put_mac(word, 6, src_mac);
            put16(word, 12, 16'h0800);
            set_byte(word, 14, 8'h45);
            put16(word, 16, ip_total_len);
            put16(word, 18, 16'h1111);
            put16(word, 20, 16'h4000);
            set_byte(word, 23, 8'h11);
            put32(word, 26, src_ip);
            put32(word, 30, CFG_FPGA_IP);
            put16(word, 34, 16'hCAFE);
            put16(word, 36, CFG_UDP_PORT);
            put16(word, 38, udp_total_len);
            set_byte(word, 42, 8'h04);
            set_byte(word, 43, 8'h00);
            put16(word, 44, 16'hFFFF);
            set_byte(word, 46, 8'h00);
            put24(word, 47, CFG_FPGA_QPN);
            put32(word, 50, psn);
            put16(word, 54, `MOE_MAGIC);
            set_byte(word, 56, 8'h01);
            set_byte(word, 57, op_type);
            set_byte(word, 58, owner_rank);
            set_byte(word, 59, flags);
            put32(word, 60, seq);
        end
    endtask

    function [TUSER_W-1:0] build_tuser;
        input [7:0] src_port;
        input [15:0] pkt_len;
        begin
            build_tuser = {TUSER_W{1'b0}};
            build_tuser[23:16] = src_port;
            build_tuser[15:0] = pkt_len;
        end
    endfunction

    task send_moe_packet;
        input integer port;
        input [7:0] src_port_mask;
        input [47:0] src_mac;
        input [31:0] src_ip;
        input [7:0] op_type;
        input [7:0] owner_rank;
        input [7:0] flags;
        input [31:0] seq;
        input [31:0] psn;
        input [31:0] payload_word;
        reg [DATA_W-1:0] first;
        integer i;
        begin
            build_moe_first_beat(first, src_mac, src_ip, op_type,
                                 owner_rank, flags, seq, psn);
            @(posedge clk);
            while (!s_axis_tready[port]) @(posedge clk);
            s_axis_tdata[port] <= first;
            s_axis_tkeep[port] <= {KEEP_W{1'b1}};
            s_axis_tuser[port] <= build_tuser(src_port_mask, 16'd1078);
            s_axis_tvalid[port] <= 1'b1;
            s_axis_tlast[port] <= 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                @(posedge clk);
                while (!s_axis_tready[port]) @(posedge clk);
                s_axis_tdata[port] <= {16{payload_word}};
                s_axis_tkeep[port] <= (i == 15) ? {6'b0, {58{1'b1}}} : {KEEP_W{1'b1}};
                s_axis_tuser[port] <= build_tuser(src_port_mask, 16'd1078);
                s_axis_tvalid[port] <= 1'b1;
                s_axis_tlast[port] <= (i == 15);
            end
            @(posedge clk);
            while (!s_axis_tready[port]) @(posedge clk);
            s_axis_tvalid[port] <= 1'b0;
            s_axis_tlast[port] <= 1'b0;
            s_axis_tdata[port] <= {DATA_W{1'b0}};
            s_axis_tkeep[port] <= {KEEP_W{1'b0}};
            s_axis_tuser[port] <= {TUSER_W{1'b0}};
        end
    endtask

    integer p;
    integer beat_count [0:NUM_PORTS-1];
    integer dispatch_packet_count [0:NUM_PORTS-1];
    integer result_packet_count [0:NUM_PORTS-1];
    reg [7:0] packet_kind [0:NUM_PORTS-1];
    reg saw_dispatch_p0_a;
    reg saw_dispatch_p0_b;
    reg saw_result_p0;
    reg saw_result_payload;

    wire [31:0] dbg_dispatch_accept_count =
        dut.u_allreduce_wrapper.u_allreduce.dbg_moe_perf_counters_flat[31:0];
    wire [31:0] dbg_init_accept_count =
        dut.u_allreduce_wrapper.u_allreduce.dbg_moe_perf_counters_flat[63:32];
    wire [31:0] dbg_data_accept_count =
        dut.u_allreduce_wrapper.u_allreduce.dbg_moe_perf_counters_flat[95:64];
    wire [31:0] dbg_release_accept_count =
        dut.u_allreduce_wrapper.u_allreduce.dbg_moe_perf_counters_flat[127:96];
    wire [31:0] dbg_dispatch_output_count =
        dut.u_allreduce_wrapper.u_allreduce.dbg_moe_perf_counters_flat[159:128];
    wire [31:0] dbg_combine_output_count =
        dut.u_allreduce_wrapper.u_allreduce.dbg_moe_perf_counters_flat[191:160];
    wire [31:0] dbg_drop_event_count =
        dut.u_allreduce_wrapper.u_allreduce.dbg_moe_perf_counters_flat[255:224];

    initial begin
        for (p = 0; p < NUM_PORTS; p = p + 1) begin
            s_axis_tdata[p] = {DATA_W{1'b0}};
            s_axis_tkeep[p] = {KEEP_W{1'b0}};
            s_axis_tuser[p] = {TUSER_W{1'b0}};
            beat_count[p] = 0;
            dispatch_packet_count[p] = 0;
            result_packet_count[p] = 0;
            packet_kind[p] = `MOE_OP_NONE;
        end
        saw_dispatch_p0_a = 1'b0;
        saw_dispatch_p0_b = 1'b0;
        saw_result_p0 = 1'b0;
        saw_result_payload = 1'b0;

        wait (rst_n == 1'b1);
        @(posedge clk);
        ar_cfg_update_en = 1'b1;
        @(posedge clk);
        ar_cfg_update_en = 1'b0;
        repeat (100) @(posedge clk);

        send_moe_packet(0, 8'h01, CFG_W0_MAC, CFG_W0_IP,
                        `MOE_OP_DISPATCH, 8'd0, 8'h03,
                        32'd0, 32'h0000_2000, 32'h1122_3344);
        wait (dispatch_packet_count[0] == 2);
        repeat (40) @(posedge clk);

        send_moe_packet(0, 8'h01, CFG_W0_MAC, CFG_W0_IP,
                        `MOE_OP_COMBINE_DATA, 8'd0, 8'h00,
                        32'd0, 32'h0000_2001, 32'd2);
        repeat (12) @(posedge clk);
        send_moe_packet(0, 8'h01, CFG_W1_MAC, CFG_W1_IP,
                        `MOE_OP_COMBINE_DATA, 8'd0, 8'h01,
                        32'd0, 32'h0000_2002, 32'd3);

        wait (saw_result_p0 && saw_result_payload);
        repeat (60) @(posedge clk);

        if (!saw_dispatch_p0_a ||
            !saw_dispatch_p0_b ||
            dispatch_packet_count[0] != 2 ||
            dispatch_packet_count[1] != 0 ||
            result_packet_count[0] != 1 ||
            result_packet_count[1] != 0 ||
            result_packet_count[2] != 0 ||
            result_packet_count[3] != 0) begin
            $display("FAIL: packet counts/experts expert0=%0b expert1=%0b dispatch=%0d,%0d,%0d,%0d result=%0d,%0d,%0d,%0d",
                     saw_dispatch_p0_a,
                     saw_dispatch_p0_b,
                     dispatch_packet_count[0], dispatch_packet_count[1],
                     dispatch_packet_count[2], dispatch_packet_count[3],
                     result_packet_count[0], result_packet_count[1],
                     result_packet_count[2], result_packet_count[3]);
            $finish;
        end

        if (dbg_dispatch_accept_count != 32'd1 ||
            dbg_init_accept_count != 32'd1 ||
            dbg_data_accept_count != 32'd2 ||
            dbg_release_accept_count != 32'd1 ||
            dbg_dispatch_output_count != 32'd2 ||
            dbg_combine_output_count != 32'd1 ||
            dbg_drop_event_count != 32'd0) begin
            $display("FAIL: counters dispatch_accept=%0d init=%0d data=%0d release=%0d dispatch_out=%0d combine_out=%0d drop=%0d",
                     dbg_dispatch_accept_count, dbg_init_accept_count,
                     dbg_data_accept_count, dbg_release_accept_count,
                     dbg_dispatch_output_count, dbg_combine_output_count,
                     dbg_drop_event_count);
            $finish;
        end

        $display("TB_MOE_SINGLE_PORT_MULTI_EXPERT_PASS");
        $finish;
    end

    initial begin
        repeat (15000) @(posedge clk);
        $display("FAIL: timeout dispatch=%0d,%0d result=%0d payload=%0b counters da=%0d init=%0d data=%0d rel=%0d dout=%0d cout=%0d drop=%0d",
                 dispatch_packet_count[0], dispatch_packet_count[1],
                 result_packet_count[0], saw_result_payload,
                 dbg_dispatch_accept_count, dbg_init_accept_count,
                 dbg_data_accept_count, dbg_release_accept_count,
                 dbg_dispatch_output_count, dbg_combine_output_count,
                 dbg_drop_event_count);
        $finish;
    end

    genvar gi;
    generate
        for (gi = 0; gi < NUM_PORTS; gi = gi + 1) begin : gen_output_monitor
            wire [DATA_W-1:0] port_tdata = m_axis_tdata[gi];
            wire [TUSER_W-1:0] port_tuser = m_axis_tuser[gi];
            wire [7:0] first_beat_kind =
                (port_tdata[447:432] == `MOE_MAGIC &&
                 port_tdata[455:448] == 8'h01 &&
                 port_tdata[463:456] == `MOE_OP_DISPATCH) ? `MOE_OP_DISPATCH :
                (port_tdata[447:432] == `MOE_MAGIC &&
                 port_tdata[455:448] == `MOE_OP_COMBINE_RESULT) ? `MOE_OP_COMBINE_RESULT :
                `MOE_OP_NONE;

            always @(posedge clk) begin
                if (!rst_n) begin
                    beat_count[gi] <= 0;
                    dispatch_packet_count[gi] <= 0;
                    result_packet_count[gi] <= 0;
                    packet_kind[gi] <= `MOE_OP_NONE;
                end
                else if (m_axis_tvalid[gi] && m_axis_tready[gi]) begin
                    if (beat_count[gi] == 0) begin
                        packet_kind[gi] <= first_beat_kind;
                        if (first_beat_kind == `MOE_OP_DISPATCH) begin
                            if (gi != 0 ||
                                port_tuser[31:24] !== 8'h01 ||
                                port_tdata[343:336] !== 8'h04 ||
                                port_tdata[447:432] !== `MOE_MAGIC ||
                                port_tdata[463:456] !== `MOE_OP_DISPATCH ||
                                port_tdata[471:464] !== 8'd0 ||
                                (port_tdata[479:472] !== 8'h01 &&
                                 port_tdata[479:472] !== 8'h02)) begin
                                $display("FAIL: dispatch output mismatch port=%0d data=0x%0128h tuser=0x%032h",
                                         gi, port_tdata, port_tuser);
                                $finish;
                            end
                            if (port_tdata[479:472] == 8'h01) begin
                                saw_dispatch_p0_a <= 1'b1;
                            end
                            if (port_tdata[479:472] == 8'h02) begin
                                saw_dispatch_p0_b <= 1'b1;
                            end
                        end
                        else if (first_beat_kind == `MOE_OP_COMBINE_RESULT) begin
                            if (gi != 0 ||
                                port_tuser[31:24] !== 8'h01 ||
                                port_tdata[343:336] !== 8'h04 ||
                                port_tdata[447:432] !== `MOE_MAGIC ||
                                port_tdata[455:448] !== `MOE_OP_COMBINE_RESULT ||
                                port_tdata[463:456] !== 8'd0) begin
                                $display("FAIL: result output mismatch port=%0d data=0x%0128h tuser=0x%032h",
                                         gi, port_tdata, port_tuser);
                                $finish;
                            end
                            saw_result_p0 <= 1'b1;
                        end
                        else begin
                            $display("FAIL: unexpected output op=0x%02h port=%0d data=0x%0128h",
                                     first_beat_kind, gi, port_tdata);
                            $finish;
                        end
                    end
                    else if (packet_kind[gi] == `MOE_OP_COMBINE_RESULT &&
                             beat_count[gi] >= 1 && beat_count[gi] <= 3) begin
                        if (port_tdata[79:48] === 32'd5 &&
                            port_tdata[111:80] === 32'd5) begin
                            saw_result_payload <= 1'b1;
                        end
                    end

                    if (m_axis_tlast[gi]) begin
                        if (beat_count[gi] != 16 && beat_count[gi] != 17) begin
                            $display("FAIL: unexpected packet length port=%0d beats_before_last=%0d",
                                     gi, beat_count[gi]);
                            $finish;
                        end
                        if (packet_kind[gi] == `MOE_OP_DISPATCH) begin
                            dispatch_packet_count[gi] <= dispatch_packet_count[gi] + 1;
                        end
                        else if (packet_kind[gi] == `MOE_OP_COMBINE_RESULT) begin
                            result_packet_count[gi] <= result_packet_count[gi] + 1;
                        end
                        beat_count[gi] <= 0;
                        packet_kind[gi] <= `MOE_OP_NONE;
                    end
                    else begin
                        beat_count[gi] <= beat_count[gi] + 1;
                    end
                end
            end
        end
    endgenerate
endmodule
