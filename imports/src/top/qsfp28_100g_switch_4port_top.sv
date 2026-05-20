// Copyright (c) 2026 Xuanwu Tech. All rights reserved.
// 4-port 100G QSFP28 switch top (NetFPGA-PLUS reference_switch datapath, 4-port adapted)
//
// Pipeline per port:
//   CMAC RX (322 MHz) -> cmac_rx_adapter (FIFO + TUSER builder)
//   -> nf_datapath_4port (input_arbiter -> OPL -> output_queues, axis_aclk = cmac_tx_clk[0])
//   -> cmac_tx_adapter (FIFO) -> CMAC TX (322 MHz)
//
// Port one-hot encoding (TUSER[31:24]=dst, TUSER[23:16]=src):
//   P0=8'h01  P1=8'h02  P2=8'h04  P3=8'h08
//
// AXI-Lite control plane (3 slaves S0/S1/S2 inside nf_datapath_4port) is tied off;
// switch_output_port_lookup runs in self-learning mode, no CPU table writes needed.
`timescale 1ns / 1ps

module qsfp28_100g_switch_4port_top (
    input  logic        sys_clk_90m,

    // GT Reference Clocks (322.265625 MHz)
    input  logic        QSFPDD0_REFCLK_P,
    input  logic        QSFPDD0_REFCLK_N,
    input  logic        QSFPDD1_REFCLK_P,
    input  logic        QSFPDD1_REFCLK_N,
    input  logic        QSFPDD2_REFCLK_P,
    input  logic        QSFPDD2_REFCLK_N,
    input  logic        QSFPDD3_REFCLK_P,
    input  logic        QSFPDD3_REFCLK_N,

    output logic [3:0]  qsfp0_tx_p,
    output logic [3:0]  qsfp0_tx_n,
    input  logic [3:0]  qsfp0_rx_p,
    input  logic [3:0]  qsfp0_rx_n,

    output logic [3:0]  qsfp1_tx_p,
    output logic [3:0]  qsfp1_tx_n,
    input  logic [3:0]  qsfp1_rx_p,
    input  logic [3:0]  qsfp1_rx_n,

    output logic [3:0]  qsfp2_tx_p,
    output logic [3:0]  qsfp2_tx_n,
    input  logic [3:0]  qsfp2_rx_p,
    input  logic [3:0]  qsfp2_rx_n,

    output logic [3:0]  qsfp3_tx_p,
    output logic [3:0]  qsfp3_tx_n,
    input  logic [3:0]  qsfp3_rx_p,
    input  logic [3:0]  qsfp3_rx_n
);

    localparam int NUM_PORTS = 4;
    localparam int DATA_W    = 512;
    localparam int KEEP_W    = 64;
    localparam int TUSER_W   = 128;

    // ========================================================================
    // System clock / reset
    // ========================================================================
    logic sys_clk;
    logic sys_rst_n;

    clk_rst_gen u_clk_rst (
        .sys_clk_90m (sys_clk_90m),
        .sys_clk     (sys_clk),
        .sys_rst_n   (sys_rst_n)
    );

    // ========================================================================
    // Allreduce 250 MHz clock (from sys_clk 90 MHz via MMCM)
    // ========================================================================
    logic allreduce_clk;
    logic allreduce_locked;
    logic allreduce_rst_n;

    clk_wiz_0 u_allreduce_pll (
        .clk_in1  (sys_clk),
        .clk_out1 (allreduce_clk),
        .reset    (~sys_rst_n),
        .locked   (allreduce_locked)
    );

    logic [2:0] ar_rst_sync;
    always_ff @(posedge allreduce_clk or negedge allreduce_locked) begin
        if (!allreduce_locked) ar_rst_sync <= 3'b000;
        else                   ar_rst_sync <= {ar_rst_sync[1:0], 1'b1};
    end
    assign allreduce_rst_n = ar_rst_sync[2];

    // ========================================================================
    // VIO global control (subset that still applies to switch mode)
    // ========================================================================
    logic        vio_test_start;
    logic        vio_test_stop;
    logic        vio_test_reset;
    logic [15:0] vio_pkt_length;
    logic [47:0] vio_pkt_count;
    logic [1:0]  vio_tx_pattern_sel;
    logic [3:0]  vio_port_enable;
    logic        vio_gt_loopback_en;
    logic        vio_continuous_mode;
    logic        vio_snap_stats;

    logic        all_link_up;
    logic        all_test_pass;
    logic        any_error;
    logic [3:0]  port_link_status;
    logic [3:0]  port_error_status;
    logic        test_running;

    logic vio_test_start_d, vio_test_stop_d, vio_test_reset_d, vio_snap_stats_d;
    logic test_start_pulse, test_stop_pulse, test_reset_pulse, snap_stats_pulse;

    always_ff @(posedge sys_clk) begin
        vio_test_start_d <= vio_test_start;
        vio_test_stop_d  <= vio_test_stop;
        vio_test_reset_d <= vio_test_reset;
        vio_snap_stats_d <= vio_snap_stats;
    end

    assign test_start_pulse = vio_test_start & ~vio_test_start_d;
    assign test_stop_pulse  = vio_test_stop  & ~vio_test_stop_d;
    assign test_reset_pulse = vio_test_reset & ~vio_test_reset_d;
    assign snap_stats_pulse = vio_snap_stats & ~vio_snap_stats_d;

    vio_global_ctrl u_vio_global (
        .clk        (sys_clk),
        .probe_in0  (all_link_up),
        .probe_in1  (all_test_pass),
        .probe_in2  (any_error),
        .probe_in3  (port_link_status),
        .probe_in4  (port_error_status),
        .probe_in5  (test_running),
        .probe_out0 (vio_test_start),
        .probe_out1 (vio_test_stop),
        .probe_out2 (vio_test_reset),
        .probe_out3 (vio_pkt_length),
        .probe_out4 (vio_pkt_count),
        .probe_out5 (vio_tx_pattern_sel),
        .probe_out6 (vio_port_enable),
        .probe_out7 (vio_gt_loopback_en),
        .probe_out8 (vio_continuous_mode),
        .probe_out9 (vio_snap_stats)
    );

    // Anchor unused VIO outputs so synthesis does not optimize the cores away.
    logic unused_global_ctrl;
    assign unused_global_ctrl = ^{test_start_pulse, test_stop_pulse, snap_stats_pulse,
                                  vio_pkt_length, vio_pkt_count, vio_tx_pattern_sel,
                                  vio_continuous_mode};

    // ========================================================================
    // Per-port clock / reset / status
    // ========================================================================
    logic [3:0]  cmac_gt_tx_reset_done;
    logic [3:0]  cmac_gt_rx_reset_done;
    logic [3:0]  cmac_stat_rx_aligned;
    logic [3:0]  cmac_stat_rx_status;
    logic [3:0]  cmac_stat_rx_bad_fcs;
    logic [3:0]  cmac_tx_clk;
    logic [3:0]  cmac_tx_rst;
    logic [3:0]  cmac_rx_clk;
    logic [3:0]  cmac_rx_rst;

    assign cmac_gt_tx_reset_done = ~cmac_tx_rst;
    assign cmac_gt_rx_reset_done = ~cmac_rx_rst;

    logic [3:0]  ctl_tx_enable;
    logic [3:0]  ctl_rx_enable;
    logic [3:0]  ctl_tx_send_rfi;
    logic [3:0]  ctl_tx_send_lfi;
    logic [3:0]  ctl_tx_send_idle;
    logic [2:0]  gt_loopback [NUM_PORTS];

    logic [3:0]  port_link_up;
    logic [3:0]  port_init_done;
    logic [3:0]  port_init_state [NUM_PORTS];

    // ========================================================================
    // Datapath clock / reset (use port-0 CMAC TX user clock as switch_clk)
    // ========================================================================
    logic        switch_clk;
    logic        switch_rst;

    assign switch_clk = cmac_tx_clk[0];
    assign switch_rst = cmac_tx_rst[0];

    // ========================================================================
    // CMAC <-> datapath AXIS plumbing
    // ========================================================================
    // CMAC TX/RX raw AXIS (each in its own CMAC clock domain)
    logic [DATA_W-1:0]  rx_tdata  [NUM_PORTS];
    logic [KEEP_W-1:0]  rx_tkeep  [NUM_PORTS];
    logic [3:0]         rx_tvalid;
    logic [3:0]         rx_tlast;

    logic [DATA_W-1:0]  tx_tdata  [NUM_PORTS];
    logic [KEEP_W-1:0]  tx_tkeep  [NUM_PORTS];
    logic [3:0]         tx_tvalid;
    logic [3:0]         tx_tready;
    logic [3:0]         tx_tlast;

    // Adapter <-> datapath AXIS (all in switch_clk domain, with TUSER)
    logic [DATA_W-1:0]  dp_s_tdata  [NUM_PORTS];
    logic [KEEP_W-1:0]  dp_s_tkeep  [NUM_PORTS];
    logic [TUSER_W-1:0] dp_s_tuser  [NUM_PORTS];
    logic [3:0]         dp_s_tvalid;
    logic [3:0]         dp_s_tready;
    logic [3:0]         dp_s_tlast;

    logic [DATA_W-1:0]  dp_m_tdata  [NUM_PORTS];
    logic [KEEP_W-1:0]  dp_m_tkeep  [NUM_PORTS];
    logic [TUSER_W-1:0] dp_m_tuser  [NUM_PORTS];
    logic [3:0]         dp_m_tvalid;
    logic [3:0]         dp_m_tready;
    logic [3:0]         dp_m_tlast;

    logic [3:0]         ingress_overflow;
    logic [3:0]         egress_overflow;

    assign port_link_status  = port_link_up;
    assign port_error_status = ingress_overflow | egress_overflow;
    assign all_link_up       = &port_link_up;
    assign any_error         = |port_error_status;
    assign all_test_pass     = all_link_up & ~any_error;
    assign test_running      = 1'b0;

    // ========================================================================
    // CMAC controllers (link bring-up)
    // ========================================================================
    genvar gi;
    generate
        for (gi = 0; gi < NUM_PORTS; gi = gi + 1) begin : gen_cmac_ctrl
            cmac_ctrl u_cmac_ctrl (
                .sys_clk         (sys_clk),
                .sys_rst_n       (sys_rst_n),
                .gt_tx_reset_done(cmac_gt_tx_reset_done[gi]),
                .gt_rx_reset_done(cmac_gt_rx_reset_done[gi]),
                .ctl_tx_enable   (ctl_tx_enable[gi]),
                .ctl_rx_enable   (ctl_rx_enable[gi]),
                .ctl_tx_send_rfi (ctl_tx_send_rfi[gi]),
                .ctl_tx_send_lfi (ctl_tx_send_lfi[gi]),
                .ctl_tx_send_idle(ctl_tx_send_idle[gi]),
                .gt_loopback     (gt_loopback[gi]),
                .stat_rx_aligned (cmac_stat_rx_aligned[gi]),
                .stat_rx_status  (cmac_stat_rx_status[gi]),
                .gt_loopback_en  (vio_gt_loopback_en),
                .port_enable     (vio_port_enable[gi]),
                .link_up         (port_link_up[gi]),
                .init_done       (port_init_done[gi]),
                .init_state      (port_init_state[gi])
            );
        end
    endgenerate

    // ========================================================================
    // 4 pairs of CMAC <-> switch adapters (CDC + TUSER builder)
    // ========================================================================
    // src_port one-hot (low 4 bits): P0=01, P1=02, P2=04, P3=08
    logic [7:0] src_port_1hot [NUM_PORTS];
    assign src_port_1hot[0] = 8'h01;
    assign src_port_1hot[1] = 8'h02;
    assign src_port_1hot[2] = 8'h04;
    assign src_port_1hot[3] = 8'h08;

    generate
        for (gi = 0; gi < NUM_PORTS; gi = gi + 1) begin : gen_adapter
            cmac_rx_adapter u_rx_adapter (
                .cmac_rx_clk      (cmac_rx_clk[gi]),
                .cmac_rx_rst      (cmac_rx_rst[gi]),
                .switch_clk       (switch_clk),
                .switch_rst       (switch_rst),
                .src_port_1hot    (src_port_1hot[gi]),
                .rx_axis_tdata    (rx_tdata[gi]),
                .rx_axis_tkeep    (rx_tkeep[gi]),
                .rx_axis_tvalid   (rx_tvalid[gi]),
                .rx_axis_tlast    (rx_tlast[gi]),
                .m_axis_tdata     (dp_s_tdata[gi]),
                .m_axis_tkeep     (dp_s_tkeep[gi]),
                .m_axis_tuser     (dp_s_tuser[gi]),
                .m_axis_tvalid    (dp_s_tvalid[gi]),
                .m_axis_tready    (dp_s_tready[gi]),
                .m_axis_tlast     (dp_s_tlast[gi]),
                .pkt_drop_overflow(ingress_overflow[gi])
            );

            cmac_tx_adapter u_tx_adapter (
                .switch_clk       (switch_clk),
                .switch_rst       (switch_rst),
                .cmac_tx_clk      (cmac_tx_clk[gi]),
                .cmac_tx_rst      (cmac_tx_rst[gi]),
                .s_axis_tdata     (dp_m_tdata[gi]),
                .s_axis_tkeep     (dp_m_tkeep[gi]),
                .s_axis_tuser     (dp_m_tuser[gi]),
                .s_axis_tvalid    (dp_m_tvalid[gi]),
                .s_axis_tready    (dp_m_tready[gi]),
                .s_axis_tlast     (dp_m_tlast[gi]),
                .tx_axis_tdata    (tx_tdata[gi]),
                .tx_axis_tkeep    (tx_tkeep[gi]),
                .tx_axis_tvalid   (tx_tvalid[gi]),
                .tx_axis_tready   (tx_tready[gi]),
                .tx_axis_tlast    (tx_tlast[gi]),
                .pkt_drop_overflow(egress_overflow[gi])
            );
        end
    endgenerate

    // ========================================================================
    // NetFPGA-PLUS reference_switch datapath, adapted to 4 ports
    //   axis_aclk = switch_clk (= cmac_tx_clk[0], 322.265625 MHz)
    //   axi_aclk  = sys_clk
    //   3 AXI-Lite slaves S0/S1/S2 are tied off.
    // ========================================================================
    nf_datapath_4port #(
        .C_S_AXI_DATA_WIDTH  (32),
        .C_S_AXI_ADDR_WIDTH  (32),
        .C_BASEADDR          (32'h0000_0000),
        .C_M_AXIS_DATA_WIDTH (DATA_W),
        .C_S_AXIS_DATA_WIDTH (DATA_W),
        .C_M_AXIS_TUSER_WIDTH(TUSER_W),
        .C_S_AXIS_TUSER_WIDTH(TUSER_W),
        .NUM_QUEUES          (NUM_PORTS)
    ) u_nf_datapath (
        .axis_aclk    (switch_clk),
        .axis_resetn  (~switch_rst),
        .axi_aclk     (sys_clk),
        .axi_resetn   (sys_rst_n),
        .allreduce_clk   (allreduce_clk),
        .allreduce_rst_n (allreduce_rst_n),

        // S0_AXI (input_arbiter): tie off
        .S0_AXI_AWADDR (32'h0), .S0_AXI_AWVALID(1'b0),
        .S0_AXI_WDATA  (32'h0), .S0_AXI_WSTRB  (4'h0), .S0_AXI_WVALID(1'b0),
        .S0_AXI_BREADY (1'b1),
        .S0_AXI_ARADDR (32'h0), .S0_AXI_ARVALID(1'b0),
        .S0_AXI_RREADY (1'b1),
        .S0_AXI_ARREADY(),       .S0_AXI_RDATA (), .S0_AXI_RRESP (),
        .S0_AXI_RVALID (),       .S0_AXI_WREADY(), .S0_AXI_BRESP (),
        .S0_AXI_BVALID (),       .S0_AXI_AWREADY(),

        // S1_AXI (output_port_lookup): tie off (self-learning mode)
        .S1_AXI_AWADDR (32'h0), .S1_AXI_AWVALID(1'b0),
        .S1_AXI_WDATA  (32'h0), .S1_AXI_WSTRB  (4'h0), .S1_AXI_WVALID(1'b0),
        .S1_AXI_BREADY (1'b1),
        .S1_AXI_ARADDR (32'h0), .S1_AXI_ARVALID(1'b0),
        .S1_AXI_RREADY (1'b1),
        .S1_AXI_ARREADY(),       .S1_AXI_RDATA (), .S1_AXI_RRESP (),
        .S1_AXI_RVALID (),       .S1_AXI_WREADY(), .S1_AXI_BRESP (),
        .S1_AXI_BVALID (),       .S1_AXI_AWREADY(),

        // S2_AXI (output_queues): tie off
        .S2_AXI_AWADDR (32'h0), .S2_AXI_AWVALID(1'b0),
        .S2_AXI_WDATA  (32'h0), .S2_AXI_WSTRB  (4'h0), .S2_AXI_WVALID(1'b0),
        .S2_AXI_BREADY (1'b1),
        .S2_AXI_ARADDR (32'h0), .S2_AXI_ARVALID(1'b0),
        .S2_AXI_RREADY (1'b1),
        .S2_AXI_ARREADY(),       .S2_AXI_RDATA (), .S2_AXI_RRESP (),
        .S2_AXI_RVALID (),       .S2_AXI_WREADY(), .S2_AXI_BRESP (),
        .S2_AXI_BVALID (),       .S2_AXI_AWREADY(),

        // Ingress (4 RX adapters -> datapath)
        .s_axis_0_tdata (dp_s_tdata[0]),  .s_axis_0_tkeep (dp_s_tkeep[0]),
        .s_axis_0_tuser (dp_s_tuser[0]),  .s_axis_0_tvalid(dp_s_tvalid[0]),
        .s_axis_0_tready(dp_s_tready[0]), .s_axis_0_tlast (dp_s_tlast[0]),

        .s_axis_1_tdata (dp_s_tdata[1]),  .s_axis_1_tkeep (dp_s_tkeep[1]),
        .s_axis_1_tuser (dp_s_tuser[1]),  .s_axis_1_tvalid(dp_s_tvalid[1]),
        .s_axis_1_tready(dp_s_tready[1]), .s_axis_1_tlast (dp_s_tlast[1]),

        .s_axis_2_tdata (dp_s_tdata[2]),  .s_axis_2_tkeep (dp_s_tkeep[2]),
        .s_axis_2_tuser (dp_s_tuser[2]),  .s_axis_2_tvalid(dp_s_tvalid[2]),
        .s_axis_2_tready(dp_s_tready[2]), .s_axis_2_tlast (dp_s_tlast[2]),

        .s_axis_3_tdata (dp_s_tdata[3]),  .s_axis_3_tkeep (dp_s_tkeep[3]),
        .s_axis_3_tuser (dp_s_tuser[3]),  .s_axis_3_tvalid(dp_s_tvalid[3]),
        .s_axis_3_tready(dp_s_tready[3]), .s_axis_3_tlast (dp_s_tlast[3]),

        // Egress (datapath -> 4 TX adapters)
        .m_axis_0_tdata (dp_m_tdata[0]),  .m_axis_0_tkeep (dp_m_tkeep[0]),
        .m_axis_0_tuser (dp_m_tuser[0]),  .m_axis_0_tvalid(dp_m_tvalid[0]),
        .m_axis_0_tready(dp_m_tready[0]), .m_axis_0_tlast (dp_m_tlast[0]),

        .m_axis_1_tdata (dp_m_tdata[1]),  .m_axis_1_tkeep (dp_m_tkeep[1]),
        .m_axis_1_tuser (dp_m_tuser[1]),  .m_axis_1_tvalid(dp_m_tvalid[1]),
        .m_axis_1_tready(dp_m_tready[1]), .m_axis_1_tlast (dp_m_tlast[1]),

        .m_axis_2_tdata (dp_m_tdata[2]),  .m_axis_2_tkeep (dp_m_tkeep[2]),
        .m_axis_2_tuser (dp_m_tuser[2]),  .m_axis_2_tvalid(dp_m_tvalid[2]),
        .m_axis_2_tready(dp_m_tready[2]), .m_axis_2_tlast (dp_m_tlast[2]),

        .m_axis_3_tdata (dp_m_tdata[3]),  .m_axis_3_tkeep (dp_m_tkeep[3]),
        .m_axis_3_tuser (dp_m_tuser[3]),  .m_axis_3_tvalid(dp_m_tvalid[3]),
        .m_axis_3_tready(dp_m_tready[3]), .m_axis_3_tlast (dp_m_tlast[3])
    );
    
//    //----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG

//ila_0 ila_nfdatapath (
//	.clk(clk), // input wire clk
//	.probe0(dp_s_tdata[0]), // input wire [511:0]  probe0  
//	.probe1(dp_s_tready[0]), // input wire [63:0]  probe1 
//	.probe2(probe2), // input wire [0:0]  probe2 
//	.probe3(), // input wire [0:0]  probe3 
//	.probe4(dp_m_tdata[0]), // input wire [511:0]  probe4 
//	.probe5(dp_m_tready[0]), // input wire [63:0]  probe5 
//	.probe6(probe6), // input wire [0:0]  probe6 
//	.probe7(probe7) // input wire [0:0]  probe7
//);

//// INST_TAG_END ------ End INSTANTIATION Template ---------
    // ========================================================================
    // CMAC 0..3 (unchanged from MAC_100g_loopback_test_4port top)
    // ========================================================================
    cmac_usplus_0 u_cmac0 (
        .gt_txp_out                  (qsfp0_tx_p),
        .gt_txn_out                  (qsfp0_tx_n),
        .gt_rxp_in                   (qsfp0_rx_p),
        .gt_rxn_in                   (qsfp0_rx_n),
        .gt_ref_clk_p                (QSFPDD0_REFCLK_P),
        .gt_ref_clk_n                (QSFPDD0_REFCLK_N),
        .gt_ref_clk_out              (),
        .gt_rxrecclkout              (),
        .gt_powergoodout             (),
        .gt_txusrclk2                (cmac_tx_clk[0]),
        .gt_rxusrclk2                (cmac_rx_clk[0]),
        .gt_loopback_in              ({4{gt_loopback[0]}}),
        .rx_axis_tdata               (rx_tdata[0]),
        .rx_axis_tkeep               (rx_tkeep[0]),
        .rx_axis_tvalid              (rx_tvalid[0]),
        .rx_axis_tlast               (rx_tlast[0]),
        .rx_axis_tuser               (),
        .tx_axis_tdata               (tx_tdata[0]),
        .tx_axis_tkeep               (tx_tkeep[0]),
        .tx_axis_tvalid              (tx_tvalid[0]),
        .tx_axis_tready              (tx_tready[0]),
        .tx_axis_tlast               (tx_tlast[0]),
        .tx_axis_tuser               (1'b0),
        .tx_ovfout                   (),
        .tx_unfout                   (),
        .tx_preamblein               (56'h55555555555555),
        .rx_preambleout              (),
        .rx_otn_bip8_0(), .rx_otn_bip8_1(), .rx_otn_bip8_2(), .rx_otn_bip8_3(), .rx_otn_bip8_4(),
        .rx_otn_data_0(), .rx_otn_data_1(), .rx_otn_data_2(), .rx_otn_data_3(), .rx_otn_data_4(),
        .rx_otn_ena(), .rx_otn_lane0(), .rx_otn_vlmarker(),
        .stat_rx_aligned             (cmac_stat_rx_aligned[0]),
        .stat_rx_aligned_err(), .stat_rx_bad_code(), .stat_rx_bad_fcs(),
        .stat_rx_bad_preamble(), .stat_rx_bad_sfd(),
        .stat_rx_bip_err_0(), .stat_rx_bip_err_1(), .stat_rx_bip_err_2(), .stat_rx_bip_err_3(),
        .stat_rx_bip_err_4(), .stat_rx_bip_err_5(), .stat_rx_bip_err_6(), .stat_rx_bip_err_7(),
        .stat_rx_bip_err_8(), .stat_rx_bip_err_9(), .stat_rx_bip_err_10(), .stat_rx_bip_err_11(),
        .stat_rx_bip_err_12(), .stat_rx_bip_err_13(), .stat_rx_bip_err_14(), .stat_rx_bip_err_15(),
        .stat_rx_bip_err_16(), .stat_rx_bip_err_17(), .stat_rx_bip_err_18(), .stat_rx_bip_err_19(),
        .stat_rx_block_lock(), .stat_rx_broadcast(), .stat_rx_fragment(),
        .stat_rx_framing_err_0(), .stat_rx_framing_err_1(), .stat_rx_framing_err_2(), .stat_rx_framing_err_3(),
        .stat_rx_framing_err_4(), .stat_rx_framing_err_5(), .stat_rx_framing_err_6(), .stat_rx_framing_err_7(),
        .stat_rx_framing_err_8(), .stat_rx_framing_err_9(), .stat_rx_framing_err_10(), .stat_rx_framing_err_11(),
        .stat_rx_framing_err_12(), .stat_rx_framing_err_13(), .stat_rx_framing_err_14(), .stat_rx_framing_err_15(),
        .stat_rx_framing_err_16(), .stat_rx_framing_err_17(), .stat_rx_framing_err_18(), .stat_rx_framing_err_19(),
        .stat_rx_framing_err_valid_0(), .stat_rx_framing_err_valid_1(), .stat_rx_framing_err_valid_2(), .stat_rx_framing_err_valid_3(),
        .stat_rx_framing_err_valid_4(), .stat_rx_framing_err_valid_5(), .stat_rx_framing_err_valid_6(), .stat_rx_framing_err_valid_7(),
        .stat_rx_framing_err_valid_8(), .stat_rx_framing_err_valid_9(), .stat_rx_framing_err_valid_10(), .stat_rx_framing_err_valid_11(),
        .stat_rx_framing_err_valid_12(), .stat_rx_framing_err_valid_13(), .stat_rx_framing_err_valid_14(), .stat_rx_framing_err_valid_15(),
        .stat_rx_framing_err_valid_16(), .stat_rx_framing_err_valid_17(), .stat_rx_framing_err_valid_18(), .stat_rx_framing_err_valid_19(),
        .stat_rx_got_signal_os(), .stat_rx_hi_ber(), .stat_rx_inrangeerr(),
        .stat_rx_internal_local_fault(), .stat_rx_jabber(), .stat_rx_local_fault(),
        .stat_rx_mf_err(), .stat_rx_mf_len_err(), .stat_rx_mf_repeat_err(), .stat_rx_misaligned(),
        .stat_rx_multicast(), .stat_rx_oversize(),
        .stat_rx_packet_1024_1518_bytes(), .stat_rx_packet_128_255_bytes(), .stat_rx_packet_1519_1522_bytes(),
        .stat_rx_packet_1523_1548_bytes(), .stat_rx_packet_1549_2047_bytes(), .stat_rx_packet_2048_4095_bytes(),
        .stat_rx_packet_256_511_bytes(), .stat_rx_packet_4096_8191_bytes(), .stat_rx_packet_512_1023_bytes(),
        .stat_rx_packet_64_bytes(), .stat_rx_packet_65_127_bytes(), .stat_rx_packet_8192_9215_bytes(),
        .stat_rx_packet_bad_fcs(cmac_stat_rx_bad_fcs[0]), .stat_rx_packet_large(), .stat_rx_packet_small(),
        .stat_rx_received_local_fault(), .stat_rx_remote_fault(),
        .stat_rx_status              (cmac_stat_rx_status[0]),
        .stat_rx_stomped_fcs(), .stat_rx_synced(), .stat_rx_synced_err(),
        .stat_rx_test_pattern_mismatch(), .stat_rx_toolong(), .stat_rx_total_bytes(),
        .stat_rx_total_good_bytes(), .stat_rx_total_good_packets(), .stat_rx_total_packets(),
        .stat_rx_truncated(), .stat_rx_undersize(), .stat_rx_unicast(), .stat_rx_vlan(),
        .stat_rx_pcsl_demuxed(), .stat_rx_pcsl_number_0(), .stat_rx_pcsl_number_1(),
        .stat_rx_pcsl_number_2(), .stat_rx_pcsl_number_3(), .stat_rx_pcsl_number_4(),
        .stat_rx_pcsl_number_5(), .stat_rx_pcsl_number_6(), .stat_rx_pcsl_number_7(),
        .stat_rx_pcsl_number_8(), .stat_rx_pcsl_number_9(), .stat_rx_pcsl_number_10(),
        .stat_rx_pcsl_number_11(), .stat_rx_pcsl_number_12(), .stat_rx_pcsl_number_13(),
        .stat_rx_pcsl_number_14(), .stat_rx_pcsl_number_15(), .stat_rx_pcsl_number_16(),
        .stat_rx_pcsl_number_17(), .stat_rx_pcsl_number_18(), .stat_rx_pcsl_number_19(),
        .stat_tx_bad_fcs(), .stat_tx_broadcast(), .stat_tx_frame_error(), .stat_tx_local_fault(),
        .stat_tx_multicast(), .stat_tx_packet_1024_1518_bytes(), .stat_tx_packet_128_255_bytes(),
        .stat_tx_packet_1519_1522_bytes(), .stat_tx_packet_1523_1548_bytes(),
        .stat_tx_packet_1549_2047_bytes(), .stat_tx_packet_2048_4095_bytes(),
        .stat_tx_packet_256_511_bytes(), .stat_tx_packet_4096_8191_bytes(),
        .stat_tx_packet_512_1023_bytes(), .stat_tx_packet_64_bytes(), .stat_tx_packet_65_127_bytes(),
        .stat_tx_packet_8192_9215_bytes(), .stat_tx_packet_large(), .stat_tx_packet_small(),
        .stat_tx_total_bytes(),
        .stat_tx_total_good_bytes(), .stat_tx_total_good_packets(), .stat_tx_total_packets(),
        .stat_tx_unicast(), .stat_tx_vlan(),
        .rx_clk                      (cmac_rx_clk[0]),
        .ctl_rx_enable               (ctl_rx_enable[0]),
        .ctl_rx_force_resync         (1'b0), .ctl_rx_test_pattern(1'b0),
        .ctl_tx_enable               (ctl_tx_enable[0]),
        .ctl_tx_send_idle            (ctl_tx_send_idle[0]),
        .ctl_tx_send_rfi             (ctl_tx_send_rfi[0]),
        .ctl_tx_send_lfi             (ctl_tx_send_lfi[0]),
        .ctl_tx_test_pattern         (1'b0),
        .core_rx_reset(1'b0), .core_tx_reset(1'b0), .core_drp_reset(1'b0),
        .drp_clk(sys_clk), .drp_addr(10'h0), .drp_di(16'h0), .drp_en(1'b0), .drp_do(), .drp_rdy(), .drp_we(1'b0),
        .usr_rx_reset(cmac_rx_rst[0]), .usr_tx_reset(cmac_tx_rst[0]),
        .gtwiz_reset_tx_datapath(1'b0), .gtwiz_reset_rx_datapath(1'b0),
        .sys_reset(~sys_rst_n), .init_clk(sys_clk)
    );

    cmac_usplus_1 u_cmac1 (
        .gt_txp_out                  (qsfp1_tx_p),
        .gt_txn_out                  (qsfp1_tx_n),
        .gt_rxp_in                   (qsfp1_rx_p),
        .gt_rxn_in                   (qsfp1_rx_n),
        .gt_ref_clk_p                (QSFPDD1_REFCLK_P),
        .gt_ref_clk_n                (QSFPDD1_REFCLK_N),
        .gt_ref_clk_out              (),
        .gt_rxrecclkout              (),
        .gt_powergoodout             (),
        .gt_txusrclk2                (cmac_tx_clk[1]),
        .gt_rxusrclk2                (cmac_rx_clk[1]),
        .gt_loopback_in              ({4{gt_loopback[1]}}),
        .rx_axis_tdata               (rx_tdata[1]),
        .rx_axis_tkeep               (rx_tkeep[1]),
        .rx_axis_tvalid              (rx_tvalid[1]),
        .rx_axis_tlast               (rx_tlast[1]),
        .rx_axis_tuser               (),
        .tx_axis_tdata               (tx_tdata[1]),
        .tx_axis_tkeep               (tx_tkeep[1]),
        .tx_axis_tvalid              (tx_tvalid[1]),
        .tx_axis_tready              (tx_tready[1]),
        .tx_axis_tlast               (tx_tlast[1]),
        .tx_axis_tuser               (1'b0),
        .tx_ovfout                   (), .tx_unfout(),
        .tx_preamblein               (56'h55555555555555),
        .rx_preambleout              (),
        .rx_otn_bip8_0(), .rx_otn_bip8_1(), .rx_otn_bip8_2(), .rx_otn_bip8_3(), .rx_otn_bip8_4(),
        .rx_otn_data_0(), .rx_otn_data_1(), .rx_otn_data_2(), .rx_otn_data_3(), .rx_otn_data_4(),
        .rx_otn_ena(), .rx_otn_lane0(), .rx_otn_vlmarker(),
        .stat_rx_aligned             (cmac_stat_rx_aligned[1]),
        .stat_rx_aligned_err(), .stat_rx_bad_code(), .stat_rx_bad_fcs(),
        .stat_rx_bad_preamble(), .stat_rx_bad_sfd(),
        .stat_rx_bip_err_0(), .stat_rx_bip_err_1(), .stat_rx_bip_err_2(), .stat_rx_bip_err_3(),
        .stat_rx_bip_err_4(), .stat_rx_bip_err_5(), .stat_rx_bip_err_6(), .stat_rx_bip_err_7(),
        .stat_rx_bip_err_8(), .stat_rx_bip_err_9(), .stat_rx_bip_err_10(), .stat_rx_bip_err_11(),
        .stat_rx_bip_err_12(), .stat_rx_bip_err_13(), .stat_rx_bip_err_14(), .stat_rx_bip_err_15(),
        .stat_rx_bip_err_16(), .stat_rx_bip_err_17(), .stat_rx_bip_err_18(), .stat_rx_bip_err_19(),
        .stat_rx_block_lock(), .stat_rx_broadcast(), .stat_rx_fragment(),
        .stat_rx_framing_err_0(), .stat_rx_framing_err_1(), .stat_rx_framing_err_2(), .stat_rx_framing_err_3(),
        .stat_rx_framing_err_4(), .stat_rx_framing_err_5(), .stat_rx_framing_err_6(), .stat_rx_framing_err_7(),
        .stat_rx_framing_err_8(), .stat_rx_framing_err_9(), .stat_rx_framing_err_10(), .stat_rx_framing_err_11(),
        .stat_rx_framing_err_12(), .stat_rx_framing_err_13(), .stat_rx_framing_err_14(), .stat_rx_framing_err_15(),
        .stat_rx_framing_err_16(), .stat_rx_framing_err_17(), .stat_rx_framing_err_18(), .stat_rx_framing_err_19(),
        .stat_rx_framing_err_valid_0(), .stat_rx_framing_err_valid_1(), .stat_rx_framing_err_valid_2(), .stat_rx_framing_err_valid_3(),
        .stat_rx_framing_err_valid_4(), .stat_rx_framing_err_valid_5(), .stat_rx_framing_err_valid_6(), .stat_rx_framing_err_valid_7(),
        .stat_rx_framing_err_valid_8(), .stat_rx_framing_err_valid_9(), .stat_rx_framing_err_valid_10(), .stat_rx_framing_err_valid_11(),
        .stat_rx_framing_err_valid_12(), .stat_rx_framing_err_valid_13(), .stat_rx_framing_err_valid_14(), .stat_rx_framing_err_valid_15(),
        .stat_rx_framing_err_valid_16(), .stat_rx_framing_err_valid_17(), .stat_rx_framing_err_valid_18(), .stat_rx_framing_err_valid_19(),
        .stat_rx_got_signal_os(), .stat_rx_hi_ber(), .stat_rx_inrangeerr(),
        .stat_rx_internal_local_fault(), .stat_rx_jabber(), .stat_rx_local_fault(),
        .stat_rx_mf_err(), .stat_rx_mf_len_err(), .stat_rx_mf_repeat_err(), .stat_rx_misaligned(),
        .stat_rx_multicast(), .stat_rx_oversize(),
        .stat_rx_packet_1024_1518_bytes(), .stat_rx_packet_128_255_bytes(), .stat_rx_packet_1519_1522_bytes(),
        .stat_rx_packet_1523_1548_bytes(), .stat_rx_packet_1549_2047_bytes(), .stat_rx_packet_2048_4095_bytes(),
        .stat_rx_packet_256_511_bytes(), .stat_rx_packet_4096_8191_bytes(), .stat_rx_packet_512_1023_bytes(),
        .stat_rx_packet_64_bytes(), .stat_rx_packet_65_127_bytes(), .stat_rx_packet_8192_9215_bytes(),
        .stat_rx_packet_bad_fcs(cmac_stat_rx_bad_fcs[1]), .stat_rx_packet_large(), .stat_rx_packet_small(),
        .stat_rx_received_local_fault(), .stat_rx_remote_fault(),
        .stat_rx_status              (cmac_stat_rx_status[1]),
        .stat_rx_stomped_fcs(), .stat_rx_synced(), .stat_rx_synced_err(),
        .stat_rx_test_pattern_mismatch(), .stat_rx_toolong(), .stat_rx_total_bytes(),
        .stat_rx_total_good_bytes(), .stat_rx_total_good_packets(), .stat_rx_total_packets(),
        .stat_rx_truncated(), .stat_rx_undersize(), .stat_rx_unicast(), .stat_rx_vlan(),
        .stat_rx_pcsl_demuxed(), .stat_rx_pcsl_number_0(), .stat_rx_pcsl_number_1(),
        .stat_rx_pcsl_number_2(), .stat_rx_pcsl_number_3(), .stat_rx_pcsl_number_4(),
        .stat_rx_pcsl_number_5(), .stat_rx_pcsl_number_6(), .stat_rx_pcsl_number_7(),
        .stat_rx_pcsl_number_8(), .stat_rx_pcsl_number_9(), .stat_rx_pcsl_number_10(),
        .stat_rx_pcsl_number_11(), .stat_rx_pcsl_number_12(), .stat_rx_pcsl_number_13(),
        .stat_rx_pcsl_number_14(), .stat_rx_pcsl_number_15(), .stat_rx_pcsl_number_16(),
        .stat_rx_pcsl_number_17(), .stat_rx_pcsl_number_18(), .stat_rx_pcsl_number_19(),
        .stat_tx_bad_fcs(), .stat_tx_broadcast(), .stat_tx_frame_error(), .stat_tx_local_fault(),
        .stat_tx_multicast(), .stat_tx_packet_1024_1518_bytes(), .stat_tx_packet_128_255_bytes(),
        .stat_tx_packet_1519_1522_bytes(), .stat_tx_packet_1523_1548_bytes(),
        .stat_tx_packet_1549_2047_bytes(), .stat_tx_packet_2048_4095_bytes(),
        .stat_tx_packet_256_511_bytes(), .stat_tx_packet_4096_8191_bytes(),
        .stat_tx_packet_512_1023_bytes(), .stat_tx_packet_64_bytes(), .stat_tx_packet_65_127_bytes(),
        .stat_tx_packet_8192_9215_bytes(), .stat_tx_packet_large(), .stat_tx_packet_small(),
        .stat_tx_total_bytes(),
        .stat_tx_total_good_bytes(), .stat_tx_total_good_packets(), .stat_tx_total_packets(),
        .stat_tx_unicast(), .stat_tx_vlan(),
        .rx_clk                      (cmac_rx_clk[1]),
        .ctl_rx_enable               (ctl_rx_enable[1]),
        .ctl_rx_force_resync         (1'b0), .ctl_rx_test_pattern(1'b0),
        .ctl_tx_enable               (ctl_tx_enable[1]),
        .ctl_tx_send_idle            (ctl_tx_send_idle[1]),
        .ctl_tx_send_rfi             (ctl_tx_send_rfi[1]),
        .ctl_tx_send_lfi             (ctl_tx_send_lfi[1]),
        .ctl_tx_test_pattern         (1'b0),
        .core_rx_reset(1'b0), .core_tx_reset(1'b0), .core_drp_reset(1'b0),
        .drp_clk(sys_clk), .drp_addr(10'h0), .drp_di(16'h0), .drp_en(1'b0), .drp_do(), .drp_rdy(), .drp_we(1'b0),
        .usr_rx_reset(cmac_rx_rst[1]), .usr_tx_reset(cmac_tx_rst[1]),
        .gtwiz_reset_tx_datapath(1'b0), .gtwiz_reset_rx_datapath(1'b0),
        .sys_reset(~sys_rst_n), .init_clk(sys_clk)
    );

    cmac_usplus_2 u_cmac2 (
        .gt_txp_out                  (qsfp2_tx_p),
        .gt_txn_out                  (qsfp2_tx_n),
        .gt_rxp_in                   (qsfp2_rx_p),
        .gt_rxn_in                   (qsfp2_rx_n),
        .gt_ref_clk_p                (QSFPDD2_REFCLK_P),
        .gt_ref_clk_n                (QSFPDD2_REFCLK_N),
        .gt_ref_clk_out              (),
        .gt_rxrecclkout              (),
        .gt_powergoodout             (),
        .gt_txusrclk2                (cmac_tx_clk[2]),
        .gt_rxusrclk2                (cmac_rx_clk[2]),
        .gt_loopback_in              ({4{gt_loopback[2]}}),
        .rx_axis_tdata               (rx_tdata[2]),
        .rx_axis_tkeep               (rx_tkeep[2]),
        .rx_axis_tvalid              (rx_tvalid[2]),
        .rx_axis_tlast               (rx_tlast[2]),
        .rx_axis_tuser               (),
        .tx_axis_tdata               (tx_tdata[2]),
        .tx_axis_tkeep               (tx_tkeep[2]),
        .tx_axis_tvalid              (tx_tvalid[2]),
        .tx_axis_tready              (tx_tready[2]),
        .tx_axis_tlast               (tx_tlast[2]),
        .tx_axis_tuser               (1'b0),
        .tx_ovfout                   (), .tx_unfout(),
        .tx_preamblein               (56'h55555555555555),
        .rx_preambleout              (),
        .rx_otn_bip8_0(), .rx_otn_bip8_1(), .rx_otn_bip8_2(), .rx_otn_bip8_3(), .rx_otn_bip8_4(),
        .rx_otn_data_0(), .rx_otn_data_1(), .rx_otn_data_2(), .rx_otn_data_3(), .rx_otn_data_4(),
        .rx_otn_ena(), .rx_otn_lane0(), .rx_otn_vlmarker(),
        .stat_rx_aligned             (cmac_stat_rx_aligned[2]),
        .stat_rx_aligned_err(), .stat_rx_bad_code(), .stat_rx_bad_fcs(),
        .stat_rx_bad_preamble(), .stat_rx_bad_sfd(),
        .stat_rx_bip_err_0(), .stat_rx_bip_err_1(), .stat_rx_bip_err_2(), .stat_rx_bip_err_3(),
        .stat_rx_bip_err_4(), .stat_rx_bip_err_5(), .stat_rx_bip_err_6(), .stat_rx_bip_err_7(),
        .stat_rx_bip_err_8(), .stat_rx_bip_err_9(), .stat_rx_bip_err_10(), .stat_rx_bip_err_11(),
        .stat_rx_bip_err_12(), .stat_rx_bip_err_13(), .stat_rx_bip_err_14(), .stat_rx_bip_err_15(),
        .stat_rx_bip_err_16(), .stat_rx_bip_err_17(), .stat_rx_bip_err_18(), .stat_rx_bip_err_19(),
        .stat_rx_block_lock(), .stat_rx_broadcast(), .stat_rx_fragment(),
        .stat_rx_framing_err_0(), .stat_rx_framing_err_1(), .stat_rx_framing_err_2(), .stat_rx_framing_err_3(),
        .stat_rx_framing_err_4(), .stat_rx_framing_err_5(), .stat_rx_framing_err_6(), .stat_rx_framing_err_7(),
        .stat_rx_framing_err_8(), .stat_rx_framing_err_9(), .stat_rx_framing_err_10(), .stat_rx_framing_err_11(),
        .stat_rx_framing_err_12(), .stat_rx_framing_err_13(), .stat_rx_framing_err_14(), .stat_rx_framing_err_15(),
        .stat_rx_framing_err_16(), .stat_rx_framing_err_17(), .stat_rx_framing_err_18(), .stat_rx_framing_err_19(),
        .stat_rx_framing_err_valid_0(), .stat_rx_framing_err_valid_1(), .stat_rx_framing_err_valid_2(), .stat_rx_framing_err_valid_3(),
        .stat_rx_framing_err_valid_4(), .stat_rx_framing_err_valid_5(), .stat_rx_framing_err_valid_6(), .stat_rx_framing_err_valid_7(),
        .stat_rx_framing_err_valid_8(), .stat_rx_framing_err_valid_9(), .stat_rx_framing_err_valid_10(), .stat_rx_framing_err_valid_11(),
        .stat_rx_framing_err_valid_12(), .stat_rx_framing_err_valid_13(), .stat_rx_framing_err_valid_14(), .stat_rx_framing_err_valid_15(),
        .stat_rx_framing_err_valid_16(), .stat_rx_framing_err_valid_17(), .stat_rx_framing_err_valid_18(), .stat_rx_framing_err_valid_19(),
        .stat_rx_got_signal_os(), .stat_rx_hi_ber(), .stat_rx_inrangeerr(),
        .stat_rx_internal_local_fault(), .stat_rx_jabber(), .stat_rx_local_fault(),
        .stat_rx_mf_err(), .stat_rx_mf_len_err(), .stat_rx_mf_repeat_err(), .stat_rx_misaligned(),
        .stat_rx_multicast(), .stat_rx_oversize(),
        .stat_rx_packet_1024_1518_bytes(), .stat_rx_packet_128_255_bytes(), .stat_rx_packet_1519_1522_bytes(),
        .stat_rx_packet_1523_1548_bytes(), .stat_rx_packet_1549_2047_bytes(), .stat_rx_packet_2048_4095_bytes(),
        .stat_rx_packet_256_511_bytes(), .stat_rx_packet_4096_8191_bytes(), .stat_rx_packet_512_1023_bytes(),
        .stat_rx_packet_64_bytes(), .stat_rx_packet_65_127_bytes(), .stat_rx_packet_8192_9215_bytes(),
        .stat_rx_packet_bad_fcs(cmac_stat_rx_bad_fcs[2]), .stat_rx_packet_large(), .stat_rx_packet_small(),
        .stat_rx_received_local_fault(), .stat_rx_remote_fault(),
        .stat_rx_status(cmac_stat_rx_status[2]),
        .stat_rx_stomped_fcs(), .stat_rx_synced(), .stat_rx_synced_err(),
        .stat_rx_test_pattern_mismatch(), .stat_rx_toolong(), .stat_rx_total_bytes(),
        .stat_rx_total_good_bytes(), .stat_rx_total_good_packets(), .stat_rx_total_packets(),
        .stat_rx_truncated(), .stat_rx_undersize(), .stat_rx_unicast(), .stat_rx_vlan(),
        .stat_rx_pcsl_demuxed(), .stat_rx_pcsl_number_0(), .stat_rx_pcsl_number_1(),
        .stat_rx_pcsl_number_2(), .stat_rx_pcsl_number_3(), .stat_rx_pcsl_number_4(),
        .stat_rx_pcsl_number_5(), .stat_rx_pcsl_number_6(), .stat_rx_pcsl_number_7(),
        .stat_rx_pcsl_number_8(), .stat_rx_pcsl_number_9(), .stat_rx_pcsl_number_10(),
        .stat_rx_pcsl_number_11(), .stat_rx_pcsl_number_12(), .stat_rx_pcsl_number_13(),
        .stat_rx_pcsl_number_14(), .stat_rx_pcsl_number_15(), .stat_rx_pcsl_number_16(),
        .stat_rx_pcsl_number_17(), .stat_rx_pcsl_number_18(), .stat_rx_pcsl_number_19(),
        .stat_tx_bad_fcs(), .stat_tx_broadcast(), .stat_tx_frame_error(), .stat_tx_local_fault(),
        .stat_tx_multicast(), .stat_tx_packet_1024_1518_bytes(), .stat_tx_packet_128_255_bytes(),
        .stat_tx_packet_1519_1522_bytes(), .stat_tx_packet_1523_1548_bytes(),
        .stat_tx_packet_1549_2047_bytes(), .stat_tx_packet_2048_4095_bytes(),
        .stat_tx_packet_256_511_bytes(), .stat_tx_packet_4096_8191_bytes(),
        .stat_tx_packet_512_1023_bytes(), .stat_tx_packet_64_bytes(), .stat_tx_packet_65_127_bytes(),
        .stat_tx_packet_8192_9215_bytes(), .stat_tx_packet_large(), .stat_tx_packet_small(),
        .stat_tx_total_bytes(),
        .stat_tx_total_good_bytes(), .stat_tx_total_good_packets(), .stat_tx_total_packets(),
        .stat_tx_unicast(), .stat_tx_vlan(),
        .rx_clk(cmac_rx_clk[2]),
        .ctl_rx_enable(ctl_rx_enable[2]), .ctl_rx_force_resync(1'b0), .ctl_rx_test_pattern(1'b0),
        .ctl_tx_enable(ctl_tx_enable[2]), .ctl_tx_send_idle(ctl_tx_send_idle[2]),
        .ctl_tx_send_rfi(ctl_tx_send_rfi[2]), .ctl_tx_send_lfi(ctl_tx_send_lfi[2]), .ctl_tx_test_pattern(1'b0),
        .core_rx_reset(1'b0), .core_tx_reset(1'b0), .core_drp_reset(1'b0),
        .drp_clk(sys_clk), .drp_addr(10'h0), .drp_di(16'h0), .drp_en(1'b0), .drp_do(), .drp_rdy(), .drp_we(1'b0),
        .usr_rx_reset(cmac_rx_rst[2]), .usr_tx_reset(cmac_tx_rst[2]),
        .gtwiz_reset_tx_datapath(1'b0), .gtwiz_reset_rx_datapath(1'b0),
        .sys_reset(~sys_rst_n), .init_clk(sys_clk)
    );

    cmac_usplus_3 u_cmac3 (
        .gt_txp_out                  (qsfp3_tx_p),
        .gt_txn_out                  (qsfp3_tx_n),
        .gt_rxp_in                   (qsfp3_rx_p),
        .gt_rxn_in                   (qsfp3_rx_n),
        .gt_ref_clk_p                (QSFPDD3_REFCLK_P),
        .gt_ref_clk_n                (QSFPDD3_REFCLK_N),
        .gt_ref_clk_out              (),
        .gt_rxrecclkout              (),
        .gt_powergoodout             (),
        .gt_txusrclk2                (cmac_tx_clk[3]),
        .gt_rxusrclk2                (cmac_rx_clk[3]),
        .gt_loopback_in              ({4{gt_loopback[3]}}),
        .rx_axis_tdata               (rx_tdata[3]),
        .rx_axis_tkeep               (rx_tkeep[3]),
        .rx_axis_tvalid              (rx_tvalid[3]),
        .rx_axis_tlast               (rx_tlast[3]),
        .rx_axis_tuser               (),
        .tx_axis_tdata               (tx_tdata[3]),
        .tx_axis_tkeep               (tx_tkeep[3]),
        .tx_axis_tvalid              (tx_tvalid[3]),
        .tx_axis_tready              (tx_tready[3]),
        .tx_axis_tlast               (tx_tlast[3]),
        .tx_axis_tuser               (1'b0),
        .tx_ovfout                   (), .tx_unfout(),
        .tx_preamblein               (56'h55555555555555),
        .rx_preambleout              (),
        .rx_otn_bip8_0(), .rx_otn_bip8_1(), .rx_otn_bip8_2(), .rx_otn_bip8_3(), .rx_otn_bip8_4(),
        .rx_otn_data_0(), .rx_otn_data_1(), .rx_otn_data_2(), .rx_otn_data_3(), .rx_otn_data_4(),
        .rx_otn_ena(), .rx_otn_lane0(), .rx_otn_vlmarker(),
        .stat_rx_aligned             (cmac_stat_rx_aligned[3]),
        .stat_rx_aligned_err(), .stat_rx_bad_code(), .stat_rx_bad_fcs(),
        .stat_rx_bad_preamble(), .stat_rx_bad_sfd(),
        .stat_rx_bip_err_0(), .stat_rx_bip_err_1(), .stat_rx_bip_err_2(), .stat_rx_bip_err_3(),
        .stat_rx_bip_err_4(), .stat_rx_bip_err_5(), .stat_rx_bip_err_6(), .stat_rx_bip_err_7(),
        .stat_rx_bip_err_8(), .stat_rx_bip_err_9(), .stat_rx_bip_err_10(), .stat_rx_bip_err_11(),
        .stat_rx_bip_err_12(), .stat_rx_bip_err_13(), .stat_rx_bip_err_14(), .stat_rx_bip_err_15(),
        .stat_rx_bip_err_16(), .stat_rx_bip_err_17(), .stat_rx_bip_err_18(), .stat_rx_bip_err_19(),
        .stat_rx_block_lock(), .stat_rx_broadcast(), .stat_rx_fragment(),
        .stat_rx_framing_err_0(), .stat_rx_framing_err_1(), .stat_rx_framing_err_2(), .stat_rx_framing_err_3(),
        .stat_rx_framing_err_4(), .stat_rx_framing_err_5(), .stat_rx_framing_err_6(), .stat_rx_framing_err_7(),
        .stat_rx_framing_err_8(), .stat_rx_framing_err_9(), .stat_rx_framing_err_10(), .stat_rx_framing_err_11(),
        .stat_rx_framing_err_12(), .stat_rx_framing_err_13(), .stat_rx_framing_err_14(), .stat_rx_framing_err_15(),
        .stat_rx_framing_err_16(), .stat_rx_framing_err_17(), .stat_rx_framing_err_18(), .stat_rx_framing_err_19(),
        .stat_rx_framing_err_valid_0(), .stat_rx_framing_err_valid_1(), .stat_rx_framing_err_valid_2(), .stat_rx_framing_err_valid_3(),
        .stat_rx_framing_err_valid_4(), .stat_rx_framing_err_valid_5(), .stat_rx_framing_err_valid_6(), .stat_rx_framing_err_valid_7(),
        .stat_rx_framing_err_valid_8(), .stat_rx_framing_err_valid_9(), .stat_rx_framing_err_valid_10(), .stat_rx_framing_err_valid_11(),
        .stat_rx_framing_err_valid_12(), .stat_rx_framing_err_valid_13(), .stat_rx_framing_err_valid_14(), .stat_rx_framing_err_valid_15(),
        .stat_rx_framing_err_valid_16(), .stat_rx_framing_err_valid_17(), .stat_rx_framing_err_valid_18(), .stat_rx_framing_err_valid_19(),
        .stat_rx_got_signal_os(), .stat_rx_hi_ber(), .stat_rx_inrangeerr(),
        .stat_rx_internal_local_fault(), .stat_rx_jabber(), .stat_rx_local_fault(),
        .stat_rx_mf_err(), .stat_rx_mf_len_err(), .stat_rx_mf_repeat_err(), .stat_rx_misaligned(),
        .stat_rx_multicast(), .stat_rx_oversize(),
        .stat_rx_packet_1024_1518_bytes(), .stat_rx_packet_128_255_bytes(), .stat_rx_packet_1519_1522_bytes(),
        .stat_rx_packet_1523_1548_bytes(), .stat_rx_packet_1549_2047_bytes(), .stat_rx_packet_2048_4095_bytes(),
        .stat_rx_packet_256_511_bytes(), .stat_rx_packet_4096_8191_bytes(), .stat_rx_packet_512_1023_bytes(),
        .stat_rx_packet_64_bytes(), .stat_rx_packet_65_127_bytes(), .stat_rx_packet_8192_9215_bytes(),
        .stat_rx_packet_bad_fcs(cmac_stat_rx_bad_fcs[3]), .stat_rx_packet_large(), .stat_rx_packet_small(),
        .stat_rx_received_local_fault(), .stat_rx_remote_fault(),
        .stat_rx_status(cmac_stat_rx_status[3]),
        .stat_rx_stomped_fcs(), .stat_rx_synced(), .stat_rx_synced_err(),
        .stat_rx_test_pattern_mismatch(), .stat_rx_toolong(), .stat_rx_total_bytes(),
        .stat_rx_total_good_bytes(), .stat_rx_total_good_packets(), .stat_rx_total_packets(),
        .stat_rx_truncated(), .stat_rx_undersize(), .stat_rx_unicast(), .stat_rx_vlan(),
        .stat_rx_pcsl_demuxed(), .stat_rx_pcsl_number_0(), .stat_rx_pcsl_number_1(),
        .stat_rx_pcsl_number_2(), .stat_rx_pcsl_number_3(), .stat_rx_pcsl_number_4(),
        .stat_rx_pcsl_number_5(), .stat_rx_pcsl_number_6(), .stat_rx_pcsl_number_7(),
        .stat_rx_pcsl_number_8(), .stat_rx_pcsl_number_9(), .stat_rx_pcsl_number_10(),
        .stat_rx_pcsl_number_11(), .stat_rx_pcsl_number_12(), .stat_rx_pcsl_number_13(),
        .stat_rx_pcsl_number_14(), .stat_rx_pcsl_number_15(), .stat_rx_pcsl_number_16(),
        .stat_rx_pcsl_number_17(), .stat_rx_pcsl_number_18(), .stat_rx_pcsl_number_19(),
        .stat_tx_bad_fcs(), .stat_tx_broadcast(), .stat_tx_frame_error(), .stat_tx_local_fault(),
        .stat_tx_multicast(), .stat_tx_packet_1024_1518_bytes(), .stat_tx_packet_128_255_bytes(),
        .stat_tx_packet_1519_1522_bytes(), .stat_tx_packet_1523_1548_bytes(),
        .stat_tx_packet_1549_2047_bytes(), .stat_tx_packet_2048_4095_bytes(),
        .stat_tx_packet_256_511_bytes(), .stat_tx_packet_4096_8191_bytes(),
        .stat_tx_packet_512_1023_bytes(), .stat_tx_packet_64_bytes(), .stat_tx_packet_65_127_bytes(),
        .stat_tx_packet_8192_9215_bytes(), .stat_tx_packet_large(), .stat_tx_packet_small(),
        .stat_tx_total_bytes(),
        .stat_tx_total_good_bytes(), .stat_tx_total_good_packets(), .stat_tx_total_packets(),
        .stat_tx_unicast(), .stat_tx_vlan(),
        .rx_clk(cmac_rx_clk[3]),
        .ctl_rx_enable(ctl_rx_enable[3]), .ctl_rx_force_resync(1'b0), .ctl_rx_test_pattern(1'b0),
        .ctl_tx_enable(ctl_tx_enable[3]), .ctl_tx_send_idle(ctl_tx_send_idle[3]),
        .ctl_tx_send_rfi(ctl_tx_send_rfi[3]), .ctl_tx_send_lfi(ctl_tx_send_lfi[3]), .ctl_tx_test_pattern(1'b0),
        .core_rx_reset(1'b0), .core_tx_reset(1'b0), .core_drp_reset(1'b0),
        .drp_clk(sys_clk), .drp_addr(10'h0), .drp_di(16'h0), .drp_en(1'b0), .drp_do(), .drp_rdy(), .drp_we(1'b0),
        .usr_rx_reset(cmac_rx_rst[3]), .usr_tx_reset(cmac_tx_rst[3]),
        .gtwiz_reset_tx_datapath(1'b0), .gtwiz_reset_rx_datapath(1'b0),
        .sys_reset(~sys_rst_n), .init_clk(sys_clk)
    );

    // ========================================================================
    // ILA Debug: REMOVED for timing convergence
    // Original probe set sampled port-0 datapath + CMAC link state on
    // switch_clk (= txoutclk_out[0]). probe11/12 came from rxoutclk domain,
    // producing the rxoutclk_out[0] -> txoutclk_out[0] WNS = -0.778 ns path.
    // ILA was also pulled to LAGUNA across SLR, dominating txoutclk_out[0]
    // intra-clock violations. Re-instantiate only if debug is required again,
    // and then synchronize RX-domain probes to switch_clk via sync_signal
    // before connecting to the ILA.
    // ========================================================================
    // ila_debug u_ila (
    //     .clk     (switch_clk),
    //     .probe0  (dp_s_tdata[0]),
    //     .probe1  (dp_s_tkeep[0]),
    //     .probe2  (dp_s_tvalid[0]),
    //     .probe3  (dp_s_tready[0]),
    //     .probe4  (dp_s_tlast[0]),
    //     .probe5  (dp_m_tdata[0]),
    //     .probe6  (dp_m_tkeep[0]),
    //     .probe7  (dp_m_tvalid[0]),
    //     .probe8  (dp_m_tlast[0]),
    //     .probe9  (ctl_tx_enable[0]),
    //     .probe10 (ctl_rx_enable[0]),
    //     .probe11 (cmac_stat_rx_aligned[0]),
    //     .probe12 (cmac_stat_rx_status[0]),
    //     .probe13 (ingress_overflow)
    // );

endmodule
