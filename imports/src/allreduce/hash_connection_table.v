`timescale 1ns / 1ps

// Minimal deterministic connection table for the two-worker hardware test.
//
// Key format:
//   {dst_mac, src_mac, src_ip, dst_ip}
//
// Data format:
//   {is_root, ingress_port[7:0]}
//
// The module keeps the original two-cycle lookup latency:
//   cycle 1: register read_key/read_key_valid
//   cycle 2: register lookup_hit/lookup_data
//
// The write interface is retained for source compatibility. It is intentionally
// inactive in this fixed two-entry test version; the current top level ties
// write_en low.
module hash_connection_table #(
    parameter KEY_WIDTH   = 160,
    parameter HASH_WIDTH  = 8,
    parameter DATA_WIDTH  = 9,
    parameter TABLE_DEPTH = 1 << HASH_WIDTH,
    parameter BUCKET_SIZE = 4
) (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    read_key_valid,
    input  wire [KEY_WIDTH-1:0]    read_key,
    output reg                     lookup_hit,
    output reg  [DATA_WIDTH-1:0]   lookup_data,
    output reg  [HASH_WIDTH-1:0]   lookup_hash_value,

    input  wire                    write_en,
    input  wire [KEY_WIDTH-1:0]    write_key,
    input  wire [DATA_WIDTH-1:0]   write_data
);

    localparam [KEY_WIDTH-1:0] WORKER0_KEY = {
        48'h020000000307,
        48'h6CB31188AB3E,
        32'hC0A80305,
        32'hC0A80307
    };

    localparam [KEY_WIDTH-1:0] WORKER1_KEY = {
        48'h020000000307,
        48'h6CB31188A94E,
        32'hC0A80306,
        32'hC0A80307
    };

    localparam [DATA_WIDTH-1:0] WORKER0_DATA = {1'b1, 8'd0};
    localparam [DATA_WIDTH-1:0] WORKER1_DATA = {1'b1, 8'd1};

    reg  [KEY_WIDTH-1:0] s1_read_key;
    reg                  s1_read_key_valid;
    wire                 s1_worker0_hit;
    wire                 s1_worker1_hit;
    wire [HASH_WIDTH-1:0] s1_read_hash_value;

    assign s1_worker0_hit = s1_read_key_valid && (s1_read_key == WORKER0_KEY);
    assign s1_worker1_hit = s1_read_key_valid && (s1_read_key == WORKER1_KEY);

    // Kept only to preserve lookup_hash_value behavior for future users of the
    // module. The current parser does not consume this output.
    hash_function #(
        .KEY_WIDTH  (KEY_WIDTH),
        .HASH_WIDTH (HASH_WIDTH)
    ) read_hash_func (
        .key_in   (s1_read_key),
        .hash_out (s1_read_hash_value)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_read_key       <= {KEY_WIDTH{1'b0}};
            s1_read_key_valid <= 1'b0;
        end
        else begin
            s1_read_key_valid <= read_key_valid;
            if (read_key_valid) begin
                s1_read_key <= read_key;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lookup_hit        <= 1'b0;
            lookup_data       <= {DATA_WIDTH{1'b0}};
            lookup_hash_value <= {HASH_WIDTH{1'b0}};
        end
        else begin
            lookup_hit        <= s1_worker0_hit || s1_worker1_hit;
            lookup_data       <= s1_worker0_hit ? WORKER0_DATA :
                                 s1_worker1_hit ? WORKER1_DATA :
                                 {DATA_WIDTH{1'b0}};
            lookup_hash_value <= s1_read_hash_value;
        end
    end

endmodule
