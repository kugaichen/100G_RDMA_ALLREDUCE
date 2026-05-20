`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/09/24 21:19:25
// Design Name: 
// Module Name: tb_retrans_checkor_arrival_updater
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


module tb_retrans_checkor_arrival_updater;
    
    parameter FAN_IN               = 2;
    parameter BUFFER_SLOTS         = 16;
    parameter BUFFER_SLOTS_WIDTH   = $clog2(BUFFER_SLOTS);
    parameter FAN_IN_WIDTH         = $clog2(FAN_IN);
    parameter DATA_WIDTH           = 32;
    parameter ADDR_WIDTH           = 8;

    // Inputs
    reg             clk;
    reg             rst_n;


    reg             in_valid;
    wire            in_ready;
    reg [3*8-1:0]   in_metadata;

    wire [ADDR_WIDTH-1:0]       arrival_state_rd_addr;
    reg  [DATA_WIDTH-1:0]       arrival_state_bitmap_in;

    wire [ADDR_WIDTH-1:0]       arrival_state_wr_addr;
    wire                        arrival_state_wr_en;
    wire [DATA_WIDTH-1:0]       arrival_state_wr_data;

    wire            out_valid;
    reg             out_ready;
    wire            aggregate_buffer_en;
    wire            read_buffer_en;
    wire            FAN_retrans_check_en;

    reg  [DATA_WIDTH-1:0]       degree_state_in;
    wire [ADDR_WIDTH-1:0]       degree_state_rd_addr;
    wire [ADDR_WIDTH-1:0]       degree_state_wr_addr;
    wire [DATA_WIDTH-1:0]       degree_state_wr_data;
    wire                        degree_state_wr_en;                                    


    reg [DATA_WIDTH-1:0]   arrival_state_bitmap_storage [BUFFER_SLOTS-1:0];
    reg [DATA_WIDTH-1:0]   degree_state_storage [BUFFER_SLOTS-1:0];

    retrans_checkor_arrival_updater #(
        .FAN_IN(FAN_IN), .BUFFER_SLOTS(BUFFER_SLOTS), .BUFFER_SLOTS_WIDTH(BUFFER_SLOTS_WIDTH),
        .FAN_IN_WIDTH(FAN_IN_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ADDR_WDITH(ADDR_WDITH)
    ) uut(
        .clk(clk), 
        .rst_n(rst_n), 
        .in_valid(in_valid), 
        .in_ready(in_ready),
        .in_metadata(in_metadata),
        .arrival_state_bitmap_in(arrival_state_bitmap_in),
        .arrival_state_rd_addr(arrival_state_rd_addr),
        .arrival_state_wr_addr(arrival_state_wr_addr),
        .arrival_state_wr_en(arrival_state_wr_en),
        .arrival_state_wr_data(arrival_state_wr_data),
        .out_valid(out_valid), 
        .out_ready(out_ready),
        .aggregate_buffer_en(aggregate_buffer_en), 
        .read_buffer_en(read_buffer_en),
        .FAN_retrans_check_en(FAN_retrans_check_en),
        .degree_state_in(degree_state_in),
        .degree_state_rd_addr(degree_state_rd_addr),
        .degree_state_wr_addr(degree_state_wr_addr),
        .degree_state_wr_data(degree_state_wr_date),
        .degree_state_wr_en(degree_state_wr_en)
    );

    initial begin
        clk = 0;
        forever begin
            #5 clk = ~clk;
        end
    end

    initial begin
        arrival_state_bitmap_storage[2] = 32'h00000001; 
        degree_state_storage[2] = 32'h00000000;
    end

    // 模拟BRAM
    always @(posedge clk) begin
        arrival_state_bitmap_in <= arrival_state_bitmap_storage[arrival_state_rd_addr];
        degree_state_in <= degree_state_storage[arrival_state_rd_addr];
    end

    always @(posedge clk) begin
        if (arrival_state_wr_en) begin
            arrival_state_bitmap_storage[arrival_state_wr_addr] <= arrival_state_wr_data;
        end

        if (degree_state_wr_en) begin
           degree_state_storage[arrival_state_wr_addr] <= degree_state_wr_data; 
        end
    end


    initial begin
        rst_n = 0;
        in_valid = 0;
        in_metadata = 24'b0;


        @(posedge clk);
        rst_n = 1;
        in_metadata[7:0] = 8'h01;
        in_metadata[15:8] = 8'h02;
        in_metadata[16:16] = 1'b1;
        in_metadata[18:17] = 2'b00;

        in_valid <= 1'b1;
        out_ready = 1;

        // 等待 DUT 接收
        wait (in_ready);
        @(posedge clk);
        in_valid <= 1'b0;
        wait (out_valid);


        @(posedge clk);
        in_metadata[7:0] = 8'h02;
        in_metadata[15:8] = 8'h02;
        in_metadata[16:16] = 1'b1;
        in_metadata[18:17] = 2'b00;
        in_valid <= 1'b1;

        // 等待 DUT 接收
        wait (in_ready);
        @(posedge clk);
        in_valid <= 1'b0;
        wait (out_valid);

        @(posedge clk);
        in_metadata[7:0] = 8'h01;
        in_metadata[15:8] = 8'h02;
        in_metadata[16:16] = 1'b1;
        in_metadata[18:17] = 2'b00;
        in_valid <= 1'b1;

        // 等待 DUT 接收
        wait (in_ready);
        @(posedge clk);
        in_valid <= 1'b0;
        wait (out_valid);

        @(posedge clk);


  

        $finish;


    end

endmodule
