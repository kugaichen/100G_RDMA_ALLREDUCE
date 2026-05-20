`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/29 21:28:42
// Design Name: 
// Module Name: upbroadcast_bram_arbiter_top
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


module up_broadcast_bram_arbiter_top #(
    parameter FAN_IN               = 2,
    parameter BUFFER_SLOTS         = 16,
    parameter BUFFER_SLOTS_WIDTH   = $clog2(BUFFER_SLOTS),
    parameter FAN_IN_WIDTH         = $clog2(FAN_IN),
    parameter DATA_WIDTH           = 32,
    parameter ADDR_WIDTH           = 8
)(
    input wire                      clk,
    input wire                      rst_n,

    input wire                      controller_out_valid,
    output wire                     in_ready,
    input wire [3*8-1:0]            in_metadata,
    
    input wire                      FAN_retrans_check_en,

    // out
    input  wire                     out_ready,
    output wire                     out_valid,
    output wire                     FAN_retrans_en,
    output wire                     down_broadcast_en,
    output wire                     new_slot_en,
    output wire                     FAN_trans_en
);

    // upbroadcast -> arbiter
    wire                     upbroadcast_arrival_wr_en;
    wire [ADDR_WIDTH-1:0]    upbroadcast_arrival_wr_addr;
    wire [DATA_WIDTH-1:0]    upbroadcast_arrival_wr_data;
    wire                     upbroadcast_arrival_wr_grant;

    wire                     upbroadcast_arrival_rd_en;
    wire [ADDR_WIDTH-1:0]    upbroadcast_arrival_rd_addr;
    wire                     upbroadcast_arrival_rd_grant;

    wire                     upbroadcast_degree_rd_en;
    wire [ADDR_WIDTH-1:0]    upbroadcast_degree_rd_addr;
    wire                     upbroadcast_degree_rd_grant;


    // arbiter -> bram
    wire                    arbiter_arrival_wr_en;
    wire [ADDR_WIDTH-1:0]   arbiter_arrival_wr_addr;
    wire [DATA_WIDTH-1:0]   arbiter_arrival_wr_data;

    wire                    arbiter_arrival_rd_en;
    wire [ADDR_WIDTH-1:0]   arbiter_arrival_rd_addr;

    wire                    arbiter_degree_rd_en;
    wire [ADDR_WIDTH-1:0]   arbiter_degree_rd_addr;

    // bram -> upbroadcast
    wire [DATA_WIDTH-1:0]   bram_arrival_rd_data;
    wire [DATA_WIDTH-1:0]   bram_degree_rd_data;

    up_broadcast_checkor_arrival_updater upbroadcast_uut (
        .clk(clk),
        .rst_n(rst_n),

        .controller_out_valid(controller_out_valid),
        .in_ready(in_ready),
        .in_metadata(in_metadata),
        .FAN_retrans_check_en(FAN_retrans_check_en),
        
        .arrival_state_rd_en(upbroadcast_arrival_rd_en),
        .arrival_state_rd_addr(upbroadcast_arrival_rd_addr),
        .arrival_state_bitmap_in(bram_arrival_rd_data),
        .arrival_state_rd_grant(upbroadcast_arrival_rd_grant),

        .arrival_state_wr_addr(upbroadcast_arrival_wr_addr),
        .arrival_state_wr_en(upbroadcast_arrival_wr_en),
        .arrival_state_wr_data(upbroadcast_arrival_wr_data),
        .arrival_state_wr_grant(upbroadcast_arrival_wr_grant),

        .degree_state_rd_grant(upbroadcast_degree_rd_grant),
        .degree_state_in(bram_degree_rd_data),
        .degree_state_rd_en(upbroadcast_degree_rd_en),
        .degree_state_rd_addr(upbroadcast_degree_rd_addr),

        .out_valid(out_valid),
        .out_ready(out_ready),
        .FAN_retrans_en(FAN_retrans_en),
        .down_broadcast_en(down_broadcast_en),
        .new_slot_en(new_slot_en),
        .FAN_trans_en(FAN_trans_en)
    );

    arrival_state_mem arrival_state_uut (
        .clk(clk),
        .wr_en(arbiter_arrival_wr_en),
        .wr_addr(arbiter_arrival_wr_addr),
        .wr_data(arbiter_arrival_wr_data),

        .rd_en(arbiter_arrival_rd_en),
        .rd_addr(arbiter_arrival_rd_addr),
        .rd_data(bram_arrival_rd_data)
    );

    degree_bram degree_bram_uut (
        .clk(clk),
        .wr_en(0),
        .wr_addr(0),
        .wr_data(0),
       
        .rd_en(arbiter_degree_rd_en),
        .rd_addr(arbiter_degree_rd_addr),
        .rd_data(bram_degree_rd_data)
    );

    bram_write_arbiter arrival_write_arbiter_uut (
        .clk(clk),
        .rst_n(rst_n),
        .req0_wr_en(upbroadcast_arrival_wr_en),
        .req0_wr_addr(upbroadcast_arrival_wr_addr),
        .req0_wr_data(upbroadcast_arrival_wr_data),
        .grant0(upbroadcast_arrival_wr_grant),

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


    bram_read_arbiter arrival_read_arbiter_uut (
        .clk(clk),
        .rst_n(rst_n),
        .req0_rd_en(upbroadcast_arrival_rd_en),
        .req0_rd_addr(upbroadcast_arrival_rd_addr),
        .grant0(upbroadcast_arrival_rd_grant),

        .bram_rd_en(arbiter_arrival_rd_en),
        .bram_rd_addr(arbiter_arrival_rd_addr),

        .req1_rd_en(0),
        .req1_rd_addr(0),
        .grant1(),

        .req2_rd_en(0),
        .req2_rd_addr(0),
        .grant2()

    );

    bram_read_arbiter degree_read_arbiter_uut (
        .clk(clk),
        .rst_n(rst_n),
        .req0_rd_en(upbroadcast_degree_rd_en),
        .req0_rd_addr(upbroadcast_degree_rd_addr),
        .grant0(upbroadcast_degree_rd_grant),

        .bram_rd_en(arbiter_degree_rd_en),
        .bram_rd_addr(arbiter_degree_rd_addr),

        .req1_rd_en(0),
        .req1_rd_addr(0),
        .grant1(),

        .req2_rd_en(0),
        .req2_rd_addr(0),
        .grant2()

    );



endmodule
