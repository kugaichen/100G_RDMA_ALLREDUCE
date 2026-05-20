`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/09/25 19:46:56
// Design Name: 
// Module Name: arrival_state_mem
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


module arrival_state_mem #(
    parameter BUFFER_SLOTS       = 16, 
    parameter DATA_WIDTH         = 32,
    parameter ADDR_WIDTH         = 8

)(
    input   wire                    clk,
    input   wire                    wr_en,
    input   wire [ADDR_WIDTH-1:0]   wr_addr,
    input   wire [DATA_WIDTH-1:0]   wr_data,

    input   wire [ADDR_WIDTH-1:0]   rd_addr,
    input   wire                    rd_en, 
    output  reg  [DATA_WIDTH-1:0]   rd_data
);
    reg [DATA_WIDTH-1:0]  arrival_state [0:BUFFER_SLOTS-1];

    initial begin : INIT_MEM
        integer i;
        for (i = 0; i < BUFFER_SLOTS; i = i + 1) begin
            arrival_state[i] = {DATA_WIDTH{1'b0}};            
        end

        rd_data = {DATA_WIDTH{1'b0}};
        
    end

    // write
    always @(posedge clk) begin
        if (wr_en) begin
           arrival_state[wr_addr] <= wr_data; 
        end
    end

    // read
    always @(posedge clk) begin
        if (rd_en) begin
            rd_data <= arrival_state[rd_addr];    
        end
        
    end

endmodule
