`timescale 1ns / 1ps

module allreduce_config_regs (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        cfg_update_en,
    input  wire [7:0]  cfg_parent_port_in,
    input  wire [3:0]  cfg_child_port_mask_in,
    input  wire        cfg_is_root_in,
    input  wire [47:0] cfg_fpga_mac_in,
    input  wire [31:0] cfg_fpga_ip_in,
    input  wire [23:0] cfg_fpga_qp_in,
    input  wire [15:0] cfg_fpga_udp_port_in,
    input  wire [47:0] cfg_worker0_mac_in,
    input  wire [31:0] cfg_worker0_ip_in,
    input  wire [23:0] cfg_worker0_qp_in,
    input  wire [15:0] cfg_worker0_udp_port_in,
    input  wire [47:0] cfg_worker1_mac_in,
    input  wire [31:0] cfg_worker1_ip_in,
    input  wire [23:0] cfg_worker1_qp_in,
    input  wire [15:0] cfg_worker1_udp_port_in,
    input  wire [47:0] cfg_worker2_mac_in,
    input  wire [31:0] cfg_worker2_ip_in,
    input  wire [23:0] cfg_worker2_qp_in,
    input  wire [15:0] cfg_worker2_udp_port_in,
    input  wire [47:0] cfg_worker3_mac_in,
    input  wire [31:0] cfg_worker3_ip_in,
    input  wire [23:0] cfg_worker3_qp_in,
    input  wire [15:0] cfg_worker3_udp_port_in,

    output reg  [7:0]  cfg_parent_port,
    output reg  [3:0]  cfg_child_port_mask,
    output reg         cfg_is_root,
    output reg  [47:0] cfg_fpga_mac,
    output reg  [31:0] cfg_fpga_ip,
    output reg  [23:0] cfg_fpga_qp,
    output reg  [15:0] cfg_fpga_udp_port,
    output reg  [47:0] cfg_worker0_mac,
    output reg  [31:0] cfg_worker0_ip,
    output reg  [23:0] cfg_worker0_qp,
    output reg  [15:0] cfg_worker0_udp_port,
    output reg  [47:0] cfg_worker1_mac,
    output reg  [31:0] cfg_worker1_ip,
    output reg  [23:0] cfg_worker1_qp,
    output reg  [15:0] cfg_worker1_udp_port,
    output reg  [47:0] cfg_worker2_mac,
    output reg  [31:0] cfg_worker2_ip,
    output reg  [23:0] cfg_worker2_qp,
    output reg  [15:0] cfg_worker2_udp_port,
    output reg  [47:0] cfg_worker3_mac,
    output reg  [31:0] cfg_worker3_ip,
    output reg  [23:0] cfg_worker3_qp,
    output reg  [15:0] cfg_worker3_udp_port
);

    localparam [7:0]  DEFAULT_PARENT_PORT       = 8'h04;
    localparam [3:0]  DEFAULT_CHILD_PORT_MASK   = 4'b0011;
    localparam        DEFAULT_IS_ROOT           = 1'b1;
    localparam [47:0] DEFAULT_FPGA_MAC          = 48'h02_00_00_00_03_07;
    localparam [31:0] DEFAULT_FPGA_IP           = 32'hC0_A8_03_07;
    localparam [23:0] DEFAULT_FPGA_QP           = 24'h000100;
    localparam [15:0] DEFAULT_FPGA_UDP_PORT     = 16'd4791;
    localparam [47:0] DEFAULT_WORKER0_MAC       = 48'h6C_B3_11_88_AB_3E;
    localparam [31:0] DEFAULT_WORKER0_IP        = 32'hC0_A8_03_05;
    localparam [23:0] DEFAULT_WORKER0_QP        = 24'd22676;
    localparam [15:0] DEFAULT_WORKER0_UDP_PORT  = 16'd4791;
    localparam [47:0] DEFAULT_WORKER1_MAC       = 48'h6C_B3_11_88_A9_4E;
    localparam [31:0] DEFAULT_WORKER1_IP        = 32'hC0_A8_03_06;
    localparam [23:0] DEFAULT_WORKER1_QP        = 24'd7957;
    localparam [15:0] DEFAULT_WORKER1_UDP_PORT  = 16'd4791;
    localparam [47:0] DEFAULT_WORKER2_MAC       = 48'hB8_59_9F_01_12_26;
    localparam [31:0] DEFAULT_WORKER2_IP        = 32'hC0_A8_03_08;
    localparam [23:0] DEFAULT_WORKER2_QP        = 24'd28406;
    localparam [15:0] DEFAULT_WORKER2_UDP_PORT  = 16'd4791;
    localparam [47:0] DEFAULT_WORKER3_MAC       = 48'hB8_59_9F_01_11_22;
    localparam [31:0] DEFAULT_WORKER3_IP        = 32'hC0_A8_03_05;
    localparam [23:0] DEFAULT_WORKER3_QP        = 24'd28406;
    localparam [15:0] DEFAULT_WORKER3_UDP_PORT  = 16'd4791;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_parent_port       <= DEFAULT_PARENT_PORT;
            cfg_child_port_mask   <= DEFAULT_CHILD_PORT_MASK;
            cfg_is_root           <= DEFAULT_IS_ROOT;
            cfg_fpga_mac          <= DEFAULT_FPGA_MAC;
            cfg_fpga_ip           <= DEFAULT_FPGA_IP;
            cfg_fpga_qp           <= DEFAULT_FPGA_QP;
            cfg_fpga_udp_port     <= DEFAULT_FPGA_UDP_PORT;
            cfg_worker0_mac       <= DEFAULT_WORKER0_MAC;
            cfg_worker0_ip        <= DEFAULT_WORKER0_IP;
            cfg_worker0_qp        <= DEFAULT_WORKER0_QP;
            cfg_worker0_udp_port  <= DEFAULT_WORKER0_UDP_PORT;
            cfg_worker1_mac       <= DEFAULT_WORKER1_MAC;
            cfg_worker1_ip        <= DEFAULT_WORKER1_IP;
            cfg_worker1_qp        <= DEFAULT_WORKER1_QP;
            cfg_worker1_udp_port  <= DEFAULT_WORKER1_UDP_PORT;
            cfg_worker2_mac       <= DEFAULT_WORKER2_MAC;
            cfg_worker2_ip        <= DEFAULT_WORKER2_IP;
            cfg_worker2_qp        <= DEFAULT_WORKER2_QP;
            cfg_worker2_udp_port  <= DEFAULT_WORKER2_UDP_PORT;
            cfg_worker3_mac       <= DEFAULT_WORKER3_MAC;
            cfg_worker3_ip        <= DEFAULT_WORKER3_IP;
            cfg_worker3_qp        <= DEFAULT_WORKER3_QP;
            cfg_worker3_udp_port  <= DEFAULT_WORKER3_UDP_PORT;
        end else if (cfg_update_en === 1'b1) begin
            cfg_parent_port       <= cfg_parent_port_in;
            cfg_child_port_mask   <= cfg_child_port_mask_in;
            cfg_is_root           <= cfg_is_root_in;
            cfg_fpga_mac          <= cfg_fpga_mac_in;
            cfg_fpga_ip           <= cfg_fpga_ip_in;
            cfg_fpga_qp           <= cfg_fpga_qp_in;
            cfg_fpga_udp_port     <= cfg_fpga_udp_port_in;
            cfg_worker0_mac       <= cfg_worker0_mac_in;
            cfg_worker0_ip        <= cfg_worker0_ip_in;
            cfg_worker0_qp        <= cfg_worker0_qp_in;
            cfg_worker0_udp_port  <= cfg_worker0_udp_port_in;
            cfg_worker1_mac       <= cfg_worker1_mac_in;
            cfg_worker1_ip        <= cfg_worker1_ip_in;
            cfg_worker1_qp        <= cfg_worker1_qp_in;
            cfg_worker1_udp_port  <= cfg_worker1_udp_port_in;
            cfg_worker2_mac       <= cfg_worker2_mac_in;
            cfg_worker2_ip        <= cfg_worker2_ip_in;
            cfg_worker2_qp        <= cfg_worker2_qp_in;
            cfg_worker2_udp_port  <= cfg_worker2_udp_port_in;
            cfg_worker3_mac       <= cfg_worker3_mac_in;
            cfg_worker3_ip        <= cfg_worker3_ip_in;
            cfg_worker3_qp        <= cfg_worker3_qp_in;
            cfg_worker3_udp_port  <= cfg_worker3_udp_port_in;
        end
    end

endmodule
