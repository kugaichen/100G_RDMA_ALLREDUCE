//
// cam.v - lightweight drop-in replacement for NetFPGA-PLUS cam_v1_1_0 IP
//
// Original (NetFPGA reference): cam.v -> cam_wrapper.v -> cam_top (Xilinx
//   ISE-era CAM Compiler VHDL) which is shipped only as a placeholder
//   (.keep) in the open-source repository. Producing it requires running
//   `cam.tcl` against an external CAM Compiler library.
//
// Replacement (this file): same module name, same parameter names, same port
//   list as the NetFPGA cam.v, but implemented as 16-deep distributed-RAM
//   exact-match table + parallel comparators. Adequate for switch
//   reference_switch's 16x48-bit MAC CAM. Timing matches the original's
//   "1-cycle read latency, 2-cycle write latency" contract that
//   mac_cam_lut.v relies on.
//
// Limitations vs. the original ternary CAM:
//   - exact match only (no don't-care bits). reference_switch never writes
//     don't-care, so this is functionally equivalent for the 4-port port.
//   - single-match assumed (no MULTIPLE_MATCH outputs).
//   - depth/width hardcoded behavior tested for ADDR_WIDTH=4, DATA_WIDTH=48.
//     Other widths still work but are not validated.
//
`timescale 1ns/1ps

module cam
#(
    parameter C_TCAM_ADDR_WIDTH       = 5,
    parameter C_TCAM_DATA_WIDTH       = 32,
    parameter C_TCAM_ADDR_TYPE        = 0,
    parameter C_TCAM_MATCH_ADDR_WIDTH = 5
)(
    input                                 CLK,
    input                                 WE,
    input  [C_TCAM_ADDR_WIDTH-1:0]        ADDR_WR,
    input  [C_TCAM_DATA_WIDTH-1:0]        DIN,
    output                                BUSY,

    input  [C_TCAM_DATA_WIDTH-1:0]        CMP_DIN,
    output                                MATCH,
    output [C_TCAM_MATCH_ADDR_WIDTH-1:0]  MATCH_ADDR
);

    localparam DEPTH = (1 << C_TCAM_ADDR_WIDTH);

    // Storage: one entry per address; "valid" tracks written rows so an
    // unwritten entry never spuriously matches all-zeros CMP_DIN.
    reg [C_TCAM_DATA_WIDTH-1:0] mem   [0:DEPTH-1];
    reg [DEPTH-1:0]             valid;

    // 2-cycle write latency: stage WE/ADDR_WR/DIN once, then commit.
    reg                         we_d;
    reg [C_TCAM_ADDR_WIDTH-1:0] addr_wr_d;
    reg [C_TCAM_DATA_WIDTH-1:0] din_d;
    reg                         busy_r;

    integer i_init;
    initial begin
        valid  = {DEPTH{1'b0}};
        we_d   = 1'b0;
        busy_r = 1'b0;
        for (i_init = 0; i_init < DEPTH; i_init = i_init + 1) begin
            mem[i_init] = {C_TCAM_DATA_WIDTH{1'b0}};
        end
    end

    always @(posedge CLK) begin
        we_d      <= WE;
        addr_wr_d <= ADDR_WR;
        din_d     <= DIN;
        busy_r    <= WE | we_d;       // BUSY high during the 2-cycle write
        if (we_d) begin
            mem[addr_wr_d]   <= din_d;
            valid[addr_wr_d] <= 1'b1;
        end
    end

    assign BUSY = busy_r;

    // Parallel exact-match: 1-cycle registered read latency.
    reg [DEPTH-1:0]                  hit_vec;
    integer i_cmp;
    always @(posedge CLK) begin
        for (i_cmp = 0; i_cmp < DEPTH; i_cmp = i_cmp + 1) begin
            hit_vec[i_cmp] <= valid[i_cmp] && (mem[i_cmp] == CMP_DIN);
        end
    end

    // Priority encoder over hit_vec -> match_addr; MATCH = |hit_vec.
    reg [C_TCAM_MATCH_ADDR_WIDTH-1:0] match_addr_r;
    integer i_enc;
    always @* begin
        match_addr_r = {C_TCAM_MATCH_ADDR_WIDTH{1'b0}};
        for (i_enc = DEPTH-1; i_enc >= 0; i_enc = i_enc - 1) begin
            if (hit_vec[i_enc]) begin
                match_addr_r = i_enc[C_TCAM_MATCH_ADDR_WIDTH-1:0];
            end
        end
    end

    assign MATCH      = |hit_vec;
    assign MATCH_ADDR = match_addr_r;

endmodule
