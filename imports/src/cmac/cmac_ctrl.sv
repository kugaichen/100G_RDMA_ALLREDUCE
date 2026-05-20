// Copyright (c) 2026 Xuanwu Tech. All rights reserved.
`timescale 1ns / 1ps

module cmac_ctrl (
    input  logic       sys_clk,
    input  logic       sys_rst_n,

    // GT status
    input  logic       gt_tx_reset_done,
    input  logic       gt_rx_reset_done,

    // CMAC control outputs
    output logic       ctl_tx_enable,
    output logic       ctl_rx_enable,
    output logic       ctl_tx_send_rfi,
    output logic       ctl_tx_send_lfi,
    output logic       ctl_tx_send_idle,
    output logic [2:0] gt_loopback,

    // CMAC status inputs
    input  logic       stat_rx_aligned,
    input  logic       stat_rx_status,

    // User control
    input  logic       gt_loopback_en,
    input  logic       port_enable,

    // Status outputs
    output logic       link_up,
    output logic       init_done,
    output logic [3:0] init_state
);

    typedef enum logic [3:0] {
        ST_RESET        = 4'd0,
        ST_WAIT_GT_RST  = 4'd1,
        ST_ENABLE_TX    = 4'd2,
        ST_ENABLE_RX    = 4'd3,
        ST_WAIT_ALIGNED = 4'd4,
        ST_LINK_UP      = 4'd5,
        ST_GT_FAIL      = 4'd6,
        ST_LINK_FAIL    = 4'd7,
        ST_LINK_LOST    = 4'd8
    } init_state_t;

    init_state_t state;
    assign init_state = state;

    logic [31:0] timeout_cnt;

    localparam int GT_RESET_TIMEOUT  = 32'd90_000_000;
    localparam int LINK_TIMEOUT      = 32'd450_000_000;
    localparam int ENABLE_DELAY      = 32'd900;

    logic gt_tx_rst_done_sync, gt_rx_rst_done_sync;
    logic rx_aligned_sync, rx_status_sync;

    sync_signal #(.WIDTH(1)) u_sync_gt_tx (
        .clk_dst(sys_clk), .sig_in(gt_tx_reset_done), .sig_out(gt_tx_rst_done_sync));
    sync_signal #(.WIDTH(1)) u_sync_gt_rx (
        .clk_dst(sys_clk), .sig_in(gt_rx_reset_done), .sig_out(gt_rx_rst_done_sync));
    sync_signal #(.WIDTH(1)) u_sync_aligned (
        .clk_dst(sys_clk), .sig_in(stat_rx_aligned), .sig_out(rx_aligned_sync));
    sync_signal #(.WIDTH(1)) u_sync_status (
        .clk_dst(sys_clk), .sig_in(stat_rx_status), .sig_out(rx_status_sync));

    always_ff @(posedge sys_clk) begin
        if (!sys_rst_n || !port_enable) begin
            state           <= ST_RESET;
            ctl_tx_enable   <= 1'b0;
            ctl_rx_enable   <= 1'b0;
            ctl_tx_send_rfi <= 1'b0;
            ctl_tx_send_lfi <= 1'b0;
            ctl_tx_send_idle<= 1'b0;
            link_up         <= 1'b0;
            init_done       <= 1'b0;
            timeout_cnt     <= '0;
            gt_loopback     <= 3'b000;
        end else begin
            gt_loopback <= gt_loopback_en ? 3'b010 : 3'b000;

            case (state)
                ST_RESET: begin
                    ctl_tx_enable <= 1'b0;
                    ctl_rx_enable <= 1'b0;
                    link_up       <= 1'b0;
                    init_done     <= 1'b0;
                    timeout_cnt   <= '0;
                    state         <= ST_WAIT_GT_RST;
                end

                ST_WAIT_GT_RST: begin
                    timeout_cnt <= timeout_cnt + 1'b1;
                    if (gt_tx_rst_done_sync && gt_rx_rst_done_sync) begin
                        timeout_cnt <= '0;
                        state       <= ST_ENABLE_TX;
                    end else if (timeout_cnt >= GT_RESET_TIMEOUT) begin
                        state <= ST_GT_FAIL;
                    end
                end

                ST_ENABLE_TX: begin
                    ctl_tx_enable <= 1'b1;
                    timeout_cnt   <= timeout_cnt + 1'b1;
                    if (timeout_cnt >= ENABLE_DELAY) begin
                        timeout_cnt <= '0;
                        state       <= ST_ENABLE_RX;
                    end
                end

                ST_ENABLE_RX: begin
                    ctl_rx_enable <= 1'b1;
                    timeout_cnt   <= timeout_cnt + 1'b1;
                    if (timeout_cnt >= ENABLE_DELAY) begin
                        timeout_cnt <= '0;
                        state       <= ST_WAIT_ALIGNED;
                    end
                end

                ST_WAIT_ALIGNED: begin
                    timeout_cnt <= timeout_cnt + 1'b1;
                    if (rx_aligned_sync && rx_status_sync) begin
                        state     <= ST_LINK_UP;
                        link_up   <= 1'b1;
                        init_done <= 1'b1;
                    end else if (timeout_cnt >= LINK_TIMEOUT) begin
                        state <= ST_LINK_FAIL;
                    end
                end

                ST_LINK_UP: begin
                    link_up <= 1'b1;
                    if (!rx_aligned_sync) begin
                        link_up <= 1'b0;
                        state   <= ST_LINK_LOST;
                    end
                end

                ST_GT_FAIL: begin
                end

                ST_LINK_FAIL: begin
                end

                ST_LINK_LOST: begin
                    link_up <= 1'b0;
                    timeout_cnt <= '0;
                    state       <= ST_WAIT_ALIGNED;
                end

                default: state <= ST_RESET;
            endcase
        end
    end

endmodule
// Copyright (c) 2026 Xuanwu Tech. All rights reserved.
