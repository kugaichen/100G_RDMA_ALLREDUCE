// Copyright (c) 2026 Xuanwu Tech. All rights reserved.
`timescale 1ns / 1ps

module clk_rst_gen (
    input  logic sys_clk_90m,   // Raw 90 MHz from non-dedicated pin
    output logic sys_clk,       // Buffered global clock
    output logic sys_rst_n      // Active-low power-on reset
);

    logic sys_clk_90m_ibuf;

    IBUF u_ibuf_clk (
        .I (sys_clk_90m),
        .O (sys_clk_90m_ibuf)
    );

    BUFG u_bufg_clk (
        .I (sys_clk_90m_ibuf),
        .O (sys_clk)
    );

    localparam int RST_COUNT_WIDTH = 24;

    logic [RST_COUNT_WIDTH-1:0] rst_counter = '0;
    logic                       rst_counter_done = 1'b0;
    logic [2:0]                 rst_sync = 3'b000;

    always_ff @(posedge sys_clk) begin
        if (!rst_counter_done) begin
            rst_counter <= rst_counter + 1'b1;
            if (rst_counter == {RST_COUNT_WIDTH{1'b1}})
                rst_counter_done <= 1'b1;
        end
    end

    always_ff @(posedge sys_clk) begin
        rst_sync <= {rst_sync[1:0], rst_counter_done};
    end

    assign sys_rst_n = rst_sync[2];

endmodule
// Copyright (c) 2026 Xuanwu Tech. All rights reserved.
