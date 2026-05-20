`timescale 1ns / 1ps
//
// nf_datapath_4port.v
//
// 4-port adaptation of NetFPGA-PLUS reference_switch datapath.
// Pipeline:  input_arbiter (NUM_QUEUES=4)
//         -> switch_output_port_lookup (NUM_OUTPUT_QUEUES=8, low-4-bit one-hot)
//         -> output_queues  (NUM_QUEUES=4)
//
// AXI-Lite control plane (3 slaves, kept to match reference_switch convention):
//   S0_AXI -> input_arbiter regs
//   S1_AXI -> output_port_lookup regs (CAM table)
//   S2_AXI -> output_queues regs
// In the XPU-213 port these are typically tied off (see top-level wiring).
//
// Port one-hot encoding (TUSER[31:24]=dst, TUSER[23:16]=src):
//   P0 = 8'h01   P1 = 8'h02   P2 = 8'h04   P3 = 8'h08
//

module nf_datapath_4port #(
    parameter C_S_AXI_DATA_WIDTH    = 32,
    parameter C_S_AXI_ADDR_WIDTH    = 32,
    parameter C_BASEADDR            = 32'h00000000,

    parameter C_M_AXIS_DATA_WIDTH   = 512,
    parameter C_S_AXIS_DATA_WIDTH   = 512,
    parameter C_M_AXIS_TUSER_WIDTH  = 128,
    parameter C_S_AXIS_TUSER_WIDTH  = 128,
    parameter NUM_QUEUES            = 4
)(
    // Datapath clock / reset (low-active resetn)
    input                                     axis_aclk,
    input                                     axis_resetn,
    // Register clock / reset
    input                                     axi_aclk,
    input                                     axi_resetn,
    // Allreduce clock / reset (250 MHz)
    input                                     allreduce_clk,
    input                                     allreduce_rst_n,

    // ---------------- AXI-Lite slave 0 (input arbiter) ----------------
    input  [C_S_AXI_ADDR_WIDTH-1 : 0]         S0_AXI_AWADDR,
    input                                     S0_AXI_AWVALID,
    input  [C_S_AXI_DATA_WIDTH-1 : 0]         S0_AXI_WDATA,
    input  [C_S_AXI_DATA_WIDTH/8-1 : 0]       S0_AXI_WSTRB,
    input                                     S0_AXI_WVALID,
    input                                     S0_AXI_BREADY,
    input  [C_S_AXI_ADDR_WIDTH-1 : 0]         S0_AXI_ARADDR,
    input                                     S0_AXI_ARVALID,
    input                                     S0_AXI_RREADY,
    output                                    S0_AXI_ARREADY,
    output [C_S_AXI_DATA_WIDTH-1 : 0]         S0_AXI_RDATA,
    output [1 : 0]                            S0_AXI_RRESP,
    output                                    S0_AXI_RVALID,
    output                                    S0_AXI_WREADY,
    output [1 : 0]                            S0_AXI_BRESP,
    output                                    S0_AXI_BVALID,
    output                                    S0_AXI_AWREADY,

    // ---------------- AXI-Lite slave 1 (output_port_lookup) ----------------
    input  [C_S_AXI_ADDR_WIDTH-1 : 0]         S1_AXI_AWADDR,
    input                                     S1_AXI_AWVALID,
    input  [C_S_AXI_DATA_WIDTH-1 : 0]         S1_AXI_WDATA,
    input  [C_S_AXI_DATA_WIDTH/8-1 : 0]       S1_AXI_WSTRB,
    input                                     S1_AXI_WVALID,
    input                                     S1_AXI_BREADY,
    input  [C_S_AXI_ADDR_WIDTH-1 : 0]         S1_AXI_ARADDR,
    input                                     S1_AXI_ARVALID,
    input                                     S1_AXI_RREADY,
    output                                    S1_AXI_ARREADY,
    output [C_S_AXI_DATA_WIDTH-1 : 0]         S1_AXI_RDATA,
    output [1 : 0]                            S1_AXI_RRESP,
    output                                    S1_AXI_RVALID,
    output                                    S1_AXI_WREADY,
    output [1 : 0]                            S1_AXI_BRESP,
    output                                    S1_AXI_BVALID,
    output                                    S1_AXI_AWREADY,

    // ---------------- AXI-Lite slave 2 (output_queues) ----------------
    input  [C_S_AXI_ADDR_WIDTH-1 : 0]         S2_AXI_AWADDR,
    input                                     S2_AXI_AWVALID,
    input  [C_S_AXI_DATA_WIDTH-1 : 0]         S2_AXI_WDATA,
    input  [C_S_AXI_DATA_WIDTH/8-1 : 0]       S2_AXI_WSTRB,
    input                                     S2_AXI_WVALID,
    input                                     S2_AXI_BREADY,
    input  [C_S_AXI_ADDR_WIDTH-1 : 0]         S2_AXI_ARADDR,
    input                                     S2_AXI_ARVALID,
    input                                     S2_AXI_RREADY,
    output                                    S2_AXI_ARREADY,
    output [C_S_AXI_DATA_WIDTH-1 : 0]         S2_AXI_RDATA,
    output [1 : 0]                            S2_AXI_RRESP,
    output                                    S2_AXI_RVALID,
    output                                    S2_AXI_WREADY,
    output [1 : 0]                            S2_AXI_BRESP,
    output                                    S2_AXI_BVALID,
    output                                    S2_AXI_AWREADY,

    // ---------------- Slave AXIS (4 ingress from RX adapters) ----------------
    input  [C_S_AXIS_DATA_WIDTH - 1:0]        s_axis_0_tdata,
    input  [(C_S_AXIS_DATA_WIDTH/8) - 1:0]    s_axis_0_tkeep,
    input  [C_S_AXIS_TUSER_WIDTH - 1:0]       s_axis_0_tuser,
    input                                     s_axis_0_tvalid,
    output                                    s_axis_0_tready,
    input                                     s_axis_0_tlast,

    input  [C_S_AXIS_DATA_WIDTH - 1:0]        s_axis_1_tdata,
    input  [(C_S_AXIS_DATA_WIDTH/8) - 1:0]    s_axis_1_tkeep,
    input  [C_S_AXIS_TUSER_WIDTH - 1:0]       s_axis_1_tuser,
    input                                     s_axis_1_tvalid,
    output                                    s_axis_1_tready,
    input                                     s_axis_1_tlast,

    input  [C_S_AXIS_DATA_WIDTH - 1:0]        s_axis_2_tdata,
    input  [(C_S_AXIS_DATA_WIDTH/8) - 1:0]    s_axis_2_tkeep,
    input  [C_S_AXIS_TUSER_WIDTH - 1:0]       s_axis_2_tuser,
    input                                     s_axis_2_tvalid,
    output                                    s_axis_2_tready,
    input                                     s_axis_2_tlast,

    input  [C_S_AXIS_DATA_WIDTH - 1:0]        s_axis_3_tdata,
    input  [(C_S_AXIS_DATA_WIDTH/8) - 1:0]    s_axis_3_tkeep,
    input  [C_S_AXIS_TUSER_WIDTH - 1:0]       s_axis_3_tuser,
    input                                     s_axis_3_tvalid,
    output                                    s_axis_3_tready,
    input                                     s_axis_3_tlast,

    // ---------------- Master AXIS (4 egress to TX adapters) ----------------
    output [C_M_AXIS_DATA_WIDTH - 1:0]        m_axis_0_tdata,
    output [(C_M_AXIS_DATA_WIDTH/8) - 1:0]    m_axis_0_tkeep,
    output [C_M_AXIS_TUSER_WIDTH - 1:0]       m_axis_0_tuser,
    output                                    m_axis_0_tvalid,
    input                                     m_axis_0_tready,
    output                                    m_axis_0_tlast,

    output [C_M_AXIS_DATA_WIDTH - 1:0]        m_axis_1_tdata,
    output [(C_M_AXIS_DATA_WIDTH/8) - 1:0]    m_axis_1_tkeep,
    output [C_M_AXIS_TUSER_WIDTH - 1:0]       m_axis_1_tuser,
    output                                    m_axis_1_tvalid,
    input                                     m_axis_1_tready,
    output                                    m_axis_1_tlast,

    output [C_M_AXIS_DATA_WIDTH - 1:0]        m_axis_2_tdata,
    output [(C_M_AXIS_DATA_WIDTH/8) - 1:0]    m_axis_2_tkeep,
    output [C_M_AXIS_TUSER_WIDTH - 1:0]       m_axis_2_tuser,
    output                                    m_axis_2_tvalid,
    input                                     m_axis_2_tready,
    output                                    m_axis_2_tlast,

    output [C_M_AXIS_DATA_WIDTH - 1:0]        m_axis_3_tdata,
    output [(C_M_AXIS_DATA_WIDTH/8) - 1:0]    m_axis_3_tkeep,
    output [C_M_AXIS_TUSER_WIDTH - 1:0]       m_axis_3_tuser,
    output                                    m_axis_3_tvalid,
    input                                     m_axis_3_tready,
    output                                    m_axis_3_tlast
);

    // ============================================================
    // Internal wires: arbiter -> allreduce -> OPL -> output_queues
    // ============================================================
    wire [C_M_AXIS_DATA_WIDTH-1:0]        s_axis_opl_tdata;
    wire [(C_M_AXIS_DATA_WIDTH/8)-1:0]    s_axis_opl_tkeep;
    wire [C_M_AXIS_TUSER_WIDTH-1:0]       s_axis_opl_tuser;
    wire                                  s_axis_opl_tvalid;
    wire                                  s_axis_opl_tready;
    wire                                  s_axis_opl_tlast;


    wire [C_M_AXIS_DATA_WIDTH-1:0]        allreduce_to_opl_tdata;
    wire [(C_M_AXIS_DATA_WIDTH/8)-1:0]    allreduce_to_opl_tkeep;
    wire [C_M_AXIS_TUSER_WIDTH-1:0]       allreduce_to_opl_tuser;
    wire                                  allreduce_to_opl_tvalid;
    wire                                  allreduce_to_opl_tready;
    wire                                  allreduce_to_opl_tlast;

    wire [C_M_AXIS_DATA_WIDTH-1:0]        m_axis_opl_tdata;
    wire [(C_M_AXIS_DATA_WIDTH/8)-1:0]    m_axis_opl_tkeep;
    wire [C_M_AXIS_TUSER_WIDTH-1:0]       m_axis_opl_tuser;
    wire                                  m_axis_opl_tvalid;
    wire                                  m_axis_opl_tready;
    wire                                  m_axis_opl_tlast;

    // ============================================================
    // input_arbiter (N=4)
    // ============================================================
    input_arbiter #(
        .C_M_AXIS_DATA_WIDTH (C_M_AXIS_DATA_WIDTH),
        .C_S_AXIS_DATA_WIDTH (C_S_AXIS_DATA_WIDTH),
        .C_M_AXIS_TUSER_WIDTH(C_M_AXIS_TUSER_WIDTH),
        .C_S_AXIS_TUSER_WIDTH(C_S_AXIS_TUSER_WIDTH),
        .NUM_QUEUES          (NUM_QUEUES),
        .C_S_AXI_DATA_WIDTH  (C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH  (12),
        .C_BASEADDR          (C_BASEADDR)
    ) u_input_arbiter (
        .axis_aclk      (axis_aclk),
        .axis_resetn    (axis_resetn),

        .m_axis_tdata   (s_axis_opl_tdata),
        .m_axis_tkeep   (s_axis_opl_tkeep),
        .m_axis_tuser   (s_axis_opl_tuser),
        .m_axis_tvalid  (s_axis_opl_tvalid),
        .m_axis_tready  (s_axis_opl_tready),
        .m_axis_tlast   (s_axis_opl_tlast),

        .s_axis_0_tdata (s_axis_0_tdata),
        .s_axis_0_tkeep (s_axis_0_tkeep),
        .s_axis_0_tuser (s_axis_0_tuser),
        .s_axis_0_tvalid(s_axis_0_tvalid),
        .s_axis_0_tready(s_axis_0_tready),
        .s_axis_0_tlast (s_axis_0_tlast),

        .s_axis_1_tdata (s_axis_1_tdata),
        .s_axis_1_tkeep (s_axis_1_tkeep),
        .s_axis_1_tuser (s_axis_1_tuser),
        .s_axis_1_tvalid(s_axis_1_tvalid),
        .s_axis_1_tready(s_axis_1_tready),
        .s_axis_1_tlast (s_axis_1_tlast),

        .s_axis_2_tdata (s_axis_2_tdata),
        .s_axis_2_tkeep (s_axis_2_tkeep),
        .s_axis_2_tuser (s_axis_2_tuser),
        .s_axis_2_tvalid(s_axis_2_tvalid),
        .s_axis_2_tready(s_axis_2_tready),
        .s_axis_2_tlast (s_axis_2_tlast),

        .s_axis_3_tdata (s_axis_3_tdata),
        .s_axis_3_tkeep (s_axis_3_tkeep),
        .s_axis_3_tuser (s_axis_3_tuser),
        .s_axis_3_tvalid(s_axis_3_tvalid),
        .s_axis_3_tready(s_axis_3_tready),
        .s_axis_3_tlast (s_axis_3_tlast),

        .S_AXI_ACLK    (axi_aclk),
        .S_AXI_ARESETN (axi_resetn),
        .S_AXI_AWADDR  (S0_AXI_AWADDR[11:0]),
        .S_AXI_AWVALID (S0_AXI_AWVALID),
        .S_AXI_WDATA   (S0_AXI_WDATA),
        .S_AXI_WSTRB   (S0_AXI_WSTRB),
        .S_AXI_WVALID  (S0_AXI_WVALID),
        .S_AXI_BREADY  (S0_AXI_BREADY),
        .S_AXI_ARADDR  (S0_AXI_ARADDR[11:0]),
        .S_AXI_ARVALID (S0_AXI_ARVALID),
        .S_AXI_RREADY  (S0_AXI_RREADY),
        .S_AXI_ARREADY (S0_AXI_ARREADY),
        .S_AXI_RDATA   (S0_AXI_RDATA),
        .S_AXI_RRESP   (S0_AXI_RRESP),
        .S_AXI_RVALID  (S0_AXI_RVALID),
        .S_AXI_WREADY  (S0_AXI_WREADY),
        .S_AXI_BRESP   (S0_AXI_BRESP),
        .S_AXI_BVALID  (S0_AXI_BVALID),
        .S_AXI_AWREADY (S0_AXI_AWREADY)
    );

    // ============================================================
    // CDC FIFO: input_arbiter (322MHz) → allreduce_wrapper (250MHz)
    // ============================================================
    localparam CDC_WIDTH = C_M_AXIS_DATA_WIDTH + C_M_AXIS_DATA_WIDTH/8 + C_M_AXIS_TUSER_WIDTH + 1;

    wire                                  cdc_in_full;
    wire                                  cdc_in_empty;
    wire [C_M_AXIS_DATA_WIDTH-1:0]        ar_s_tdata;
    wire [(C_M_AXIS_DATA_WIDTH/8)-1:0]    ar_s_tkeep;
    wire [C_M_AXIS_TUSER_WIDTH-1:0]       ar_s_tuser;
    wire                                  ar_s_tlast;
    wire                                  ar_s_tvalid;
    wire                                  ar_s_tready;

    assign s_axis_opl_tready = ~cdc_in_full;
    assign ar_s_tvalid = ~cdc_in_empty;

    xpm_fifo_async #(
        .WRITE_DATA_WIDTH (CDC_WIDTH),
        .READ_DATA_WIDTH  (CDC_WIDTH),
        .FIFO_WRITE_DEPTH (32),
        .CDC_SYNC_STAGES  (3),
        .FULL_RESET_VALUE (0),
        .READ_MODE        ("fwft"),
        .FIFO_MEMORY_TYPE ("distributed")
    ) u_cdc_fifo_in (
        .wr_clk         (axis_aclk),
        .wr_en          (s_axis_opl_tvalid & ~cdc_in_full),
        .din            ({s_axis_opl_tlast, s_axis_opl_tuser, s_axis_opl_tkeep, s_axis_opl_tdata}),
        .full           (cdc_in_full),
        .rd_clk         (allreduce_clk),
        .rd_en          (ar_s_tready & ~cdc_in_empty),
        .dout           ({ar_s_tlast, ar_s_tuser, ar_s_tkeep, ar_s_tdata}),
        .empty          (cdc_in_empty),
        .rst            (~axis_resetn),
        .sleep          (1'b0),
        .injectsbiterr  (1'b0),
        .injectdbiterr  (1'b0),
        .wr_rst_busy    (),
        .rd_rst_busy    (),
        .almost_full    (),
        .almost_empty   (),
        .data_valid     (),
        .wr_data_count  (),
        .rd_data_count  (),
        .prog_full      (),
        .prog_empty     (),
        .overflow       (),
        .underflow      (),
        .wr_ack         (),
        .sbiterr        (),
        .dbiterr        ()
    );

    // ============================================================
    // Allreduce_offload_wrapper (250MHz domain)
    // ============================================================
    wire [C_M_AXIS_DATA_WIDTH-1:0]        ar_m_tdata;
    wire [(C_M_AXIS_DATA_WIDTH/8)-1:0]    ar_m_tkeep;
    wire [C_M_AXIS_TUSER_WIDTH-1:0]       ar_m_tuser;
    wire                                  ar_m_tvalid;
    wire                                  ar_m_tlast;
    wire                                  ar_m_tready;

    allreduce_offload_wrapper #(
        .DATA_W (C_M_AXIS_DATA_WIDTH),
        .KEEP_W (C_M_AXIS_DATA_WIDTH/8),
        .TUSER_W (C_M_AXIS_TUSER_WIDTH)
    ) u_allreduce_wrapper (
        .clk    (allreduce_clk),
        .rst_n  (allreduce_rst_n),

        .cfg_parent_port    (8'h04),
        .cfg_child_port_mask(4'b0011),
        .cfg_is_root        (1'b1),

        // Per-port identity LUT (P0=worker0, P1=worker1)
        .cfg_my_mac_p0      (48'h10_70_fd_19_00_95),
        .cfg_my_mac_p1      (48'h10_70_fd_19_00_95),
        .cfg_my_ip_p0       (32'hC0_A8_01_02),
        .cfg_my_ip_p1       (32'hC0_A8_01_01),
        .cfg_my_qp_p0       (24'd8761),
        .cfg_my_qp_p1       (24'd28406),
        .cfg_my_port_p0     (16'd4791),
        .cfg_my_port_p1     (16'd4791),
        .cfg_peer_mac_p0    (48'h52_54_00_a0_e6_9a),
        .cfg_peer_mac_p1    (48'h52_54_00_07_1b_5b),
        .cfg_peer_ip_p0     (32'hC0_A8_01_01),
        .cfg_peer_ip_p1     (32'hC0_A8_01_02),
        .cfg_peer_qp_p0     (24'd28406),
        .cfg_peer_qp_p1     (24'd8761),
        .cfg_peer_port_p0   (16'd4791),
        .cfg_peer_port_p1   (16'd4791),

        .s_axis_tdata   (ar_s_tdata),
        .s_axis_tkeep   (ar_s_tkeep),
        .s_axis_tuser   (ar_s_tuser),
        .s_axis_tvalid  (ar_s_tvalid),
        .s_axis_tlast   (ar_s_tlast),
        .s_axis_tready  (ar_s_tready),

        .m_axis_tdata   (ar_m_tdata),
        .m_axis_tkeep   (ar_m_tkeep),
        .m_axis_tuser   (ar_m_tuser),
        .m_axis_tvalid  (ar_m_tvalid),
        .m_axis_tlast   (ar_m_tlast),
        .m_axis_tready  (ar_m_tready)
    );

    // ============================================================
    // CDC FIFO: allreduce_wrapper (250MHz) → OPL (322MHz)
    // ============================================================
    wire                                  cdc_out_full;
    wire                                  cdc_out_empty;

    assign ar_m_tready = ~cdc_out_full;
    assign allreduce_to_opl_tvalid = ~cdc_out_empty;

    xpm_fifo_async #(
        .WRITE_DATA_WIDTH (CDC_WIDTH),
        .READ_DATA_WIDTH  (CDC_WIDTH),
        .FIFO_WRITE_DEPTH (32),
        .CDC_SYNC_STAGES  (3),
        .FULL_RESET_VALUE (0),
        .READ_MODE        ("fwft"),
        .FIFO_MEMORY_TYPE ("distributed")
    ) u_cdc_fifo_out (
        .wr_clk         (allreduce_clk),
        .wr_en          (ar_m_tvalid & ~cdc_out_full),
        .din            ({ar_m_tlast, ar_m_tuser, ar_m_tkeep, ar_m_tdata}),
        .full           (cdc_out_full),
        .rd_clk         (axis_aclk),
        .rd_en          (allreduce_to_opl_tready & ~cdc_out_empty),
        .dout           ({allreduce_to_opl_tlast, allreduce_to_opl_tuser, allreduce_to_opl_tkeep, allreduce_to_opl_tdata}),
        .empty          (cdc_out_empty),
        .rst            (~allreduce_rst_n),
        .sleep          (1'b0),
        .injectsbiterr  (1'b0),
        .injectdbiterr  (1'b0),
        .wr_rst_busy    (),
        .rd_rst_busy    (),
        .almost_full    (),
        .almost_empty   (),
        .data_valid     (),
        .wr_data_count  (),
        .rd_data_count  (),
        .prog_full      (),
        .prog_empty     (),
        .overflow       (),
        .underflow      (),
        .wr_ack         (),
        .sbiterr        (),
        .dbiterr        ()
    );

    // ============================================================
    // switch_output_port_lookup (CAM/MAC self-learning, 8-bit one-hot, low 4 bits used)
    // ============================================================
    switch_output_port_lookup #(
        .C_M_AXIS_DATA_WIDTH (C_M_AXIS_DATA_WIDTH),
        .C_S_AXIS_DATA_WIDTH (C_S_AXIS_DATA_WIDTH),
        .C_M_AXIS_TUSER_WIDTH(C_M_AXIS_TUSER_WIDTH),
        .C_S_AXIS_TUSER_WIDTH(C_S_AXIS_TUSER_WIDTH),
        .SRC_PORT_POS        (16),
        .DST_PORT_POS        (24),
        .NUM_OUTPUT_QUEUES   (8),
        .C_S_AXI_DATA_WIDTH  (C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH  (12),
        .C_BASEADDR          (C_BASEADDR)
    ) u_output_port_lookup (
        .axis_aclk      (axis_aclk),
        .axis_resetn    (axis_resetn),

        .s_axis_tdata   (allreduce_to_opl_tdata),
        .s_axis_tkeep   (allreduce_to_opl_tkeep),
        .s_axis_tuser   (allreduce_to_opl_tuser),
        .s_axis_tvalid  (allreduce_to_opl_tvalid),
        .s_axis_tready  (allreduce_to_opl_tready),
        .s_axis_tlast   (allreduce_to_opl_tlast),

        .m_axis_tdata   (m_axis_opl_tdata),
        .m_axis_tkeep   (m_axis_opl_tkeep),
        .m_axis_tuser   (m_axis_opl_tuser),
        .m_axis_tvalid  (m_axis_opl_tvalid),
        .m_axis_tready  (m_axis_opl_tready),
        .m_axis_tlast   (m_axis_opl_tlast),

        .S_AXI_ACLK    (axi_aclk),
        .S_AXI_ARESETN (axi_resetn),
        .S_AXI_AWADDR  (S1_AXI_AWADDR[11:0]),
        .S_AXI_AWVALID (S1_AXI_AWVALID),
        .S_AXI_WDATA   (S1_AXI_WDATA),
        .S_AXI_WSTRB   (S1_AXI_WSTRB),
        .S_AXI_WVALID  (S1_AXI_WVALID),
        .S_AXI_BREADY  (S1_AXI_BREADY),
        .S_AXI_ARADDR  (S1_AXI_ARADDR[11:0]),
        .S_AXI_ARVALID (S1_AXI_ARVALID),
        .S_AXI_RREADY  (S1_AXI_RREADY),
        .S_AXI_ARREADY (S1_AXI_ARREADY),
        .S_AXI_RDATA   (S1_AXI_RDATA),
        .S_AXI_RRESP   (S1_AXI_RRESP),
        .S_AXI_RVALID  (S1_AXI_RVALID),
        .S_AXI_WREADY  (S1_AXI_WREADY),
        .S_AXI_BRESP   (S1_AXI_BRESP),
        .S_AXI_BVALID  (S1_AXI_BVALID),
        .S_AXI_AWREADY (S1_AXI_AWREADY)
    );

    // ============================================================
    // output_queues (N=4)
    // ============================================================
    output_queues #(
        .C_M_AXIS_DATA_WIDTH (C_M_AXIS_DATA_WIDTH),
        .C_S_AXIS_DATA_WIDTH (C_S_AXIS_DATA_WIDTH),
        .C_M_AXIS_TUSER_WIDTH(C_M_AXIS_TUSER_WIDTH),
        .C_S_AXIS_TUSER_WIDTH(C_S_AXIS_TUSER_WIDTH),
        .NUM_QUEUES          (NUM_QUEUES),
        .C_S_AXI_DATA_WIDTH  (C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH  (12),
        .C_BASEADDR          (C_BASEADDR)
    ) u_output_queues (
        .axis_aclk      (axis_aclk),
        .axis_resetn    (axis_resetn),

        .s_axis_tdata   (m_axis_opl_tdata),
        .s_axis_tkeep   (m_axis_opl_tkeep),
        .s_axis_tuser   (m_axis_opl_tuser),
        .s_axis_tvalid  (m_axis_opl_tvalid),
        .s_axis_tready  (m_axis_opl_tready),
        .s_axis_tlast   (m_axis_opl_tlast),

        .m_axis_0_tdata (m_axis_0_tdata),
        .m_axis_0_tkeep (m_axis_0_tkeep),
        .m_axis_0_tuser (m_axis_0_tuser),
        .m_axis_0_tvalid(m_axis_0_tvalid),
        .m_axis_0_tready(m_axis_0_tready),
        .m_axis_0_tlast (m_axis_0_tlast),

        .m_axis_1_tdata (m_axis_1_tdata),
        .m_axis_1_tkeep (m_axis_1_tkeep),
        .m_axis_1_tuser (m_axis_1_tuser),
        .m_axis_1_tvalid(m_axis_1_tvalid),
        .m_axis_1_tready(m_axis_1_tready),
        .m_axis_1_tlast (m_axis_1_tlast),

        .m_axis_2_tdata (m_axis_2_tdata),
        .m_axis_2_tkeep (m_axis_2_tkeep),
        .m_axis_2_tuser (m_axis_2_tuser),
        .m_axis_2_tvalid(m_axis_2_tvalid),
        .m_axis_2_tready(m_axis_2_tready),
        .m_axis_2_tlast (m_axis_2_tlast),

        .m_axis_3_tdata (m_axis_3_tdata),
        .m_axis_3_tkeep (m_axis_3_tkeep),
        .m_axis_3_tuser (m_axis_3_tuser),
        .m_axis_3_tvalid(m_axis_3_tvalid),
        .m_axis_3_tready(m_axis_3_tready),
        .m_axis_3_tlast (m_axis_3_tlast),

        .bytes_stored    (),
        .pkt_stored      (),
        .bytes_removed_0 (),
        .bytes_removed_1 (),
        .bytes_removed_2 (),
        .bytes_removed_3 (),
        .pkt_removed_0   (),
        .pkt_removed_1   (),
        .pkt_removed_2   (),
        .pkt_removed_3   (),
        .bytes_dropped   (),
        .pkt_dropped     (),

        .S_AXI_ACLK    (axi_aclk),
        .S_AXI_ARESETN (axi_resetn),
        .S_AXI_AWADDR  (S2_AXI_AWADDR[11:0]),
        .S_AXI_AWVALID (S2_AXI_AWVALID),
        .S_AXI_WDATA   (S2_AXI_WDATA),
        .S_AXI_WSTRB   (S2_AXI_WSTRB),
        .S_AXI_WVALID  (S2_AXI_WVALID),
        .S_AXI_BREADY  (S2_AXI_BREADY),
        .S_AXI_ARADDR  (S2_AXI_ARADDR[11:0]),
        .S_AXI_ARVALID (S2_AXI_ARVALID),
        .S_AXI_RREADY  (S2_AXI_RREADY),
        .S_AXI_ARREADY (S2_AXI_ARREADY),
        .S_AXI_RDATA   (S2_AXI_RDATA),
        .S_AXI_RRESP   (S2_AXI_RRESP),
        .S_AXI_RVALID  (S2_AXI_RVALID),
        .S_AXI_WREADY  (S2_AXI_WREADY),
        .S_AXI_BRESP   (S2_AXI_BRESP),
        .S_AXI_BVALID  (S2_AXI_BVALID),
        .S_AXI_AWREADY (S2_AXI_AWREADY)
    );

endmodule
