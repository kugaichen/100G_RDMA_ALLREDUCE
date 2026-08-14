`timescale 1ns / 1ps

module allreduce_offload_wrapper #(
    parameter DATA_W    = 512,
    parameter KEEP_W    = 64,
    parameter TUSER_W   = 128,
    parameter NUM_PORTS = 4
)(
    input wire  clk,
    input wire  rst_n,

    input wire [7:0]            cfg_parent_port,
    input wire [NUM_PORTS-1:0]  cfg_child_port_mask,
    input wire                  cfg_is_root,

    // Per-port identity LUT (广播路径使用)
    input wire [47:0]           cfg_my_mac_p0,
    input wire [47:0]           cfg_my_mac_p1,
    input wire [31:0]           cfg_my_ip_p0,
    input wire [31:0]           cfg_my_ip_p1,
    input wire [23:0]           cfg_my_qp_p0,
    input wire [23:0]           cfg_my_qp_p1,
    input wire [15:0]           cfg_my_port_p0,
    input wire [15:0]           cfg_my_port_p1,
    input wire [47:0]           cfg_peer_mac_p0,
    input wire [47:0]           cfg_peer_mac_p1,
    input wire [31:0]           cfg_peer_ip_p0,
    input wire [31:0]           cfg_peer_ip_p1,
    input wire [23:0]           cfg_peer_qp_p0,
    input wire [23:0]           cfg_peer_qp_p1,
    input wire [15:0]           cfg_peer_port_p0,
    input wire [15:0]           cfg_peer_port_p1,

    input wire [DATA_W-1:0]     s_axis_tdata,
    input wire [KEEP_W-1:0]     s_axis_tkeep,
    input wire [TUSER_W-1:0]    s_axis_tuser,
    input wire                  s_axis_tvalid,
    input wire                  s_axis_tlast,
    output wire                 s_axis_tready,

    output wire [DATA_W-1:0]    m_axis_tdata,
    output wire [KEEP_W-1:0]    m_axis_tkeep,
    output reg  [TUSER_W-1:0]   m_axis_tuser,
    output wire                 m_axis_tvalid,
    output wire                 m_axis_tlast,
    input wire                  m_axis_tready
);

    localparam ROUTE_PASSTHROUGH            = 3'd0;
    localparam ROUTE_TO_PARENT              = 3'd1;
    localparam ROUTE_TO_CHILD_SINGLE        = 3'd2;
    localparam ROUTE_TO_CHILDREN_ALL        = 3'd3;
    localparam ROUTE_TO_PARENT_AND_CHILDREN = 3'd4;

    // ============================================================
    // 1. ingress_port: one-hot -> binary
    // ============================================================
    reg [7:0] ingress_port_binary;
    always @(*) begin
        case (s_axis_tuser[23:16])
            8'h01:   ingress_port_binary = 8'd0;
            8'h02:   ingress_port_binary = 8'd1;
            8'h04:   ingress_port_binary = 8'd2;
            8'h08:   ingress_port_binary = 8'd3;
            default: ingress_port_binary = 8'd0;
        endcase
    end

    // ============================================================
    // 2. Latch first-beat TUSER
    // ============================================================
    reg [TUSER_W-1:0] latched_tuser;
    reg               in_packet;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_tuser <= {TUSER_W{1'b0}};
            in_packet     <= 1'b0;
        end else if (s_axis_tvalid && s_axis_tready) begin
            if (!in_packet) begin
                latched_tuser <= s_axis_tuser;
                in_packet     <= 1'b1;
            end
            if (s_axis_tlast)
                in_packet <= 1'b0;
        end
    end

    // ============================================================
    // 3. AllReduce core
    // ============================================================
    wire [DATA_W-1:0] ar_m_tdata;
    wire [KEEP_W-1:0] ar_m_tkeep;
    wire [TUSER_W-1:0] ar_m_tuser;
    wire              ar_m_tvalid;
    wire              ar_m_tlast;
    wire [2:0]        ar_m_route_type;
    wire              ar_m_is_aggregated;
    wire [7:0]        ar_m_agg_ingress_port;

    allreduce_offload_top u_allreduce (
        .clk                     (clk),
        .rst_n                   (rst_n),
        .s_axis_tdata            (s_axis_tdata),
        .s_axis_tkeep            (s_axis_tkeep),
        .s_axis_tvalid           (s_axis_tvalid),
        .s_axis_tlast            (s_axis_tlast),
        .s_axis_tready           (s_axis_tready),
        .m_axis_tdata            (ar_m_tdata),
        .m_axis_tkeep            (ar_m_tkeep),
        .m_axis_tuser            (ar_m_tuser),
        .m_axis_tvalid           (ar_m_tvalid),
        .m_axis_tlast            (ar_m_tlast),
        .m_axis_tready           (m_axis_tready),
        .m_axis_route_type       (ar_m_route_type),
        .m_axis_is_aggregated    (ar_m_is_aggregated),
        .m_axis_agg_ingress_port (ar_m_agg_ingress_port),
        .ingress_port            (ingress_port_binary),
        .cfg_is_root             (cfg_is_root),
        .cfg_my_mac_p0           (cfg_my_mac_p0),
        .cfg_my_mac_p1           (cfg_my_mac_p1),
        .cfg_my_ip_p0            (cfg_my_ip_p0),
        .cfg_my_ip_p1            (cfg_my_ip_p1),
        .cfg_my_qp_p0            (cfg_my_qp_p0),
        .cfg_my_qp_p1            (cfg_my_qp_p1),
        .cfg_my_port_p0          (cfg_my_port_p0),
        .cfg_my_port_p1          (cfg_my_port_p1),
        .cfg_peer_mac_p0         (cfg_peer_mac_p0),
        .cfg_peer_mac_p1         (cfg_peer_mac_p1),
        .cfg_peer_ip_p0          (cfg_peer_ip_p0),
        .cfg_peer_ip_p1          (cfg_peer_ip_p1),
        .cfg_peer_qp_p0          (cfg_peer_qp_p0),
        .cfg_peer_qp_p1          (cfg_peer_qp_p1),
        .cfg_peer_port_p0        (cfg_peer_port_p0),
        .cfg_peer_port_p1        (cfg_peer_port_p1)
    );

    // ============================================================
    // 4. agg_ingress_port binary -> one-hot
    // ============================================================
    reg [7:0] agg_ingress_1hot;
    always @(*) begin
        case (ar_m_agg_ingress_port)
            8'd0:    agg_ingress_1hot = 8'h01;
            8'd1:    agg_ingress_1hot = 8'h02;
            8'd2:    agg_ingress_1hot = 8'h04;
            8'd3:    agg_ingress_1hot = 8'h08;
            default: agg_ingress_1hot = 8'h01;
        endcase
    end

    // ============================================================
    // 5. Build output TUSER with dst_port
    // ============================================================
    always @(*) begin
        if (!ar_m_is_aggregated) begin
            m_axis_tuser = latched_tuser;
        end else if (ar_m_tuser[32]) begin
            m_axis_tuser = ar_m_tuser;
        end else begin
            m_axis_tuser = latched_tuser;
            m_axis_tuser[32] = 1'b1;
            m_axis_tuser[33] = 1'b0;
            case (ar_m_route_type)
                ROUTE_TO_PARENT:
                    m_axis_tuser[31:24] = cfg_parent_port;
                ROUTE_TO_CHILD_SINGLE:
                    m_axis_tuser[31:24] = agg_ingress_1hot;
                ROUTE_TO_CHILDREN_ALL: begin
                    m_axis_tuser[31:24] = {4'b0000, cfg_child_port_mask};
                    m_axis_tuser[33] = 1'b1;
                end
                ROUTE_TO_PARENT_AND_CHILDREN: begin
                    m_axis_tuser[31:24] = cfg_parent_port | {4'b0000, cfg_child_port_mask};
                    m_axis_tuser[33] = 1'b1;
                end
                default:
                    m_axis_tuser[31:24] = 8'h00;
            endcase
        end
    end

    // ============================================================
    // 6. ICRC 计算迁移到 nf_datapath_4port 中的 per_port_rewriter
    //    wrapper 直接透传 deparser 输出
    // ============================================================
    assign m_axis_tdata  = ar_m_tdata;
    assign m_axis_tkeep  = ar_m_tkeep;
    assign m_axis_tvalid = ar_m_tvalid;
    assign m_axis_tlast  = ar_m_tlast;

endmodule
