`timescale 1ns / 1ps
`include "moe_defs.vh"

module tb_moe_dispatch_switch_integration;
    localparam DATA_W = 512;
    localparam KEEP_W = 64;
    localparam TUSER_W = 128;
    localparam NUM_PORTS = 4;
    localparam CLK_PERIOD = 3.103;

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

    localparam [47:0] CFG_FPGA_MAC = 48'h020000000307;
    localparam [31:0] CFG_FPGA_IP = 32'hC0A80307;
    localparam [23:0] CFG_FPGA_QPN = 24'h000100;
    localparam [15:0] CFG_UDP_PORT = 16'd4791;
    localparam [47:0] CFG_W0_MAC = 48'h6CB31188AB3E;
    localparam [31:0] CFG_W0_IP = 32'hC0A80305;
    localparam [23:0] CFG_W0_QPN = 24'h000200;
    localparam [47:0] CFG_W1_MAC = 48'h6CB31188AB3F;
    localparam [31:0] CFG_W1_IP = 32'hC0A80306;
    localparam [23:0] CFG_W1_QPN = 24'h000201;

    nf_datapath_4port #(
        .C_S_AXI_DATA_WIDTH(32),
        .C_S_AXI_ADDR_WIDTH(32),
        .C_BASEADDR(32'h0),
        .C_M_AXIS_DATA_WIDTH(DATA_W),
        .C_S_AXIS_DATA_WIDTH(DATA_W),
        .C_M_AXIS_TUSER_WIDTH(TUSER_W),
        .C_S_AXIS_TUSER_WIDTH(TUSER_W),
        .NUM_QUEUES(NUM_PORTS)
    ) dut (
        .axis_aclk(clk),
        .axis_resetn(rst_n),
        .axi_aclk(clk),
        .axi_resetn(rst_n),
        .allreduce_clk(clk),
        .allreduce_rst_n(rst_n),

        .ar_cfg_update_en(ar_cfg_update_en),
        .ar_cfg_parent_port(8'h00),
        .ar_cfg_child_port_mask(4'h3),
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

    task build_moe_dispatch_first_beat;
        output [DATA_W-1:0] word;
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
            put_mac(word, 6, CFG_W0_MAC);
            put16(word, 12, 16'h0800);
            set_byte(word, 14, 8'h45);
            put16(word, 16, ip_total_len);
            put16(word, 18, 16'h1111);
            put16(word, 20, 16'h4000);
            set_byte(word, 23, 8'h11);
            put32(word, 26, CFG_W0_IP);
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
            set_byte(word, 57, `MOE_OP_DISPATCH);
            set_byte(word, 58, 8'd0);
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

    task send_dispatch_packet;
        reg [DATA_W-1:0] first;
        integer i;
        begin
            build_moe_dispatch_first_beat(first, 8'h03, 32'd9, 32'h00001000);

            @(posedge clk);
            while (!s_axis_tready[0]) @(posedge clk);
            s_axis_tdata[0] <= first;
            s_axis_tkeep[0] <= {KEEP_W{1'b1}};
            s_axis_tuser[0] <= build_tuser(8'h01, 16'd1078);
            s_axis_tvalid[0] <= 1'b1;
            s_axis_tlast[0] <= 1'b0;

            for (i = 0; i < 16; i = i + 1) begin
                @(posedge clk);
                while (!s_axis_tready[0]) @(posedge clk);
                s_axis_tdata[0] <= {16{32'h11223344}};
                s_axis_tkeep[0] <= (i == 15) ? {6'b0, {58{1'b1}}} : {KEEP_W{1'b1}};
                s_axis_tuser[0] <= build_tuser(8'h01, 16'd1078);
                s_axis_tvalid[0] <= 1'b1;
                s_axis_tlast[0] <= (i == 15);
            end

            @(posedge clk);
            while (!s_axis_tready[0]) @(posedge clk);
            s_axis_tvalid[0] <= 1'b0;
            s_axis_tlast[0] <= 1'b0;
            s_axis_tdata[0] <= {DATA_W{1'b0}};
            s_axis_tkeep[0] <= {KEEP_W{1'b0}};
            s_axis_tuser[0] <= {TUSER_W{1'b0}};
        end
    endtask

    integer p;
    integer beat_count [0:NUM_PORTS-1];
    integer pkt_count [0:NUM_PORTS-1];
    integer ingress_fire_count;
    integer arbiter_fire_count;
    integer ar_input_fire_count;
    integer opl_input_fire_count;
    integer opl_output_fire_count;
    integer opl_eth_done_count;
    integer opl_lookup_done_count;
    reg saw_dispatch [0:NUM_PORTS-1];

    initial begin
        for (p = 0; p < NUM_PORTS; p = p + 1) begin
            s_axis_tdata[p] = {DATA_W{1'b0}};
            s_axis_tkeep[p] = {KEEP_W{1'b0}};
            s_axis_tuser[p] = {TUSER_W{1'b0}};
            beat_count[p] = 0;
            pkt_count[p] = 0;
            saw_dispatch[p] = 1'b0;
        end
        ingress_fire_count = 0;
        arbiter_fire_count = 0;
        ar_input_fire_count = 0;
        opl_input_fire_count = 0;
        opl_output_fire_count = 0;
        opl_eth_done_count = 0;
        opl_lookup_done_count = 0;

        wait (rst_n == 1'b1);
        @(posedge clk);
        ar_cfg_update_en = 1'b1;
        @(posedge clk);
        ar_cfg_update_en = 1'b0;
        repeat (100) @(posedge clk);

        $display("DBG: MoE params combine=%0d real_payload=%0d dispatch_init=%0d dispatch_egress=%0d",
                 dut.u_allreduce_wrapper.u_allreduce.ENABLE_MOE_COMBINE,
                 dut.u_allreduce_wrapper.u_allreduce.MOE_USE_REAL_PAYLOAD,
                 dut.u_allreduce_wrapper.u_allreduce.ENABLE_MOE_DISPATCH_INIT,
                 dut.u_allreduce_wrapper.u_allreduce.ENABLE_MOE_DISPATCH_EGRESS);

        if (dut.u_allreduce_wrapper.u_allreduce.ENABLE_MOE_COMBINE != 1 ||
            dut.u_allreduce_wrapper.u_allreduce.MOE_USE_REAL_PAYLOAD != 1 ||
            dut.u_allreduce_wrapper.u_allreduce.ENABLE_MOE_DISPATCH_INIT != 1 ||
            dut.u_allreduce_wrapper.u_allreduce.ENABLE_MOE_DISPATCH_EGRESS != 1) begin
            $display("FAIL: MoE is disabled in nf_datapath allreduce core. Check nf_datapath_4port/allreduce_offload_wrapper source update in Vivado.");
            $finish;
        end

        send_dispatch_packet();

        repeat (2000) @(posedge clk);

        if (!saw_dispatch[0] || !saw_dispatch[1]) begin
            $display("FAIL: missing dispatch output p0=%0b p1=%0b pkt0=%0d pkt1=%0d",
                     saw_dispatch[0], saw_dispatch[1], pkt_count[0], pkt_count[1]);
            $display("DBG: s_opl valid=%0b ready=%0b ar_s valid=%0b ready=%0b ar_m valid=%0b ready=%0b",
                     dut.s_axis_opl_tvalid,
                     dut.s_axis_opl_tready,
                     dut.ar_s_tvalid,
                     dut.ar_s_tready,
                     dut.ar_m_tvalid,
                     dut.ar_m_tready);
            $display("DBG: input handshakes ingress=%0d arbiter=%0d ar_input=%0d s0_valid=%0b s0_ready=%0b",
                     ingress_fire_count,
                     arbiter_fire_count,
                     ar_input_fire_count,
                     s_axis_tvalid[0],
                     s_axis_tready[0]);
            $display("DBG: opl handshakes input=%0d output=%0d eth_done=%0d lookup_done=%0d",
                     opl_input_fire_count,
                     opl_output_fire_count,
                     opl_eth_done_count,
                     opl_lookup_done_count);
            $display("DBG: core dispatch accept=%0d init=%0d dispatch_out=%0d drop=%0d desc_pending=%0b payload_pending=%0b egress_valid=%0b ready=%0b",
                     dut.u_allreduce_wrapper.u_allreduce.dbg_moe_dispatch_accept_count,
                     dut.u_allreduce_wrapper.u_allreduce.dbg_moe_init_accept_count,
                     dut.u_allreduce_wrapper.u_allreduce.dbg_moe_dispatch_output_count,
                     dut.u_allreduce_wrapper.u_allreduce.dbg_moe_drop_event_count,
                     dut.u_allreduce_wrapper.u_allreduce.moe_dispatch_desc_pending,
                     dut.u_allreduce_wrapper.u_allreduce.moe_dispatch_payload_pending,
                     dut.u_allreduce_wrapper.u_allreduce.moe_dispatch_egress_valid,
                     dut.u_allreduce_wrapper.u_allreduce.moe_dispatch_egress_ready);
            $display("DBG: cdc_out empty=%0b full=%0b to_opl valid=%0b ready=%0b opl_out valid=%0b ready=%0b dst=0x%02h",
                     dut.cdc_out_empty,
                     dut.cdc_out_full,
                     dut.allreduce_to_opl_tvalid,
                     dut.allreduce_to_opl_tready,
                     dut.m_axis_opl_tvalid,
                     dut.m_axis_opl_tready,
                     dut.m_axis_opl_tuser[31:24]);
            $display("DBG: opl state=%0d in_empty=%0b in_nearly_full=%0b eth_done=%0b lookup_done=%0b dst_empty=%0b send=%0b head_dst=0x%012h head_src=0x%012h",
                     dut.u_output_port_lookup.state,
                     dut.u_output_port_lookup.in_fifo_empty,
                     dut.u_output_port_lookup.in_fifo_nearly_full,
                     dut.u_output_port_lookup.eth_done,
                     dut.u_output_port_lookup.lookup_done,
                     dut.u_output_port_lookup.dst_port_fifo_empty,
                     dut.u_output_port_lookup.send_packet,
                     dut.allreduce_to_opl_tdata[47:0],
                     dut.allreduce_to_opl_tdata[95:48]);
            $finish;
        end

        if (pkt_count[0] != 1 || pkt_count[1] != 1) begin
            $display("FAIL: wrong dispatch packet count pkt0=%0d pkt1=%0d",
                     pkt_count[0], pkt_count[1]);
            $finish;
        end

        if (pkt_count[2] != 0 || pkt_count[3] != 0) begin
            $display("FAIL: unexpected dispatch output on p2/p3 pkt2=%0d pkt3=%0d",
                     pkt_count[2], pkt_count[3]);
            $finish;
        end

        $display("TB_MOE_DISPATCH_SWITCH_INTEGRATION_PASS");
        $finish;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ingress_fire_count <= 0;
            arbiter_fire_count <= 0;
            ar_input_fire_count <= 0;
        end else begin
            if (s_axis_tvalid[0] && s_axis_tready[0])
                ingress_fire_count <= ingress_fire_count + 1;
            if (dut.s_axis_opl_tvalid && dut.s_axis_opl_tready)
                arbiter_fire_count <= arbiter_fire_count + 1;
            if (dut.ar_s_tvalid && dut.ar_s_tready)
                ar_input_fire_count <= ar_input_fire_count + 1;
            if (dut.allreduce_to_opl_tvalid && dut.allreduce_to_opl_tready)
                opl_input_fire_count <= opl_input_fire_count + 1;
            if (dut.m_axis_opl_tvalid && dut.m_axis_opl_tready)
                opl_output_fire_count <= opl_output_fire_count + 1;
            if (dut.u_output_port_lookup.eth_done)
                opl_eth_done_count <= opl_eth_done_count + 1;
            if (dut.u_output_port_lookup.lookup_done)
                opl_lookup_done_count <= opl_lookup_done_count + 1;
        end
    end

    genvar gi;
    generate
        for (gi = 0; gi < NUM_PORTS; gi = gi + 1) begin : gen_output_monitor
            wire [DATA_W-1:0] port_tdata = m_axis_tdata[gi];
            wire [TUSER_W-1:0] port_tuser = m_axis_tuser[gi];

            always @(posedge clk) begin
                if (!rst_n) begin
                    beat_count[gi] <= 0;
                    pkt_count[gi] <= 0;
                    saw_dispatch[gi] <= 1'b0;
                end else if (m_axis_tvalid[gi] && m_axis_tready[gi]) begin
                    if (beat_count[gi] == 0) begin
                        if (gi < 2) begin
                            if (port_tuser[31:24] !== (gi == 0 ? 8'h01 : 8'h02)) begin
                                $display("FAIL: wrong tuser dst on port%0d dst=0x%02h",
                                         gi, port_tuser[31:24]);
                                $finish;
                            end

                            if (port_tdata[343:336] !== 8'h04 ||
                                port_tdata[447:432] !== `MOE_MAGIC ||
                                port_tdata[455:448] !== 8'h01 ||
                                port_tdata[463:456] !== `MOE_OP_DISPATCH ||
                                port_tdata[471:464] !== 8'd0 ||
                                port_tdata[479:472] !== (gi == 0 ? 8'h01 : 8'h02) ||
                                port_tdata[511:480] !== 32'd9) begin
                                $display("FAIL: dispatch header mismatch port%0d data=0x%0128h",
                                         gi, port_tdata);
                                $finish;
                            end

                            saw_dispatch[gi] <= 1'b1;
                        end
                    end

                    if (m_axis_tlast[gi]) begin
                        pkt_count[gi] <= pkt_count[gi] + 1;
                        beat_count[gi] <= 0;
                    end else begin
                        beat_count[gi] <= beat_count[gi] + 1;
                    end
                end
            end
        end
    endgenerate
endmodule
