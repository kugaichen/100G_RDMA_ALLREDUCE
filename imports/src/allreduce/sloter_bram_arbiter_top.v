`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/30 11:23:59
// Design Name: 
// Module Name: sloter_bram_arbiter_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module sloter_bram_arbiter_top #(
    parameter FAN_IN               = 2,
    parameter BUFFER_SLOTS         = 16,
    parameter BUFFER_SLOTS_WIDTH   = $clog2(BUFFER_SLOTS),
    parameter FAN_IN_WIDTH         = $clog2(FAN_IN),
    parameter DATA_WIDTH           = 32,
    parameter ADDR_WIDTH           = 8,
    parameter WINDOWSIZE           = 8
)(
    input wire                      clk,
    input wire                      rst_n,
    input wire                      new_slot_en,
    input wire                      in_valid,
    output wire                     in_ready,
    input wire [3*8-1:0]            in_metadata,

    input wire                      out_ready,
    output wire                     out_valid 
);
    wire                            sloter_arrival_wr_en;
    wire [ADDR_WIDTH-1:0]           sloter_arrival_wr_addr;
    wire [DATA_WIDTH-1:0]           sloter_arrival_wr_data;
    wire                            sloter_arrival_wr_grant;

    wire                            sloter_degree_wr_en;
    wire [ADDR_WIDTH-1:0]           sloter_degree_wr_addr;
    wire [DATA_WIDTH-1:0]           sloter_degree_wr_data;
    wire                            sloter_degree_wr_grant;

    // arbiter -> bram
    wire                    arbiter_arrival_wr_en;
    wire [ADDR_WIDTH-1:0]   arbiter_arrival_wr_addr;
    wire [DATA_WIDTH-1:0]   arbiter_arrival_wr_data;

    wire                    arbiter_degree_wr_en;
    wire [ADDR_WIDTH-1:0]   arbiter_degree_wr_addr;
    wire [DATA_WIDTH-1:0]   arbiter_degree_wr_data;

    new_slot_creater sloter_uut (
        .clk(clk),
        .rst_n(rst_n),
        .new_slot_en(new_slot_en),
        .in_metadata(in_metadata),
        .in_valid(in_valid),
        .in_ready(in_ready),

        .out_ready(out_ready),
        .out_valid(out_valid),
        .new_arrival_state_wr_grant(sloter_arrival_wr_grant),
        .new_arrival_state_wr_en(sloter_arrival_wr_en),
        .new_arrival_state_wr_addr(sloter_arrival_wr_addr),
        .new_arrival_state_wr_data(sloter_arrival_wr_data),

        .new_degree_wr_grant(sloter_degree_wr_grant),
        .new_degree_wr_en(sloter_degree_wr_en),
        .new_degree_wr_addr(sloter_degree_wr_addr),
        .new_degree_wr_data(sloter_degree_wr_data)
    );

    arrival_state_mem arrival_state_uut (
        .clk(clk),
        .wr_en(arbiter_arrival_wr_en),
        .wr_addr(arbiter_arrival_wr_addr),
        .wr_data(arbiter_arrival_wr_data),

        .rd_en(0),
        .rd_addr(0),
        .rd_data()
    );

    degree_bram degree_bram_uut (
        .clk(clk),
        .wr_en(arbiter_degree_wr_en),
        .wr_addr(arbiter_degree_wr_addr),
        .wr_data(arbiter_degree_wr_data),
       
        .rd_en(0),
        .rd_addr(0),
        .rd_data()
    );

    bram_write_arbiter arrival_write_arbiter_uut (
        .clk(clk),
        .rst_n(rst_n),
        .req0_wr_en(sloter_arrival_wr_en),
        .req0_wr_addr(sloter_arrival_wr_addr),
        .req0_wr_data(sloter_arrival_wr_data),
        .grant0(sloter_arrival_wr_grant),

        .bram_wr_en(arbiter_arrival_wr_en),
        .bram_wr_addr(arbiter_arrival_wr_addr),
        .bram_wr_data(arbiter_arrival_wr_data),

        .req1_wr_en(0),
        .req1_wr_addr(0),
        .req1_wr_data(0),
        .grant1(),

        .req2_wr_en(0),
        .req2_wr_addr(0),
        .req2_wr_data(0),
        .grant2()

    );

    bram_write_arbiter degree_write_arbiter_uut (
        .clk(clk),
        .rst_n(rst_n),
        .req0_wr_en(sloter_degree_wr_en),
        .req0_wr_addr(sloter_degree_wr_addr),
        .req0_wr_data(sloter_degree_wr_data),
        .grant0(sloter_degree_wr_grant),

        .bram_wr_en(arbiter_degree_wr_en),
        .bram_wr_addr(arbiter_degree_wr_addr),
        .bram_wr_data(arbiter_degree_wr_data),

        .req1_wr_en(0),
        .req1_wr_addr(0),
        .req1_wr_data(0),
        .grant1(),

        .req2_wr_en(0),
        .req2_wr_addr(0),
        .req2_wr_data(0),
        .grant2()
    );

endmodule
