`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/09/08 10:28:56
// Design Name: 
// Module Name: fifo_sync
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


module fifo_sync#(
    parameter DATA_WIDTH = 512,
    parameter KEEP_WIDTH = 16,
    parameter DEPTH      = 256
)(
    input   wire                   clk,
    input   wire                   rst_n,

    // AXI-stream
    input   wire                   wr_en,
    input   wire [DATA_WIDTH-1:0]  din,
    input   wire [KEEP_WIDTH-1:0]  kin,
    input   wire                   lin,
    output  wire                   full,

    input   wire                   rd_en,
    output  wire [DATA_WIDTH-1:0]  dout,
    output  wire [KEEP_WIDTH-1:0]  kout,
    output  wire                   lout,
    output  wire                   dout_valid,  
    output  wire                   empty           
);
    localparam ADDR_WIDTH = $clog2(DEPTH);

    localparam MEM_WIDTH = DATA_WIDTH + KEEP_WIDTH + 1;

    reg [MEM_WIDTH-1:0]         mem[0:DEPTH-1];
    reg [ADDR_WIDTH-1:0]        wr_ptr;
    reg [ADDR_WIDTH-1:0]        rd_ptr;
    reg [ADDR_WIDTH:0]          count;

    assign full = (count == DEPTH);
    assign empty = (count == 0);

    assign dout_valid = !empty;

    // assign {lout,kout,dout} = rd_en ? mem[rd_ptr] : 0;
    assign {lout,kout,dout} = mem[rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
        end
        else begin
            if (wr_en && !full) begin
                wr_ptr <= wr_ptr + 1;
            end
            else begin
                wr_ptr <= wr_ptr;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
        end
        else begin
            if (rd_en && !empty) begin
                rd_ptr <= rd_ptr + 1;
            end
            else begin
                rd_ptr <= rd_ptr;
            end
        end
    end


    // write logic 
    always @(posedge clk) begin
        if (wr_en && !full) begin
            mem[wr_ptr] <= {lin,kin,din};
        end
    end


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 0;
        end
        else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b00: count <= count;
                2'b01: count <= count-1;
                2'b10: count <= count+1;
                2'b11: count <= count;
            endcase
        end
    end

endmodule
