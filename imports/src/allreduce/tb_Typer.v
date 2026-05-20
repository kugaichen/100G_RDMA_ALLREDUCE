`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/09/19 21:29:22
// Design Name: 
// Module Name: tb_Typer
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


module tb_Typer;
    parameter OPCODE_ACK            = 8'h11;
    parameter OPCODE_FIRST          = 8'h0;
    parameter OPCODE_MIDDLE         = 8'h1;
    parameter OPCODE_LAST           = 8'h2;
    parameter OPCODE_SEND_ONLY      = 8'h4;

    parameter FAN_IN = 2;

    parameter TYPE_ACK_UP           = 3'b001;
    parameter TYPE_NOROOT_DATA_UP   = 3'b010;
    parameter TYPE_ROOT_DATA_UP     = 3'b011;
    parameter TYPE_DATA_DOWN        = 3'b100;
    parameter TYPE_ACK_DOWN         = 3'b101;
    parameter TYPE_NOVALID          = 3'b000;

    // Inputs
    reg                 clk;
    reg                 rst_n;

    reg                 aggregate_en;
    reg  [3*8-1:0]      metadata_without_type;
    reg  [7:0]          opcode;

    wire [3*8-1:0]      metadata_with_type;
    wire                valid_out;

    Typer uut (
        .clk(clk), .rst_n(rst_n), .aggregate_en(aggregate_en), 
        .metadata_without_type(metadata_without_type), .opcode(opcode),
        .metadata_with_type(metadata_with_type), .valid_out(valid_out)
    );

    initial begin
        clk = 0;
        forever begin
            #5 clk = ~clk;
        end
    end

    initial begin
        rst_n = 0;
        aggregate_en = 0;
        opcode = 0;
        metadata_without_type = 0;

        #10;
        rst_n = 1;
        aggregate_en = 1;

        metadata_without_type[7:0] = 8'b00000001;
        metadata_without_type[15:8] = 8'b00000000;
        metadata_without_type[23:16] = 8'b00000000;
        opcode[7:0] = OPCODE_FIRST;

        #40;

        aggregate_en = 0;
        #10;
        aggregate_en = 1;

        metadata_without_type[16:16] = 1'd1;

        opcode[7:0] = OPCODE_LAST;

        #40;

        metadata_without_type[7:0] = 8'b00000010;

        opcode[7:0] = OPCODE_ACK;

        #40;


        metadata_without_type[7:0] = 8'b00000011;

        opcode[7:0] = OPCODE_FIRST;


        #20;

        $finish;

    end
 

endmodule
