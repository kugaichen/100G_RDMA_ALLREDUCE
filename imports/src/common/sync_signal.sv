// Copyright (c) 2026 Xuanwu Tech. All rights reserved.
`timescale 1ns / 1ps

module sync_signal #(
    parameter int WIDTH = 1,
    parameter int STAGES = 3
)(
    input  logic             clk_dst,
    input  logic [WIDTH-1:0] sig_in,
    output logic [WIDTH-1:0] sig_out
);

    xpm_cdc_array_single #(
        .DEST_SYNC_FF   (STAGES),
        .INIT_SYNC_FF   (0),
        .SIM_ASSERT_CHK (0),
        .SRC_INPUT_REG  (0),
        .WIDTH          (WIDTH)
    ) u_xpm_cdc (
        .dest_out (sig_out),
        .dest_clk (clk_dst),
        .src_clk  (1'b0),
        .src_in   (sig_in)
    );

endmodule
// Copyright (c) 2026 Xuanwu Tech. All rights reserved.
