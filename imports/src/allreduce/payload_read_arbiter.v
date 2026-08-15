`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/19 12:20:48
// Design Name: 
// Module Name: payload_read_arbiter
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


module payload_read_arbiter #(
    parameter ADDR_WIDTH = 8,
    parameter PAYLOAD_ITEM_NUM = 16
)(
    input wire clk,
    input wire rst_n,

    input wire [PAYLOAD_ITEM_NUM-1:0]                               req0_rd_en,
    input wire [ADDR_WIDTH-1:0]                                     req0_rd_addr,
    output reg                                                      grant0,

    input wire [PAYLOAD_ITEM_NUM-1:0]                               req1_rd_en,
    input wire [ADDR_WIDTH-1:0]                                     req1_rd_addr,
    output reg                                                      grant1,

    input wire [PAYLOAD_ITEM_NUM-1:0]                               req2_rd_en,
    input wire [ADDR_WIDTH-1:0]                                     req2_rd_addr,
    output reg                                                      grant2,
    
    output reg [PAYLOAD_ITEM_NUM-1:0]                              payload_rd_en,
    output reg [ADDR_WIDTH-1:0]                                    payload_rd_addr
);

    // 状态机
    localparam IDLE = 2'b00;
    localparam READ = 2'b01;

    reg [1:0] state;
    reg [1:0] next_state;

    // 辅助信号：检测是否有任意一位为高
    wire req0_active = |req0_rd_en;
    wire req1_active = |req1_rd_en;
    wire req2_active = |req2_rd_en;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (req0_active) next_state = READ;
                else if (req1_active) next_state = READ;
                else if (req2_active) next_state = READ;
            end
            READ: begin
                next_state = IDLE;
            end
        endcase
    end

    // 输出逻辑：锁存输出，确保读使能宽度足够
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            payload_rd_en <= 0;
            payload_rd_addr <= 0;
            grant0 <= 0;
            grant1 <= 0;
            grant2 <= 0;
        end
        else begin
            case (state)
                IDLE: begin
                    payload_rd_en <= 0;
                    grant0 <= 0;
                    grant1 <= 0;
                    grant2 <= 0;

                    if (req0_active) begin
                        payload_rd_en <= req0_rd_en; // 锁存请求向量
                        payload_rd_addr <= req0_rd_addr;
                        grant0 <= 1;
                    end
                    else if (req1_active) begin
                        payload_rd_en <= req1_rd_en; // 锁存请求向量
                        payload_rd_addr <= req1_rd_addr;
                        grant1 <= 1;
                    end
                    else if (req2_active) begin
                        payload_rd_en <= req2_rd_en;
                        payload_rd_addr <= req2_rd_addr;
                        grant2 <= 1;
                    end
                end

                READ: begin
                    // 保持一个周期后清除
                    payload_rd_en <= 0;
                    grant0 <= 0;
                    grant1 <= 0;
                    grant2 <= 0;
                end
            endcase
        end
    end
    // always @(posedge clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         grant0 <= 0;
    //         grant1 <= 0;

    //     end
    //     else begin
    //         if (req0_rd_en) begin
    //             grant0 <= 1'b1;
    //             grant1 <= 1'b0;
        
    //         end

    //         else if (req1_rd_en) begin
    //             grant0 <= 1'b0;
    //             grant1 <= 1'b1;
    
    //         end



    //         else begin
    //             grant0 <= 0;
    //             grant1 <= 0;
    //         end
    //     end
    // end

    // assign payload_rd_addr = grant0 ? req0_rd_addr : grant1 ? req1_rd_addr : 0;
    // assign payload_rd_en = grant0 ? req0_rd_en : grant1 ? req1_rd_en : 0;
endmodule
