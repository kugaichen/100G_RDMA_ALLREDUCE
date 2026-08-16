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

module xpm_fifo_async #(
    parameter integer WRITE_DATA_WIDTH = 32,
    parameter integer READ_DATA_WIDTH = WRITE_DATA_WIDTH,
    parameter integer FIFO_WRITE_DEPTH = 16,
    parameter integer CDC_SYNC_STAGES = 2,
    parameter integer FIFO_READ_LATENCY = 0,
    parameter integer FULL_RESET_VALUE = 0,
    parameter READ_MODE = "std",
    parameter FIFO_MEMORY_TYPE = "auto",
    parameter integer PROG_FULL_THRESH = FIFO_WRITE_DEPTH - 2,
    parameter integer PROG_EMPTY_THRESH = 2
) (
    input  wire                         wr_clk,
    input  wire                         wr_en,
    input  wire [WRITE_DATA_WIDTH-1:0]  din,
    output wire                         full,
    input  wire                         rd_clk,
    input  wire                         rd_en,
    output wire [READ_DATA_WIDTH-1:0]   dout,
    output wire                         empty,
    input  wire                         rst,
    input  wire                         sleep,
    input  wire                         injectsbiterr,
    input  wire                         injectdbiterr,
    output wire                         wr_rst_busy,
    output wire                         rd_rst_busy,
    output wire                         almost_full,
    output wire                         almost_empty,
    output wire                         data_valid,
    output wire [31:0]                  wr_data_count,
    output wire [31:0]                  rd_data_count,
    output wire                         prog_full,
    output wire                         prog_empty,
    output reg                          overflow,
    output reg                          underflow,
    output reg                          wr_ack,
    output wire                         sbiterr,
    output wire                         dbiterr
);
    localparam integer ADDR_W = (FIFO_WRITE_DEPTH <= 2) ? 1 : $clog2(FIFO_WRITE_DEPTH);

    reg [WRITE_DATA_WIDTH-1:0] mem [0:FIFO_WRITE_DEPTH-1];
    reg [ADDR_W-1:0] wr_ptr;
    reg [ADDR_W-1:0] rd_ptr;
    reg [ADDR_W:0] count;

    assign full = (count == FIFO_WRITE_DEPTH[ADDR_W:0]);
    assign empty = (count == {ADDR_W+1{1'b0}});
    assign dout = mem[rd_ptr][READ_DATA_WIDTH-1:0];
    assign almost_full = (count >= FIFO_WRITE_DEPTH[ADDR_W:0] - 1'b1);
    assign almost_empty = (count <= {{ADDR_W{1'b0}}, 1'b1});
    assign data_valid = !empty;
    assign wr_data_count = count;
    assign rd_data_count = count;
    assign prog_full = almost_full;
    assign prog_empty = almost_empty;
    assign wr_rst_busy = 1'b0;
    assign rd_rst_busy = 1'b0;
    assign sbiterr = 1'b0;
    assign dbiterr = 1'b0;

    always @(posedge wr_clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= {ADDR_W{1'b0}};
            rd_ptr <= {ADDR_W{1'b0}};
            count <= {ADDR_W+1{1'b0}};
            overflow <= 1'b0;
            underflow <= 1'b0;
            wr_ack <= 1'b0;
        end else begin
            overflow <= 1'b0;
            underflow <= 1'b0;
            wr_ack <= 1'b0;

            case ({wr_en && !full, rd_en && !empty})
                2'b10: begin
                    mem[wr_ptr] <= din;
                    wr_ptr <= wr_ptr + 1'b1;
                    count <= count + 1'b1;
                    wr_ack <= 1'b1;
                end
                2'b01: begin
                    rd_ptr <= rd_ptr + 1'b1;
                    count <= count - 1'b1;
                end
                2'b11: begin
                    mem[wr_ptr] <= din;
                    wr_ptr <= wr_ptr + 1'b1;
                    rd_ptr <= rd_ptr + 1'b1;
                    wr_ack <= 1'b1;
                end
                default: begin
                    if (wr_en && full)
                        overflow <= 1'b1;
                    if (rd_en && empty)
                        underflow <= 1'b1;
                end
            endcase
        end
    end

    wire unused_inputs = sleep ^ injectsbiterr ^ injectdbiterr ^
                         ^{CDC_SYNC_STAGES, FULL_RESET_VALUE, PROG_FULL_THRESH,
                           PROG_EMPTY_THRESH, FIFO_READ_LATENCY};
endmodule
