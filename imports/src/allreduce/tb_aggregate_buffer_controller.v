`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/12 10:17:33
// Design Name: 
// Module Name: tb_aggregate_buffer_controller
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


module tb_aggregate_buffer_controller;

    localparam PAYLOAD_ITEM_NUM = 16;
    localparam PAYLOAD_ITEM_WIDTH = 512;
    localparam PAYLOAD_ITEM_COUNT_WIDTH = $clog2(PAYLOAD_ITEM_NUM);

    localparam SLOTS_WIDTH = 8;
    localparam BUFFER_SLOTS = 16;
    localparam METADATA_LEN = 2*8+3+5;
    localparam RING_SLOT_WIDTH = 16;


    reg clk;
    reg rst_n;

    reg aggregate_buffer_en;
    reg read_buffer_en;

    reg [METADATA_LEN-1:0]  metadata_in;
    reg                     controller_in_ready;
    wire                    controller_out_ready;

    // payload_bram_rd
    reg [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]  payload_bram_rd_vector_pack;
    reg                                            payload_bram_rd_valid;
    wire [SLOTS_WIDTH-1:0]                         payload_bram_rd_addr;

    // payload_B
    reg [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]  aggregate_bram_rd_vector_pack;
    reg                                            aggregate_bram_rd_valid;


    wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0] updated_aggregate_bram_wr_vector_pack;
    wire                                           updated_aggregate_bram_wr_en;


    aggregate_buffer_controller #(
        .PAYLOAD_ITEM_NUM(PAYLOAD_ITEM_NUM), .PAYLOAD_ITEM_WIDTH(PAYLOAD_ITEM_WIDTH),
        .PAYLOAD_ITEM_COUNT_WIDTH(PAYLOAD_ITEM_COUNT_WIDTH), .METADATA_LEN(METADATA_LEN),
        .SLOTS_WIDTH(SLOTS_WIDTH), .BUFFER_SLOTS(BUFFER_SLOTS), .RING_SLOT_WIDTH(RING_SLOT_WIDTH)
    ) uut (
        .clk(clk), .rst_n(rst_n), .aggregate_buffer_en(aggregate_buffer_en),
        .read_buffer_en(read_buffer_en), .metadata_in(metadata_in), .controller_in_ready(controller_in_ready),
        .controller_out_ready(controller_out_ready), .payload_bram_rd_vector_pack(payload_bram_rd_vector_pack),
        .payload_bram_rd_valid(payload_bram_rd_valid), .payload_bram_rd_addr(payload_bram_rd_addr),
        .aggregate_bram_rd_vector_pack(aggregate_bram_rd_vector_pack), .aggregate_bram_rd_valid(aggregate_bram_rd_valid),
        .updated_aggregate_bram_wr_vector_pack(updated_aggregate_bram_wr_vector_pack), 
        .updated_aggregate_bram_wr_en(updated_aggregate_bram_wr_en)
    );

    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram_storage_0 [PAYLOAD_ITEM_NUM-1:0];
    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram_storage_1 [PAYLOAD_ITEM_NUM-1:0];
    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram_storage_2 [PAYLOAD_ITEM_NUM-1:0];
    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram_storage_3 [PAYLOAD_ITEM_NUM-1:0];
    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram_storage_4 [PAYLOAD_ITEM_NUM-1:0];
    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram_storage_5 [PAYLOAD_ITEM_NUM-1:0];
    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram_storage_6 [PAYLOAD_ITEM_NUM-1:0];
    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram_storage_7 [PAYLOAD_ITEM_NUM-1:0];
    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram_storage_8 [PAYLOAD_ITEM_NUM-1:0];
    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram_storage_9 [PAYLOAD_ITEM_NUM-1:0];
    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram_storage_10 [PAYLOAD_ITEM_NUM-1:0];
    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram_storage_11 [PAYLOAD_ITEM_NUM-1:0];
    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram_storage_12 [PAYLOAD_ITEM_NUM-1:0];
    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram_storage_13 [PAYLOAD_ITEM_NUM-1:0];
    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram_storage_14 [PAYLOAD_ITEM_NUM-1:0];
    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram_storage_15 [PAYLOAD_ITEM_NUM-1:0];

    // reg [PAYLOAD_ITEM_WIDTH-1:0] aggregate_bram_storage [PAYLOAD_ITEM_NUM-1:0];
    reg [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0] aggregate_bram_storage;
    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram_storage [0:PAYLOAD_ITEM_NUM-1][0:BUFFER_SLOTS-1];

    integer i;
    always @(posedge clk) begin
        if (controller_out_ready) begin // DUT is requesting a read
            for (i = 0; i < PAYLOAD_ITEM_NUM; i = i + 1) begin
                payload_bram_rd_vector_pack[PAYLOAD_ITEM_WIDTH*(i+1)-1 -: PAYLOAD_ITEM_WIDTH] <= payload_bram_storage[i][payload_bram_rd_addr];
            end
            payload_bram_rd_valid <= 1'b1;
        end else begin
            payload_bram_rd_valid <= 1'b0;
        end
    end

    always @(posedge clk) begin
        // Read logic
        if (controller_out_ready) begin // DUT is requesting a read
            aggregate_bram_rd_vector_pack <= aggregate_bram_storage;
            aggregate_bram_rd_valid <= 1'b1;
        end else begin
            aggregate_bram_rd_valid <= 1'b0;
        end

        // Write logic
        if (updated_aggregate_bram_wr_en) begin
            aggregate_bram_storage <= updated_aggregate_bram_wr_vector_pack;
        end
    end

    initial begin
        clk = 0;

        forever begin
            #5 clk = ~clk;
        end
    end

    integer j;
    integer k;

    initial begin

        rst_n = 1'b0;
        aggregate_buffer_en = 1'b0;        
        read_buffer_en = 1'b0;
        controller_in_ready = 1'b1;
        metadata_in = 0; 

        // Initialize BRAM contents
        for (i = 0; i < PAYLOAD_ITEM_NUM; i = i + 1) begin
            for (j = 0; j < BUFFER_SLOTS; j = j + 1) begin
                payload_bram_storage[i][j] = 0;
            end
        end
        aggregate_bram_storage = 0;

        for (k = 0; k < PAYLOAD_ITEM_NUM; k = k + 1) begin
            payload_bram_storage[k][1] = k + 5; // payload_bram[i] at addr 5 contains value i+1
            aggregate_bram_storage[PAYLOAD_ITEM_WIDTH*(k+1)-1 -: PAYLOAD_ITEM_WIDTH] = k + 10; // aggregate_bram contains all 10s
        end

        #10;
        rst_n = 1'b1;

        metadata_in = {
            5'b00000,
            2'b00,
            8'h00,
            8'h01,
            8'h00
        };

        aggregate_buffer_en = 1'b1;


    end







endmodule
