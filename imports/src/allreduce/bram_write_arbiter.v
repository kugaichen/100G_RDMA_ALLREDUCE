`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/23 19:16:48
// Design Name: 
// Module Name: bram_write_arbiter
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


module bram_write_arbiter#(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32    
)(
    input wire clk,
    input wire rst_n,

    input wire                      req0_wr_en,
    input wire [ADDR_WIDTH-1:0]     req0_wr_addr,
    input wire [DATA_WIDTH-1:0]     req0_wr_data,
    output reg                      grant0,

    input wire                      req1_wr_en,
    input wire [ADDR_WIDTH-1:0]     req1_wr_addr,
    input wire [DATA_WIDTH-1:0]     req1_wr_data,
    output reg                      grant1,

    input wire                      req2_wr_en,
    input wire [ADDR_WIDTH-1:0]     req2_wr_addr,
    input wire [DATA_WIDTH-1:0]     req2_wr_data,
    output reg                      grant2,

    input wire                      req3_wr_en,
    input wire [ADDR_WIDTH-1:0]     req3_wr_addr,
    input wire [DATA_WIDTH-1:0]     req3_wr_data,
    output reg                      grant3,

    input wire                      req4_wr_en,
    input wire [ADDR_WIDTH-1:0]     req4_wr_addr,
    input wire [DATA_WIDTH-1:0]     req4_wr_data,
    output reg                      grant4,

    output reg                      bram_wr_en,
    output reg [ADDR_WIDTH-1:0]     bram_wr_addr,
    output reg [DATA_WIDTH-1:0]     bram_wr_data
    
);

    // 状态机
    localparam IDLE = 2'b00;
    localparam WRITE = 2'b01;

    reg [1:0]   state;
    reg [1:0]   next_state;

    reg latched_wr_en;
    reg [ADDR_WIDTH-1:0]    latched_wr_addr;
    reg [DATA_WIDTH-1:0]    latched_wr_data;
    reg [1:0]               selected_req;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end
        else begin
            state <= next_state;
        end
            
    end

    always @( *) begin
        next_state = state;
        case (state)
            IDLE: begin
                // 优先级仲裁：0 > 1 > 2 > 3
                if (req0_wr_en) next_state = WRITE;
                else if (req1_wr_en) next_state = WRITE;
                else if (req2_wr_en) next_state = WRITE;
                else if (req3_wr_en) next_state = WRITE;
                else if (req4_wr_en) next_state = WRITE;
            end

            WRITE: begin
                next_state = IDLE;
            end
        endcase
    end

     // 3. 数据锁存与输出逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bram_wr_en <= 0;
            bram_wr_addr <= 0;
            bram_wr_data <= 0;
            grant0 <= 0;
            grant1 <= 0;
            grant2 <= 0;
            grant3 <= 0;
            grant4 <= 0;
        end
        else begin
            case (state)
                IDLE: begin
                    bram_wr_en <= 0; // 默认不写
                    grant0 <= 0;
                    grant1 <= 0;
                    grant2 <= 0;
                    grant3 <= 0;
                    grant4 <= 0;

                    // 在 IDLE 状态下捕获请求并锁存数据
                    if (req0_wr_en) begin
                        bram_wr_en <= 1;
                        bram_wr_addr <= req0_wr_addr;
                        bram_wr_data <= req0_wr_data;
                        grant0 <= 1; // 立即给出 Grant
                    end
                    else if (req1_wr_en) begin
                        bram_wr_en <= 1;
                        bram_wr_addr <= req1_wr_addr;
                        bram_wr_data <= req1_wr_data;
                        grant1 <= 1;
                    end
                    else if (req2_wr_en) begin
                        bram_wr_en <= 1;
                        bram_wr_addr <= req2_wr_addr;
                        bram_wr_data <= req2_wr_data;
                        grant2 <= 1;
                    end
                    else if (req3_wr_en) begin
                        bram_wr_en <= 1;
                        bram_wr_addr <= req3_wr_addr;
                        bram_wr_data <= req3_wr_data;
                        grant3 <= 1;
                    end
                    else if (req4_wr_en) begin
                        bram_wr_en <= 1;
                        bram_wr_addr <= req4_wr_addr;
                        bram_wr_data <= req4_wr_data;
                        grant4 <= 1;
                    end
                end

                WRITE: begin
                    // 在 WRITE 状态保持一个周期，确保 BRAM 写入
                    // 此时 Grant 已经发出，上游可以撤销请求了
                    // 下一个周期回到 IDLE，bram_wr_en 会变回 0
                    bram_wr_en <= 0; 
                    grant0 <= 0;
                    grant1 <= 0;
                    grant2 <= 0;
                    grant3 <= 0;
                    grant4 <= 0;
                end
            endcase
        end
    end




    // always @(posedge clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         grant0 <= 0;
    //         grant1 <= 0;
    //         grant2 <= 0;
    //         grant3 <= 0;
    //     end
    //     else begin
    //         if (req0_wr_en) begin
    //             grant0 <= 1'b1;
    //             grant1 <= 1'b0;
    //             grant2 <= 1'b0;
    //             grant3 <= 1'b0;
    //         end

    //         else if (req1_wr_en) begin
    //             grant0 <= 1'b0;
    //             grant1 <= 1'b1;
    //             grant2 <= 1'b0;
    //             grant3 <= 1'b0;
    //         end

    //         else if (req2_wr_en) begin
    //             grant0 <= 1'b0;
    //             grant1 <= 1'b0;
    //             grant2 <= 1'b1;
    //             grant3 <= 1'b0;
    //         end

            
    //         else if (req3_wr_en) begin
    //             grant0 <= 1'b0;
    //             grant1 <= 1'b0;
    //             grant2 <= 1'b0;
    //             grant3 <= 1'b1;
    //         end

    //         else begin
    //             grant0 <= 0;
    //             grant1 <= 0;
    //             grant2 <= 0;
    //             grant3 <= 0;
    //         end
    //     end
    // end

    // assign bram_wr_en   = grant0 ? req0_wr_en : grant1 ? req1_wr_en : grant2 ? req2_wr_en : grant3 ? req2_wr_en : 0;
    // assign bram_wr_addr = grant0 ? req0_wr_addr : grant1 ? req1_wr_addr : grant2 ? req2_wr_addr : grant3 ? req3_wr_addr : 0;
    // assign bram_wr_data = grant0 ? req0_wr_data : grant1 ? req1_wr_data : grant2 ? req2_wr_data : grant3 ? req3_wr_data : 0;
endmodule
