`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/18 20:04:33
// Design Name: 
// Module Name: degree_bram
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


module degree_bram #(
    parameter FAN_IN = 2,
    parameter BUFFER_SLOTS = 16,
    parameter BUFFER_SLOTS_WIDTH = $clog2(BUFFER_SLOTS),
    parameter ADDR_WIDTH = 8,
    // parameter DATA_WIDTH = $clog2(FAN_IN) + 1
    parameter DATA_WIDTH = 32

)(
    input wire                              clk,
    
    input wire                              wr_en,
    input wire [ADDR_WIDTH-1:0]             wr_addr,
    input wire [DATA_WIDTH-1:0]             wr_data,

    input wire                              rd_en,
    input wire [ADDR_WIDTH-1:0]             rd_addr,
    output reg [DATA_WIDTH-1:0]             rd_data
);
    reg [DATA_WIDTH-1:0]  mem [0:BUFFER_SLOTS-1];

    initial begin : INIT_MEM
        integer i;

        for (i = 0; i < BUFFER_SLOTS; i = i + 1) begin
            mem[i] = {DATA_WIDTH{1'b0}};            
        end

        rd_data = {DATA_WIDTH{1'b0}}; 
    end


    // write
    always @(posedge clk) begin
        if (wr_en) begin
           mem[wr_addr] <= wr_data; 
        end
    end

    // read
    always @(posedge clk) begin
        if (rd_en) begin
            rd_data <= mem[rd_addr];    
        end
    end
endmodule
