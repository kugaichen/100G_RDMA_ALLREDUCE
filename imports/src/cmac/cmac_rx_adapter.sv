`timescale 1ns / 1ps
`include "switch_defs.svh"

module cmac_rx_adapter #(
    parameter int DATA_W  = `SWITCH_BASIC_DATA_W,
    parameter int KEEP_W  = `SWITCH_BASIC_KEEP_W,
    parameter int TUSER_W = `SWITCH_BASIC_TUSER_W,
    parameter int PORT_W  = `SWITCH_BASIC_PORT_W
)(
    input  logic               cmac_rx_clk,
    input  logic               cmac_rx_rst,
    input  logic               switch_clk,
    input  logic               switch_rst,
    input  logic [PORT_W-1:0]  src_port_1hot,

    input  logic [DATA_W-1:0]  rx_axis_tdata,
    input  logic [KEEP_W-1:0]  rx_axis_tkeep,
    input  logic               rx_axis_tvalid,
    input  logic               rx_axis_tlast,

    output logic [DATA_W-1:0]  m_axis_tdata,
    output logic [KEEP_W-1:0]  m_axis_tkeep,
    output logic [TUSER_W-1:0] m_axis_tuser,
    output logic               m_axis_tvalid,
    input  logic               m_axis_tready,
    output logic               m_axis_tlast,

    output logic               pkt_drop_overflow
);

    localparam int DATA_FIFO_W = DATA_W + KEEP_W + 1;
    localparam int META_FIFO_W = 16 + PORT_W;

    logic [DATA_FIFO_W-1:0] data_fifo_din;
    logic [DATA_FIFO_W-1:0] data_fifo_dout;
    logic                   data_fifo_wr_en;
    logic                   data_fifo_rd_en;
    logic                   data_fifo_full;
    logic                   data_fifo_empty;

    logic [META_FIFO_W-1:0] meta_fifo_din;
    logic [META_FIFO_W-1:0] meta_fifo_dout;
    logic                   meta_fifo_wr_en;
    logic                   meta_fifo_rd_en;
    logic                   meta_fifo_full;
    logic                   meta_fifo_empty;

    logic [15:0]            rx_pkt_len;
    logic [15:0]            cur_pkt_len;
    logic [PORT_W-1:0]      cur_src_port;
    logic                   packet_active;

    function automatic [15:0] count_keep_bytes(input logic [KEEP_W-1:0] keep);
        integer i;
        begin
            count_keep_bytes = '0;
            for (i = 0; i < KEEP_W; i = i + 1) begin
                count_keep_bytes = count_keep_bytes + keep[i];
            end
        end
    endfunction

    assign data_fifo_din  = {rx_axis_tlast, rx_axis_tkeep, rx_axis_tdata};
    assign data_fifo_wr_en = rx_axis_tvalid && !data_fifo_full;

    always_ff @(posedge cmac_rx_clk) begin
        if (cmac_rx_rst) begin
            rx_pkt_len         <= '0;
            meta_fifo_din      <= '0;
            meta_fifo_wr_en    <= 1'b0;
            pkt_drop_overflow  <= 1'b0;
        end else begin
            meta_fifo_wr_en <= 1'b0;

            if (rx_axis_tvalid && data_fifo_full) begin
                pkt_drop_overflow <= 1'b1;
            end

            if (rx_axis_tvalid) begin
                if (data_fifo_full) begin
                    rx_pkt_len <= '0;
                end else if (rx_axis_tlast) begin
                    if (!meta_fifo_full) begin
                        meta_fifo_din   <= {src_port_1hot, rx_pkt_len + count_keep_bytes(rx_axis_tkeep)};
                        meta_fifo_wr_en <= 1'b1;
                    end else begin
                        pkt_drop_overflow <= 1'b1;
                    end
                    rx_pkt_len <= '0;
                end else begin
                    rx_pkt_len <= rx_pkt_len + count_keep_bytes(rx_axis_tkeep);
                end
            end
        end
    end

    xpm_fifo_async #(
        .CASCADE_HEIGHT      (0),
        .CDC_SYNC_STAGES     (2),
        .DOUT_RESET_VALUE    ("0"),
        .ECC_MODE            ("no_ecc"),
        .FIFO_MEMORY_TYPE    ("auto"),
        .FIFO_READ_LATENCY   (0),
        .FIFO_WRITE_DEPTH    (4096),
        .FULL_RESET_VALUE    (0),
        .PROG_EMPTY_THRESH   (10),
        .PROG_FULL_THRESH    (10),
        .RD_DATA_COUNT_WIDTH (1),
        .READ_DATA_WIDTH     (DATA_FIFO_W),
        .READ_MODE           ("fwft"),
        .RELATED_CLOCKS      (0),
        .SIM_ASSERT_CHK      (0),
        .USE_ADV_FEATURES    ("0303"),
        .WAKEUP_TIME         (0),
        .WRITE_DATA_WIDTH    (DATA_FIFO_W),
        .WR_DATA_COUNT_WIDTH (1)
    ) u_data_fifo (
        .rst            (cmac_rx_rst | switch_rst),
        .wr_clk         (cmac_rx_clk),
        .wr_en          (data_fifo_wr_en),
        .din            (data_fifo_din),
        .full           (data_fifo_full),
        .wr_ack         (),
        .overflow       (),
        .prog_full      (),
        .almost_full    (),
        .wr_data_count  (),
        .rd_clk         (switch_clk),
        .rd_en          (data_fifo_rd_en),
        .dout           (data_fifo_dout),
        .empty          (data_fifo_empty),
        .underflow      (),
        .prog_empty     (),
        .almost_empty   (),
        .rd_data_count  (),
        .sleep          (1'b0),
        .injectsbiterr  (1'b0),
        .injectdbiterr  (1'b0),
        .sbiterr        (),
        .dbiterr        ()
    );

    xpm_fifo_async #(
        .CASCADE_HEIGHT      (0),
        .CDC_SYNC_STAGES     (2),
        .DOUT_RESET_VALUE    ("0"),
        .ECC_MODE            ("no_ecc"),
        .FIFO_MEMORY_TYPE    ("auto"),
        .FIFO_READ_LATENCY   (0),
        .FIFO_WRITE_DEPTH    (1024),
        .FULL_RESET_VALUE    (0),
        .PROG_EMPTY_THRESH   (10),
        .PROG_FULL_THRESH    (10),
        .RD_DATA_COUNT_WIDTH (1),
        .READ_DATA_WIDTH     (META_FIFO_W),
        .READ_MODE           ("fwft"),
        .RELATED_CLOCKS      (0),
        .SIM_ASSERT_CHK      (0),
        .USE_ADV_FEATURES    ("0303"),
        .WAKEUP_TIME         (0),
        .WRITE_DATA_WIDTH    (META_FIFO_W),
        .WR_DATA_COUNT_WIDTH (1)
    ) u_meta_fifo (
        .rst            (cmac_rx_rst | switch_rst),
        .wr_clk         (cmac_rx_clk),
        .wr_en          (meta_fifo_wr_en),
        .din            (meta_fifo_din),
        .full           (meta_fifo_full),
        .wr_ack         (),
        .overflow       (),
        .prog_full      (),
        .almost_full    (),
        .wr_data_count  (),
        .rd_clk         (switch_clk),
        .rd_en          (meta_fifo_rd_en),
        .dout           (meta_fifo_dout),
        .empty          (meta_fifo_empty),
        .underflow      (),
        .prog_empty     (),
        .almost_empty   (),
        .rd_data_count  (),
        .sleep          (1'b0),
        .injectsbiterr  (1'b0),
        .injectdbiterr  (1'b0),
        .sbiterr        (),
        .dbiterr        ()
    );

    assign m_axis_tdata  = data_fifo_dout[DATA_W-1:0];
    assign m_axis_tkeep  = data_fifo_dout[DATA_W+KEEP_W-1:DATA_W];
    assign m_axis_tlast  = data_fifo_dout[DATA_W+KEEP_W];
    assign m_axis_tuser  = {96'd0, 8'd0, cur_src_port, cur_pkt_len};
    assign m_axis_tvalid = packet_active && !data_fifo_empty;

    assign data_fifo_rd_en = m_axis_tvalid && m_axis_tready;
    assign meta_fifo_rd_en = !packet_active && !data_fifo_empty && !meta_fifo_empty;

    always_ff @(posedge switch_clk) begin
        if (switch_rst) begin
            packet_active <= 1'b0;
            cur_pkt_len   <= '0;
            cur_src_port  <= '0;
        end else begin
            if (!packet_active && !data_fifo_empty && !meta_fifo_empty) begin
                cur_pkt_len   <= meta_fifo_dout[15:0];
                cur_src_port  <= meta_fifo_dout[META_FIFO_W-1:16];
                packet_active <= 1'b1;
            end else if (m_axis_tvalid && m_axis_tready && m_axis_tlast) begin
                packet_active <= 1'b0;
            end
        end
    end

endmodule
