`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/09/05 10:26:05
// Design Name: 
// Module Name: hash_connection
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

module hash_function #(
    parameter KEY_WIDTH  = 192,
    parameter HASH_WIDTH = 8
)(
    input   wire [KEY_WIDTH-1:0] key_in,
    output  wire [HASH_WIDTH-1:0] hash_out
);
    genvar i;
    generate
        wire [HASH_WIDTH-1:0] crc_temp[0:KEY_WIDTH];
        assign crc_temp[0] = {HASH_WIDTH{1'b0}};

        for (i = 0; i < KEY_WIDTH; i = i + 1) begin : hash_loop
            wire [HASH_WIDTH:0] next_crc_temp;
            assign next_crc_temp = ({1'b0, crc_temp[i]} << 1) ^ (key_in[i] ? 9'h1ED : 9'h0);
            assign crc_temp[i+1] = next_crc_temp[HASH_WIDTH-1:0];
        end
        
        assign hash_out = crc_temp[KEY_WIDTH];
    endgenerate
endmodule

