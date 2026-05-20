`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/25 12:49:16
// Design Name: 
// Module Name: bram_read_arbiter
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


module bram_read_arbiter #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32    
)(
    input wire clk,
    input wire rst_n,

    input wire                      req0_rd_en,
    input wire [ADDR_WIDTH-1:0]     req0_rd_addr,
    output reg                      grant0,

    input wire                      req1_rd_en,
    input wire [ADDR_WIDTH-1:0]     req1_rd_addr,
    output reg                      grant1,

    input wire                      req2_rd_en,
    input wire [ADDR_WIDTH-1:0]     req2_rd_addr,
    output reg                      grant2,

    output reg                      bram_rd_en,
    output reg [ADDR_WIDTH-1:0]     bram_rd_addr
    
);

    // 状态机
    localparam IDLE = 2'b00;
    localparam READ = 2'b01;

    reg [1:0]   state;
    reg [1:0]   next_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end
        else begin
            state <= next_state;
        end
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (req0_rd_en) next_state = READ;
                else if (req1_rd_en) next_state = READ;
                else if (req2_rd_en) next_state = READ;
            end

            READ: begin
                next_state = IDLE;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bram_rd_en <= 0;
            bram_rd_addr <= 0;
            grant0 <= 0;
            grant1 <= 0;
            grant2 <= 0;
        end

        else begin
            case (state)
                IDLE: begin
                    bram_rd_en <= 0;
                    grant0 <= 0;
                    grant1 <= 0;
                    grant2 <= 0;
                

                    if (req0_rd_en) begin
                        bram_rd_en <= 1;
                        bram_rd_addr <= req0_rd_addr;
                        grant0 <= 1;
                    end
                    else if (req1_rd_en) begin
                        bram_rd_en <= 1;
                        bram_rd_addr <= req1_rd_addr;
                        grant1 <= 1;
                    end
                    else if (req2_rd_en) begin
                        bram_rd_en <= 1;
                        bram_rd_addr <= req2_rd_addr;
                        grant2 <= 1;
                    end
                end 
                
                READ: begin
                    bram_rd_en <= 0;
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
    //         grant2 <= 0;
    //     end
    //     else begin
    //         if (req0_rd_en) begin
    //             grant0 <= 1'b1;
    //             grant1 <= 1'b0;
    //             grant2 <= 1'b0;
    //         end

    //         else if (req1_rd_en) begin
    //             grant0 <= 1'b0;
    //             grant1 <= 1'b1;
    //             grant2 <= 1'b0;
    //         end

    //         else if (req2_rd_en) begin
    //             grant0 <= 1'b0;
    //             grant1 <= 1'b0;
    //             grant2 <= 1'b1;
    //         end

    //         else begin
    //             grant0 <= 0;
    //             grant1 <= 0;
    //             grant2 <= 0;
    //         end
    //     end
    // end

    // assign bram_rd_en = grant0 ? req0_rd_en : grant1 ? req1_rd_en : grant2 ? req2_rd_en : 0;
    // assign bram_rd_addr = grant0 ? req0_rd_addr : grant1 ? req1_rd_addr : grant2 ? req2_rd_addr : 0;
    
endmodule
