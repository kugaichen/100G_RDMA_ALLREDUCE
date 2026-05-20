`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/14 11:05:54
// Design Name: 
// Module Name: tb_bram_write_demux
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


module tb_bram_write_demux;
    localparam PARALLEL_NUM = 16;
    localparam SLOT_ADDR_WIDTH = 8;
    localparam ITEM_ADDR_WIDTH = $clog2(PARALLEL_NUM);
    localparam PAYLOAD_ITEM_WIDTH = 512;

    reg                                         parser_wr_en;
    reg [SLOT_ADDR_WIDTH+ITEM_ADDR_WIDTH-1:0]   parser_wr_addr;
    reg [PAYLOAD_ITEM_WIDTH-1:0]                parser_wr_data;

    wire [SLOT_ADDR_WIDTH-1:0]                   parallel_wr_addr;
    wire [PARALLEL_NUM-1:0]                      parallel_wr_en;
    wire [PAYLOAD_ITEM_WIDTH-1:0]                parallel_wr_data;

    bram_write_demux #(
        .PARALLEL_NUM(PARALLEL_NUM), .SLOT_ADDR_WIDTH(SLOT_ADDR_WIDTH),
        .ITEM_ADDR_WIDTH(ITEM_ADDR_WIDTH), .PAYLOAD_ITEM_WIDTH(PAYLOAD_ITEM_WIDTH)
    ) bram_write_demux_init (
        .parser_wr_en(parser_wr_en), .parser_wr_addr(parser_wr_addr),
        .parser_wr_data(parser_wr_data), .parallel_wr_addr(parallel_wr_addr),
        .parallel_wr_en(parallel_wr_en), .parallel_wr_data(parallel_wr_data)
    );


    initial begin
        parser_wr_en = 1;
        parser_wr_data = 1;
        parser_wr_addr = {12'b0000_0001_0001};

        #10
        parser_wr_en = 1;
        parser_wr_data = 1;
        parser_wr_addr = {12'b0000_0001_0010};

        #10
        parser_wr_en = 1;
        parser_wr_data = 1;
        parser_wr_addr = {12'b0000_0001_0110};

        #10
        parser_wr_en = 1;
        parser_wr_data = 1;
        parser_wr_addr = {12'b0000_0001_1111};

        #10
        parser_wr_en = 1;
        parser_wr_data = 1;
        parser_wr_addr = {12'b0000_0011_0010};
        
        #10
        parser_wr_en = 1;
        parser_wr_data = 1;
        parser_wr_addr = {12'b0000_1111_1111};

        $finish;
    end
endmodule
