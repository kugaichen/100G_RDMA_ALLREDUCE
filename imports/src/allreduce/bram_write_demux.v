`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/13 21:34:56
// Design Name: 
// Module Name: bram_write_demux
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


module bram_write_demux #(
    parameter PARALLEL_NUM = 16,
    parameter SLOT_ADDR_WIDTH = 8,
    parameter ITEM_ADDR_WIDTH = $clog2(PARALLEL_NUM),
    parameter PAYLOAD_ITEM_WIDTH = 512
)(
    input wire                                              parser_wr_en,
    input wire [SLOT_ADDR_WIDTH + ITEM_ADDR_WIDTH - 1: 0]   parser_wr_addr,
    input wire [PAYLOAD_ITEM_WIDTH-1:0]                     parser_wr_data,

    output wire [SLOT_ADDR_WIDTH-1:0]                       parallel_wr_addr,
    output wire [PARALLEL_NUM-1:0]                          parallel_wr_en,
    output wire [PAYLOAD_ITEM_WIDTH-1:0]                    parallel_wr_data
);

    wire [SLOT_ADDR_WIDTH-1:0]  slot_addr_solo = parser_wr_addr[SLOT_ADDR_WIDTH + ITEM_ADDR_WIDTH-1:ITEM_ADDR_WIDTH];
    wire [ITEM_ADDR_WIDTH-1:0]  item_addr_solo = parser_wr_addr[ITEM_ADDR_WIDTH-1:0];

    assign parallel_wr_addr = slot_addr_solo;
    assign parallel_wr_data = parser_wr_data;

    genvar i;
    generate
        for (i = 0; i < PARALLEL_NUM; i = i + 1) begin
            assign parallel_wr_en[i] = parser_wr_en && (item_addr_solo == i);
        end
    endgenerate
endmodule
