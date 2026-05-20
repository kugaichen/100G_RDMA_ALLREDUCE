`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/02 11:45:42
// Design Name: 
// Module Name: aggregate_bram
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


module aggregate_bram #(
    parameter BUFFER_SLOTS = 16,
    parameter DATA_WIDTH = 512,
    parameter ADDR_WIDTH = 8

)(
    input wire                              clk,
    
    input wire                              wr_en,
    input wire [DATA_WIDTH-1:0]             wr_data,


    input wire                              rd_en,
    output reg [DATA_WIDTH-1:0]             rd_data
);
    reg [DATA_WIDTH*BUFFER_SLOTS-1:0]  mem;

    // write
    always @(posedge clk) begin
        if (wr_en) begin
           mem <= wr_data; 
        end
    end

    // read
    always @(posedge clk) begin
        rd_data <= mem;    
    end

endmodule
