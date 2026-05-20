`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/21 19:04:16
// Design Name: 
// Module Name: new_slot_creater
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


 module new_slot_creater #(
    parameter WINDOWSIZE = 8,
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 8,
    parameter PAYLOAD_ITEM_WIDTH = 512,
    parameter PAYLOAD_ITEM_NUM = 16,
    parameter SLOTS_WIDTH = 8
)(
    input   wire                clk,
    input   wire                rst_n, 
    input   wire                new_slot_en,
    input   wire [3*8-1:0]      in_metadata,
    // input   wire                in_valid,
    output  wire                in_ready,
    
    input   wire                    out_ready,
    input   wire                    new_arrival_state_wr_grant, 
    output  reg                     new_arrival_state_wr_en,
    output  reg [ADDR_WIDTH-1:0]    new_arrival_state_wr_addr,
    output  reg [DATA_WIDTH-1:0]    new_arrival_state_wr_data,
    
    input   wire                    new_degree_wr_grant,
    output  reg                     new_degree_wr_en,
    output  reg [ADDR_WIDTH-1:0]    new_degree_wr_addr,
    output  reg [DATA_WIDTH-1:0]    new_degree_wr_data,  

    // new
    input   wire                                                     new_aggregate_bram_wr_grant,
    output  wire[PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]            new_aggregate_bram_wr_vector_pack,              // 聚合后的写入数据
    output  reg [SLOTS_WIDTH-1:0]                                    new_aggregate_bram_wr_addr,
    output  reg [PAYLOAD_ITEM_NUM-1:0]                               new_aggregate_bram_wr_en_pack

);

    reg                         s1_valid;
    reg [ADDR_WIDTH-1:0]        s1_wr_addr;

    reg                         s2_valid;

    reg                         s3_valid;

    wire                        s1_valid_holdfix;
    wire                        s2_valid_holdfix;

    wire s1_can_accept;
    wire s2_can_accept;
    wire s3_can_accept;

    (* DONT_TOUCH = "TRUE" *) LUT1 #(
        .INIT(2'b10)
    ) u_lut1_s1_valid_holdfix (
        .I0(s1_valid),
        .O(s1_valid_holdfix)
    );

    (* DONT_TOUCH = "TRUE" *) LUT1 #(
        .INIT(2'b10)
    ) u_lut1_s2_valid_holdfix (
        .I0(s2_valid),
        .O(s2_valid_holdfix)
    );

    assign s3_can_accept = !s3_valid || (s3_valid && out_ready);
    assign s2_can_accept = !s2_valid || (s2_valid && s3_can_accept);
    assign s1_can_accept = !s1_valid || (s1_valid && s2_can_accept);

    assign in_ready = s1_can_accept;
    assign out_valid = s3_valid;

    // data
    assign new_aggregate_bram_wr_vector_pack = 0;

    // data
    // wire [PAYLOAD_ITEM_WIDTH-1:0] new_aggregate_bram_wr_vector_unpack [PAYLOAD_ITEM_NUM-1:0];

    // genvar i;
    // generate
    //     for (i = 0; i < PAYLOAD_ITEM_NUM; i = i + 1 ) begin : new_aggregate_unpack_logic
    //         assign ;
    //     end
    // endgenerate

    // assign new_wr_addr = s1_idx_psn + WINDOWSIZE;

    // wire s2_ready = out_ready;
    // wire s1_ready = !s2_valid || s2_ready;
    // assign in_ready = !s2_valid || out_ready;

    // always @(posedge clk or negedge rst_n) begin
    //     if(!rst_n) begin
    //         s1_valid <= 0;
    //         s1_ready <= 0;
    //         s2_valid <= 0;
    //         s1_valid <= 0;
    //         in_ready <= 0;
    //         new_arrival_state_wr_en <= 0;
    //         new_arrival_state_wr_addr <= 0;
    //         new_arrival_state_wr_data <= 0;
    //         new_degree_wr_en <= 0;
    //         new_degree_wr_addr <= 0;
    //         new_degree_wr_data <= 0;
    //     end

    //     else begin
    //         new_arrival_state_wr_en <= 0;
    //         new_degree_wr_en <= 0;
    //         if (s1_ready) begin
    //             s1_valid <= 1'b1;
    //             if (new_slot_en) begin
    //                 s1_idx_psn <= in_metadata[15:8];
    //             end
    //         end

    //         if (s2_ready && s1_valid) begin
    //             s2_valid <= s1_valid;
    //             if (s1_valid) begin
    //                 s2_wr_addr <= new_wr_addr;
    //             end
    //         end

    //         if (out_ready && s2_valid) begin
    //             new_arrival_state_wr_en <= 1;
    //             new_arrival_state_wr_addr <= s2_wr_addr;
    //             new_arrival_state_wr_data <= 0;

    //             new_degree_wr_en <= 1;
    //             new_degree_wr_addr <= s2_wr_addr;
    //             new_degree_wr_data <= 0;
    //         end
    //     end
            
    // end

// arbiter
    // S1
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 0;
            new_arrival_state_wr_en <= 0;
            new_arrival_state_wr_addr <= 0;
            new_arrival_state_wr_data <= 0;
            new_degree_wr_en <= 0;
            new_degree_wr_addr <= 0;
            new_degree_wr_data <= 0;
        end

        else begin
            if (s2_can_accept || !s1_valid) begin
                s1_valid <= new_slot_en;
                new_arrival_state_wr_en <= new_slot_en;
                new_arrival_state_wr_addr <= in_metadata[15:8] + WINDOWSIZE;
                new_arrival_state_wr_data <= 0;
                new_degree_wr_en <= new_slot_en;
                new_degree_wr_addr <= in_metadata[15:8] + WINDOWSIZE;
                new_degree_wr_data <= 0;

                new_aggregate_bram_wr_addr <= in_metadata[15:8] + WINDOWSIZE;
                new_aggregate_bram_wr_en_pack <= {16{new_slot_en}};

            end
        end
    end

    // S2
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 0;
        end
        else begin
            if (s3_can_accept || !s2_valid) begin
                s2_valid <= s1_valid_holdfix;
            end
        end
    end

    // S3
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_valid <= 0;
        end

        else begin
            if ((out_ready || !s3_valid) && new_arrival_state_wr_grant && new_degree_wr_grant && new_aggregate_bram_wr_grant) begin
                s3_valid <= s2_valid_holdfix;
            end
            else begin
                s3_valid <= 0;
            end
        end
    end



endmodule
