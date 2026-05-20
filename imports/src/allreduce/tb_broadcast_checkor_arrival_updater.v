`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/21 10:33:45
// Design Name: 
// Module Name: tb_broadcast_checkor_arrival_updater
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


module tb_broadcast_checkor_arrival_updater;
    parameter FAN_IN                = 2;
    parameter BUFFER_SLOTS          = 16;
    parameter BUFFER_SLOTS_WIDTH    = $clog2(BUFFER_SLOTS);
    parameter FAN_IN_WIDTH          = $clog2(FAN_IN);
    parameter DATA_WIDTH            = 32;
    parameter ADDR_WIDTH            = 8;

    reg                  clk;
    reg                  rst_n;

    reg                  controller_out_valid;
    wire                 in_ready;
    reg [3*8-1:0]        in_metadata;
    
    reg                  FAN_retrans_check_en;
    
    // bitmap_rd
    reg     [DATA_WIDTH-1:0]     arrival_state_bitmap_in;
    wire    [ADDR_WIDTH-1:0]     arrival_state_rd_addr;

    // bitmap_wr
    wire    [ADDR_WIDTH-1:0]     arrival_state_wr_addr;
    wire                         arrival_state_wr_en;
    wire    [DATA_WIDTH-1:0]     arrival_state_wr_data;

    // degree_rd
    reg  [DATA_WIDTH-1:0]        degree_state_in;
    wire [ADDR_WIDTH-1:0]        degree_state_rd_addr;


    // out
    wire                         out_valid;
    wire                         FAN_retrans_en;
    wire                         down_broadcast_en;
    wire                         new_slot_en;
    wire                         FAN_trans_en;
    reg                          out_ready;


    reg [DATA_WIDTH-1:0]         arrival_state_bitmap_storage [BUFFER_SLOTS-1:0];
    reg [DATA_WIDTH-1:0]         degree_state_storage [BUFFER_SLOTS-1:0];

    broadcast_checkor_arrival_updater #(
        .FAN_IN(FAN_IN),
        .BUFFER_SLOTS(BUFFER_SLOTS),
        .BUFFER_SLOTS_WIDTH(BUFFER_SLOTS_WIDTH),
        .FAN_IN_WIDTH(FAN_IN_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .controller_out_valid(controller_out_valid),
        .in_ready(in_ready),
        .in_metadata(in_metadata),
        .FAN_retrans_check_en(FAN_retrans_check_en),
        .arrival_state_bitmap_in(arrival_state_bitmap_in),
        .arrival_state_wr_en(arrival_state_wr_en),
        .arrival_state_rd_addr(arrival_state_rd_addr),
        .degree_state_in(degree_state_in),
        .degree_state_rd_addr(degree_state_rd_addr),
        .out_valid(out_valid),
        .FAN_retrans_en(FAN_retrans_en),
        .down_broadcast_en(down_broadcast_en),
        .new_slot_en(new_slot_en),
        .FAN_trans_en(FAN_trans_en),
        .out_ready(out_ready)
    );

    initial begin
        clk = 0;
        forever begin
            #5 clk = ~clk;
        end
    end

    initial begin
        arrival_state_bitmap_storage[2] = 32'h00000003;
        degree_state_storage[2] = 32'h00000001;

        #90;
        arrival_state_bitmap_storage[2] = 32'h00000000;
        degree_state_storage[2] = 32'h00000002;
    end

    // 模拟BRAM
    always @(posedge clk) begin
        arrival_state_bitmap_in <= arrival_state_bitmap_storage[arrival_state_rd_addr];
        degree_state_in <= degree_state_storage[degree_state_rd_addr];
    end

    always @(posedge clk) begin
        if (arrival_state_wr_en) begin
            arrival_state_bitmap_storage[arrival_state_wr_addr] <= arrival_state_wr_data;
        end
    end

     initial begin
        rst_n = 0;
        controller_out_valid = 0;
        in_metadata = 24'b0;


        // @(posedge clk);
        #10;
        rst_n = 1;
        controller_out_valid = 1'b1;
        FAN_retrans_check_en = 1'b0;
        in_metadata[7:0] = 8'h01;
        in_metadata[15:8] = 8'h02;
        in_metadata[16:16] = 1'b1;
        in_metadata[18:17] = 2'b00;

        out_ready = 1;

        // 等待 DUT 接收
        wait (in_ready);
        @(posedge clk);
        controller_out_valid = 1'b0;
        wait (out_valid);


        @(posedge clk);
        controller_out_valid = 1'b1;
        FAN_retrans_check_en = 1'b0;
        in_metadata[7:0] = 8'h02;
        in_metadata[15:8] = 8'h02;
        in_metadata[16:16] = 1'b0;
        in_metadata[18:17] = 2'b00;

        out_ready = 1;


        // 等待 DUT 接收
        wait (in_ready);
        @(posedge clk);
        controller_out_valid = 1'b0;
        wait (out_valid);

        @(posedge clk);
        controller_out_valid = 1'b1;
        FAN_retrans_check_en = 1'b1;
        in_metadata[7:0] = 8'h02;
        in_metadata[15:8] = 8'h02;
        in_metadata[16:16] = 1'b0;
        in_metadata[18:17] = 2'b00;

        out_ready = 1;


        // 等待 DUT 接收
        wait (in_ready);
        @(posedge clk);
        controller_out_valid = 1'b0;
        wait (out_valid);

        @(posedge clk);


  

        $finish;


    end


endmodule
