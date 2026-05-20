`timescale 1ns / 1ps
`include "switch_defs.svh"

module cmac_tx_adapter #(
    parameter int DATA_W  = `SWITCH_BASIC_DATA_W,
    parameter int KEEP_W  = `SWITCH_BASIC_KEEP_W,
    parameter int TUSER_W = `SWITCH_BASIC_TUSER_W
)(
    input  logic               switch_clk,
    input  logic               switch_rst,
    input  logic               cmac_tx_clk,
    input  logic               cmac_tx_rst,

    input  logic [DATA_W-1:0]  s_axis_tdata,
    input  logic [KEEP_W-1:0]  s_axis_tkeep,
    input  logic [TUSER_W-1:0] s_axis_tuser,
    input  logic               s_axis_tvalid,
    output logic               s_axis_tready,
    input  logic               s_axis_tlast,

    output logic [DATA_W-1:0]  tx_axis_tdata,
    output logic [KEEP_W-1:0]  tx_axis_tkeep,
    output logic               tx_axis_tvalid,
    input  logic               tx_axis_tready,
    output logic               tx_axis_tlast,

    output logic               pkt_drop_overflow
);

    localparam int FIFO_W = DATA_W + KEEP_W + 1;

    logic [FIFO_W-1:0] fifo_din;
    logic [FIFO_W-1:0] fifo_dout;
    logic              fifo_full;
    logic              fifo_empty;
    logic              fifo_rd_en;
    logic              fifo_wr_en;

    assign fifo_din   = {s_axis_tlast, s_axis_tkeep, s_axis_tdata};
    assign fifo_wr_en = s_axis_tvalid && s_axis_tready;
    assign s_axis_tready = !fifo_full;

    always_ff @(posedge switch_clk) begin
        if (switch_rst) begin
            pkt_drop_overflow <= 1'b0;
        end else if (s_axis_tvalid && !s_axis_tready) begin
            pkt_drop_overflow <= 1'b1;
        end
    end

    xpm_fifo_async #(
        .CASCADE_HEIGHT      (0),
        .CDC_SYNC_STAGES     (2),
        .DOUT_RESET_VALUE    ("0"),
        .ECC_MODE            ("no_ecc"),
        .FIFO_MEMORY_TYPE    ("auto"),
        .FIFO_READ_LATENCY   (0),
        .FIFO_WRITE_DEPTH    (2048),
        .FULL_RESET_VALUE    (0),
        .PROG_EMPTY_THRESH   (10),
        .PROG_FULL_THRESH    (10),
        .RD_DATA_COUNT_WIDTH (1),
        .READ_DATA_WIDTH     (FIFO_W),
        .READ_MODE           ("fwft"),
        .RELATED_CLOCKS      (0),
        .SIM_ASSERT_CHK      (0),
        .USE_ADV_FEATURES    ("0303"),
        .WAKEUP_TIME         (0),
        .WRITE_DATA_WIDTH    (FIFO_W),
        .WR_DATA_COUNT_WIDTH (1)
    ) u_tx_fifo (
        .rst            (switch_rst | cmac_tx_rst),
        .wr_clk         (switch_clk),
        .wr_en          (fifo_wr_en),
        .din            (fifo_din),
        .full           (fifo_full),
        .wr_ack         (),
        .overflow       (),
        .prog_full      (),
        .almost_full    (),
        .wr_data_count  (),
        .rd_clk         (cmac_tx_clk),
        .rd_en          (fifo_rd_en),
        .dout           (fifo_dout),
        .empty          (fifo_empty),
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

    assign tx_axis_tdata  = fifo_dout[DATA_W-1:0];
    assign tx_axis_tkeep  = fifo_dout[DATA_W+KEEP_W-1:DATA_W];
    assign tx_axis_tlast  = fifo_dout[DATA_W+KEEP_W];
    assign tx_axis_tvalid = !fifo_empty;
    assign fifo_rd_en     = tx_axis_tvalid && tx_axis_tready;

    // The current CMAC path does not consume internal metadata.
    logic unused_tuser;
    assign unused_tuser = ^s_axis_tuser;

endmodule
