// Minimal Xilinx primitive stubs for local iverilog syntax checks.
// Do not add this file to Vivado synthesis/simulation filesets.

module LUT1 #(
    parameter [1:0] INIT = 2'b10
) (
    input wire I0,
    output wire O
);
    assign O = INIT[I0];
endmodule

module ila_0 (
    input wire clk,
    input wire [255:0] probe0,
    input wire [255:0] probe1,
    input wire [255:0] probe2,
    input wire [255:0] probe3,
    input wire [255:0] probe4,
    input wire [255:0] probe5,
    input wire [255:0] probe6,
    input wire [255:0] probe7,
    input wire [255:0] probe8,
    input wire [255:0] probe9,
    input wire [255:0] probe10,
    input wire [255:0] probe11,
    input wire [255:0] probe12,
    input wire [255:0] probe13,
    input wire [255:0] probe14,
    input wire [255:0] probe15,
    input wire [255:0] probe16
);
endmodule
