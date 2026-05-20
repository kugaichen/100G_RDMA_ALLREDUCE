`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/22 15:55:52
// Design Name: 
// Module Name: tb_down_broadcast_checkor_arrival_updater
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


module tb_down_broadcast_checkor_arrival_updater;
    parameter PAYLOAD_ITEM_NUM      = 16;
    parameter PAYLOAD_ITEM_WIDTH    = 512;
    parameter FAN_IN                = 2;
    parameter BUFFER_SLOTS          = 16;
    parameter BUFFER_SLOTS_WIDTH    = $clog2(BUFFER_SLOTS);
    parameter FAN_IN_WIDTH          = $clog2(FAN_IN);
    parameter DATA_WIDTH            = 32;
    parameter ADDR_WIDTH            = 8;

    reg                     clk;
    reg                     rst_n;

    reg                     in_valid;
    wire                    in_ready;
    reg [3*8-1:0]           in_metadata;

    wire [ADDR_WIDTH-1:0]   arrival_state_rd_addr;
    reg  [DATA_WIDTH-1:0]   arrival_state_bitmap_in;

    wire [ADDR_WIDTH-1:0]   arrival_state_wr_addr;
    wire                    arrival_state_wr_en;
    wire [DATA_WIDTH-1:0]   arrival_state_wr_data;

    wire                    out_valid;
    reg                     out_ready;
    wire                    copy_buffer_en;
    wire                    down_broadcast_en;



    reg [DATA_WIDTH-1:0]         arrival_state_bitmap_storage [BUFFER_SLOTS-1:0];
    reg [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0] aggregate_bram_storage;  

    // copy payload
    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram_storage [0:PAYLOAD_ITEM_NUM-1][0:BUFFER_SLOTS-1];
    wire [ADDR_WIDTH-1:0]         payload_wr_addr = arrival_state_wr_addr;


    down_broadcast_checkor_arrival_updater #(
        .PAYLOAD_ITEM_NUM(PAYLOAD_ITEM_NUM),
        .PAYLOAD_ITEM_WIDTH(PAYLOAD_ITEM_WIDTH),
        .FAN_IN(FAN_IN),
        .BUFFER_SLOTS(BUFFER_SLOTS),
        .BUFFER_SLOTS_WIDTH(BUFFER_SLOTS_WIDTH),
        .FAN_IN_WIDTH(FAN_IN_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_metadata(in_metadata),
        .arrival_state_rd_addr(arrival_state_rd_addr),
        .arrival_state_bitmap_in(arrival_state_bitmap_in),
        .arrival_state_wr_addr(arrival_state_wr_addr),
        .arrival_state_wr_en(arrival_state_wr_en),
        .arrival_state_wr_data(arrival_state_wr_data),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .copy_buffer_en(copy_buffer_en),
        .down_broadcast_en(down_broadcast_en)
    );

    initial begin
        clk = 0;
        forever begin
            #5 clk = ~clk;
        end
    end

    integer j;
    integer k;

    // 模拟BRAM
    always @(posedge clk) begin
        arrival_state_bitmap_in <= arrival_state_bitmap_storage[arrival_state_rd_addr];
    end

    always @(posedge clk) begin
        if (arrival_state_wr_en) begin
            arrival_state_bitmap_storage[arrival_state_wr_addr] <= arrival_state_wr_data;
        end
    end

    always @( *) begin
        if (copy_buffer_en) begin
            for (k = 0; k < PAYLOAD_ITEM_NUM; k = k + 1) begin
                payload_bram_storage[k][payload_wr_addr] <= aggregate_bram_storage[PAYLOAD_ITEM_WIDTH*(k+1)-1 -: PAYLOAD_ITEM_WIDTH];
            end
        end
    end

    initial begin
        rst_n = 1'b0;
        in_valid = 1'b0;
        arrival_state_bitmap_in = 0;
        in_metadata = 0;

        arrival_state_bitmap_storage[2] = 32'h00000003; 

        for (j = 0; j < PAYLOAD_ITEM_NUM; j = j + 1) begin
            aggregate_bram_storage[PAYLOAD_ITEM_WIDTH*(j+1)-1 -: PAYLOAD_ITEM_WIDTH] = j + 1;
        end

        # 5;
        rst_n = 1'b1;
        in_valid = 1'b1;
        in_metadata[7:0] = 8'h01;
        in_metadata[15:8] = 8'h02;
        in_metadata[16:16] = 1'b1;
        in_metadata[18:17] = 2'b00;

        // 等待 DUT 接收
        wait (in_ready);
        @(posedge clk);
        in_valid = 1'b0;
        wait (out_valid);

        @(posedge clk);
        @(posedge clk); 

        $finish;
    end



endmodule
