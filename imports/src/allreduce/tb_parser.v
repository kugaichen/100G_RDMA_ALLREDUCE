`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/09/09 15:15:50
// Design Name: 
// Module Name: tb_parser
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


module tb_parser;

    parameter AXIS_DATA_WIDTH    = 512;
    parameter AXIS_KEEP_WIDTH    = AXIS_DATA_WIDTH / 8;
    parameter ORIGIN_HDR_LEN     = 54*8;

    // Hash Table
    parameter HASH_KEY_WIDTH     = 192;
    parameter HASH_DATA_WIDTH    = 1;
    parameter HASH_WIDTH         = 8;

    // HEADER / METADATA
    parameter PKT_HDR_LEN        = (2*6+4*4+3*2+1) * 8;
    parameter METADATA_LEN       = 2*8+3+5;
    
    // PAYLOAD
    parameter PAYLOAD_WIDTH      = 1024*8;
    parameter PAYLOAD_ITEM_NUM   = 16;
    parameter PAYLOAD_ITEM_WIDTH = 512;
    parameter PAYLOAD_BEATS      = PAYLOAD_WIDTH / AXIS_DATA_WIDTH;
    parameter PAYLOAD_ITEM_COUNT_WIDTH = $clog2(PAYLOAD_ITEM_NUM);

    // WIDTH
    parameter MAC_ADDR_WIDTH = 48;
    parameter IP_ADDR_WIDTH = 32;
    parameter PSN_WIDTH = 32;
    parameter PORT_WIDTH = 16;
    parameter IP_START = 26;
    parameter BTH_START = 42;
    parameter OPCODE_WIDTH = 8;
    parameter QPN_START = 46;
    parameter QPN_LEN = 32;

    // BUFFER
    parameter WINDOWSIZE = 8;
    parameter BUFFER_SLOTS = 16;
    parameter RING_SLOT_WIDTH = 16;

    // Inputs
    reg axis_clk;
    reg rst_n;


    reg [AXIS_DATA_WIDTH-1:0]    axis_in_data;
    reg [7:0]                    ingress_port;   

    reg [AXIS_KEEP_WIDTH-1:0]    axis_tkeep;
    reg                          axis_tvalid;
    reg                          axis_tlast;
    wire                         in_ready;

    wire                         pkt_valid_out;
    wire [AXIS_KEEP_WIDTH-1:0]   pkt_keep_out;
    wire [AXIS_DATA_WIDTH-1:0]   pkt_data_out;
    wire                         pkt_last_out;
    reg                          pkt_ready_in;
    
    wire                         agg_valid_out;
    wire [PKT_HDR_LEN-1:0]       agg_header_out;
    wire [METADATA_LEN-1:0]      agg_metadata_out;
    wire [OPCODE_WIDTH-1:0]      agg_opcode_out;        
    wire                         agg_payload_fire_en;
    reg                          agg_ready_in;

    wire [RING_SLOT_WIDTH+PAYLOAD_ITEM_COUNT_WIDTH-1:0]   payload_wr_addr;
    wire [PAYLOAD_ITEM_WIDTH-1:0]       payload_wr_data;
    wire                                payload_wr_en;
    reg                                 payload_wr_ready;

    parser parser_init (
        .axis_clk(axis_clk), .rst_n(rst_n), .ingress_port(ingress_port),
        .axis_in_data(axis_in_data), .axis_tkeep(axis_tkeep),
        .axis_tvalid(axis_tvalid), .axis_tlast(axis_tlast),
        .pkt_ready_in(pkt_ready_in), .in_ready(in_ready),
        .pkt_valid_out(pkt_valid_out), .pkt_keep_out(pkt_keep_out),
        .pkt_data_out(pkt_data_out), .pkt_last_out(pkt_last_out),
        .agg_valid_out(agg_valid_out), .agg_header_out(agg_header_out),
        .agg_metadata_out(agg_metadata_out), .agg_opcode_out(agg_opcode_out),
        .agg_payload_fire_en(agg_payload_fire_en), .agg_ready_in(agg_ready_in),
        .payload_wr_addr(payload_wr_addr), .payload_wr_data(payload_wr_data),
        .payload_wr_en(payload_wr_en), .payload_wr_ready(payload_wr_ready)
    );

    initial begin
        axis_clk = 0;
        axis_tkeep = 0;
        axis_tlast = 0;
        axis_in_data = 0;
        axis_tvalid = 0;
        forever begin
            #5 axis_clk = ~axis_clk;
        end
    end

    initial begin
        pkt_ready_in = 1'b1;
        agg_ready_in = 1'b1;
        payload_wr_ready = 1'b1;
    end

    // 假设BRAM
    localparam BRAM_DEPTH = BUFFER_SLOTS * PAYLOAD_ITEM_NUM;
    reg [PAYLOAD_ITEM_WIDTH-1:0] payload_bram[0:BRAM_DEPTH-1];

    always @(posedge axis_clk) begin
        if(payload_wr_en) begin
            payload_bram[payload_wr_addr] <= payload_wr_data;
        end
    end


    // lookup-hit
    reg [AXIS_DATA_WIDTH-1:0] data_stream[0:33];
    reg [47:0] hit_src_mac = 48'hAABBCCDDEEFF;
    reg [47:0] hit_dst_mac = 48'h112233445566;
    reg [31:0] hit_src_ip = 32'h0A000001;
    reg [31:0] hit_dst_ip = 32'h0A000002;
    reg [15:0] hit_src_port = 16'd1234;
    reg [15:0] hit_dst_port = 16'd5678;
    reg        hit_root_info = 1'b1;

    wire [HASH_WIDTH-1:0]       hit_hash_value;
    reg  [HASH_KEY_WIDTH-1:0]   full_hit_key;

    hash_function #(.KEY_WIDTH(HASH_KEY_WIDTH), .HASH_WIDTH(HASH_WIDTH)) temp_hash_func (
        .key_in({hit_dst_mac,hit_src_mac,hit_src_ip,hit_dst_ip,hit_src_port,hit_dst_port}),
        .hash_out(hit_hash_value)
    );


    integer i,j;

    initial begin
        data_stream[0] = {
            // 1. payload
            32'h0000_0002, 32'h0000_0001, 16'h0000,

            // 2. RoCEv2 BTH
            32'h0001,
            32'h0001,
            16'h11,
            8'h1,
            8'h1,

            // 3. UDP Header
            16'h11,
            16'd970,
            hit_dst_port,
            hit_src_port,

            // 4. IPV4 header
            hit_dst_ip,
            hit_src_ip,
            16'h11,
            8'h1,
            8'h8,
            16'h01,
            16'h02,
            16'h09,
            8'h0,
            8'h1,

            // 5. Eth
            16'h01,
            hit_src_mac,
            hit_dst_mac
        };

        data_stream[1] = 512'd2;
        data_stream[2] = {512{1'b1}};
        data_stream[3] = 512'd6;
        data_stream[4] = 512'd8;
        data_stream[5] = 512'd16;
        data_stream[6] = 512'd32;
        data_stream[7] = 512'd64;
        data_stream[8] = 512'd32;
        data_stream[9] = 512'd16;
        data_stream[10] = 512'd8;
        data_stream[11] = 512'd4;
        data_stream[12] = 512'd2;
        data_stream[13] = 512'd1;
        data_stream[14] = 512'd0;
        data_stream[15] = 512'd2;
        data_stream[16] = {32'h0002_0002, 32'h0002_0002, 16'h0000, {432{1'b1}}};

        data_stream[17] = {
            // 1. payload
            32'h0000_0002, 32'h0000_0001, 16'h0000,

            // 2. RoCEv2 BTH
            32'h0001,
            32'h0001,
            16'h11,
            8'h1,
            8'h1,

            // 3. UDP Header
            16'h11,
            16'd970,
            hit_dst_port,
            hit_src_port,

            // 4. IPV4 header
            // hit_dst_ip,
            32'h0A000008,
            hit_src_ip,
            16'h11,
            8'h1,
            8'h8,
            16'h01,
            16'h02,
            16'h09,
            8'h0,
            8'h1,

            // 5. Eth
            16'h01,
            hit_src_mac,
            hit_dst_mac
        };

        // data_stream[18] = 512'd2;
        // data_stream[19] = {512{1'b1}};
        // data_stream[20] = 512'd6;
        // data_stream[21] = 512'd8;
        // data_stream[22] = 512'd16;
        // data_stream[23] = 512'd32;
        // data_stream[24] = 512'd64;
        // data_stream[25] = 512'd32;
        // data_stream[26] = 512'd16;
        // data_stream[27] = 512'd8;
        // data_stream[28] = 512'd4;
        // data_stream[29] = 512'd2;
        // data_stream[30] = 512'd1;
        // data_stream[31] = 512'd0;
        // data_stream[32] = 512'd2;
        // data_stream[33] = {32'h0002_0002, 32'h0002_0002, 16'h0000, {432{1'b1}}};

        data_stream[18] = 512'd2;
        data_stream[19] = {512{1'b1}};
        data_stream[20] = 512'd6;
        data_stream[21] = 512'd8;
        data_stream[22] = 512'd16;
        data_stream[23] = 512'd32;
        data_stream[24] = 512'd64;
        data_stream[25] = 512'd32;
        data_stream[26] = 512'd16;
        data_stream[27] = 512'd8;
        data_stream[28] = 512'd4;
        data_stream[29] = 512'd2;
        data_stream[30] = 512'd1;
        data_stream[31] = 512'd0;
        data_stream[32] = 512'd2;
        data_stream[33] = {32'h0002_0002, 32'h0002_0002, 16'h0000, {432{1'b1}}};

        ingress_port = 8'h01;

        // Beats 1 to 15 (pure payload)
        // for (j = 1; j < 16; j = j + 1) begin
        //     data_stream[j] = {
        //         (j*16+15), (j*16+14), (j*16+13), (j*16+12),
        //         (j*16+11), (j*16+10), (j*16+9),  (j*16+8),
        //         (j*16+7),  (j*16+6),  (j*16+5),  (j*16+4),
        //         (j*16+3),  (j*16+2),  (j*16+1),  (j*16+0)
        //     };
        // end

        // data_stream[1][511 -: 80] = {32'h0000_0005, 32'h0000_0004, 16'h0003};

        rst_n = 1'b0;
        #10
        rst_n = 1'b1;

        @(posedge axis_clk);
        full_hit_key = {hit_dst_mac,hit_src_mac,hit_src_ip,hit_dst_ip,hit_src_port,hit_dst_port};
        parser_init.u_connection_table.table_mem[hit_hash_value][0] = {hit_root_info,full_hit_key,1'b1};
        
        for (i = 0; i < 16; i = i + 1 ) begin
            wait(in_ready);
            @(posedge axis_clk);
            axis_in_data <= data_stream[i];
            axis_tvalid <= 1'b1;
            axis_tkeep <= {AXIS_KEEP_WIDTH{1'b1}};
            axis_tlast <= 1'b0; 
        end

        wait(in_ready);
        @(posedge axis_clk);
        axis_in_data <= data_stream[16];
        axis_tvalid <= 1'b1;
        axis_tkeep <= {AXIS_KEEP_WIDTH{1'b1}};
        axis_tlast <= 1'b1; 
        
        // @(posedge axis_clk);
        // axis_tvalid <= 1'b0;
        // axis_tlast <= 1'b0;



        for (i = 17; i < 33; i = i + 1 ) begin
            wait(in_ready);
            @(posedge axis_clk);
            axis_in_data <= data_stream[i];
            axis_tvalid <= 1'b1;
            axis_tkeep <= {AXIS_KEEP_WIDTH{1'b1}};
            axis_tlast <= 1'b0; 
        end

        wait(in_ready);
        @(posedge axis_clk);
        axis_in_data <= data_stream[33];
        axis_tvalid <= 1'b1;
        axis_tkeep <= {AXIS_KEEP_WIDTH{1'b1}};
        axis_tlast <= 1'b1; 
        
        @(posedge axis_clk);
        axis_tvalid <= 1'b0;
        axis_tlast <= 1'b0;

        repeat(5) @(posedge axis_clk);

        $finish;
    end

endmodule
