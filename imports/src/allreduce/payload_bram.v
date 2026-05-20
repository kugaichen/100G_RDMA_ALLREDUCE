`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/10 17:28:21
// Design Name: 
// Module Name: payload_bram
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


module payload_bram #(
    parameter USE_LUTRAM = 0, // 新增参数：0=BRAM, 1=LUTRAM
    parameter BUFFER_SLOTS = 16,
    parameter DATA_WIDTH = 512,
    parameter ADDR_WIDTH = 8

)(
    input wire                              clk,
    
    input wire                              wr_en,
    input wire [ADDR_WIDTH-1:0]             wr_addr,
    input wire [DATA_WIDTH-1:0]             wr_data,


    input wire                              rd_en,
    input wire [ADDR_WIDTH-1:0]             rd_addr,
    output reg [DATA_WIDTH-1:0]             rd_data
);
    
    generate
        if (USE_LUTRAM) begin: gen_lutram
            (* ram_style = "distributed" *)
            reg [DATA_WIDTH-1:0] mem [0:BUFFER_SLOTS-1];

            integer k;
            initial begin
                for (k = 0; k<BUFFER_SLOTS; k = k +1) begin
                    mem[k] = 0;
                end

                rd_data = {DATA_WIDTH{1'b0}};
            end

            always @(posedge clk) begin
                if (wr_en) mem[wr_addr] <= wr_data;
            end
            always @(posedge clk) begin
                if (rd_en) rd_data <= mem[rd_addr];
            end
            
        end

        else begin: gen_bram
            (* ram_style = "block" *)
            reg [DATA_WIDTH-1:0] mem [0:BUFFER_SLOTS-1];

            integer k;
            initial begin
                for (k = 0; k<BUFFER_SLOTS; k = k +1) begin
                    mem[k] = 0;
                end

                rd_data = {DATA_WIDTH{1'b0}};
            end

             always @(posedge clk) begin
                if (wr_en) mem[wr_addr] <= wr_data;
            end
            always @(posedge clk) begin
                if (rd_en) rd_data <= mem[rd_addr];
            end
        end
    endgenerate



    // reg [DATA_WIDTH-1:0]  mem [0:BUFFER_SLOTS-1];

    // // 初始化逻辑
    // integer i;
    // initial begin
    //     // 1. 初始化存储阵列
    //     for (i = 0; i < BUFFER_SLOTS; i = i + 1) begin
    //         mem[i] = {DATA_WIDTH{1'b0}};
    //     end
        
    //     // 2. 关键：初始化输出寄存器
    //     // 如果不加这一行，在第一次读操作完成前，输出端口仍然是 X
    //     rd_data = {DATA_WIDTH{1'b0}};
    // end

    // // write
    // always @(posedge clk) begin
    //     if (wr_en) begin
    //        mem[wr_addr] <= wr_data; 
    //     end
    // end

    // // read
    // always @(posedge clk) begin
    //     if (rd_en) begin
    //         rd_data <= mem[rd_addr];    
    //     end    
    // end

endmodule
