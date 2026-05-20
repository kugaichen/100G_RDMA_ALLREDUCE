`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/19 15:13:32
// Design Name: 
// Module Name: payload_wr_arbiter
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


module payload_wr_arbiter #(
    parameter ADDR_WIDTH = 8,
    parameter PAYLOAD_ITEM_NUM = 16,
    parameter PAYLOAD_ITEM_WIDTH = 512
)(
    input wire clk,
    input wire rst_n,

    input wire [PAYLOAD_ITEM_NUM-1:0]                           req0_wr_en,
    input wire [ADDR_WIDTH-1:0]                                 req0_wr_addr,
    input wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]        req0_wr_data_pack,
    output reg                                                  grant0,

    input wire [PAYLOAD_ITEM_NUM-1:0]                           req1_wr_en,
    input wire [ADDR_WIDTH-1:0]                                 req1_wr_addr,
    input wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]        req1_wr_data_pack,
    output reg                                                  grant1,

    output wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]       payload_wr_data_pack,
    // output wire [ADDR_WIDTH-1:0]                                payload_wr_addr,
    // output wire [PAYLOAD_ITEM_NUM-1:0]                          payload_wr_en
    output reg [ADDR_WIDTH-1:0]                                 payload_wr_addr,
    output reg [PAYLOAD_ITEM_NUM-1:0]                           payload_wr_en
);

    // 状态机
    localparam IDLE = 2'b00;
    localparam WRITE = 2'b01;

    reg [1:0] state, next_state;
    
    // 辅助信号：检测是否有请求
    wire req0_active = |req0_wr_en;
    wire req1_active = |req1_wr_en;

    // 关键：锁存“当前选中了谁”，用于驱动组合逻辑的数据 MUX
    // 0: None, 1: Req0, 2: Req1
    reg [1:0] sel_req; 


    // 1. 状态机跳转
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= next_state;
    end

    // 2. 下一状态逻辑
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (req0_active) next_state = WRITE;
                else if (req1_active) next_state = WRITE;
            end
            WRITE: begin
                next_state = IDLE;
            end
        endcase
    end

    // 3. 控制信号锁存与输出
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            payload_wr_en <= 0;
            payload_wr_addr <= 0;
            grant0 <= 0;
            grant1 <= 0;
            sel_req <= 0;
        end
        else begin
            case (state)
                IDLE: begin
                    payload_wr_en <= 0;
                    grant0 <= 0;
                    grant1 <= 0;
                    sel_req <= 0; // 默认不选

                    if (req0_active) begin
                        payload_wr_en <= req0_wr_en;   // 锁存使能
                        payload_wr_addr <= req0_wr_addr; // 锁存地址
                        grant0 <= 1;
                        sel_req <= 1; // 记录选中了 Req0
                    end
                    else if (req1_active) begin
                        payload_wr_en <= req1_wr_en;
                        payload_wr_addr <= req1_wr_addr;
                        grant1 <= 1;
                        sel_req <= 2; // 记录选中了 Req1
                    end
                end

                WRITE: begin
                    // 保持一个周期后清除
                    payload_wr_en <= 0;
                    grant0 <= 0;
                    grant1 <= 0;
                    // sel_req 保持不变，或者在这里清零也可以，
                    // 但为了数据稳定，建议保持直到回到 IDLE
                end
            endcase
        end
    end

    assign payload_wr_data_pack = (sel_req == 1) ? req0_wr_data_pack :
                                  (sel_req == 2) ? req1_wr_data_pack : 
                                  {(PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH){1'b0}};


    // always @(posedge clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         grant0 <= 0;
    //         grant1 <= 0;
    //     end
    //     else begin
    //         if (req0_wr_en) begin
    //             grant0 <= 1'b1;
    //             grant1 <= 1'b0;
    //         end
    //         else if (req1_wr_en) begin
    //             grant0 <= 1'b0;
    //             grant1 <= 1'b1;
    //         end
    //         else begin
    //             grant0 <= 1'b0;
    //             grant1 <= 1'b0;
    //         end
    //     end
    // end

    // assign payload_wr_data_pack = grant0 ? req0_wr_data_pack : grant1 ? req1_wr_data_pack : 0;
    // assign payload_wr_addr = grant0 ? req0_wr_addr : grant1 ? req1_wr_addr : {ADDR_WIDTH{1'b0}};
    // assign paylaod_wr_en = grant0 ? req0_wr_en : grant1 ? req1_wr_en : {PAYLOAD_ITEM_NUM{1'b0}};
endmodule
