`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/08 15:34:31
// Design Name: 
// Module Name: tb_allreduce_offload_top
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


module tb_allreduce_offload_top;
    parameter PROT_NUM                  = 2;                    // 节点数量
    parameter AXIS_DATA_WIDTH           = 512;
    parameter AXIS_KEEP_WIDTH           = AXIS_DATA_WIDTH / 8;
    parameter ORIGIN_HDR_LEN            = 54*8;

    parameter HASH_KEY_WIDTH            = 192;
    parameter HASH_DATA_WIDTH           = 1;
    parameter HASH_WIDTH                = 8;

    parameter PKT_HDR_LEN               = (2*6+4*4+3*2+1) * 8;
    parameter METADATA_LEN              = 2*8+3+5;

    parameter PAYLOAD_WIDTH             = 1024*8;
    parameter PAYLOAD_ITEM_NUM          = 16;
    parameter PAYLOAD_ITEM_WIDTH        = AXIS_DATA_WIDTH;
    
    // WIDTH
    parameter MAC_ADDR_WIDTH            = 48;
    parameter IP_ADDR_WIDTH             = 32;
    parameter PORT_WIDTH                = 16;
    parameter OPCODE_WIDTH              = 8;

    // BUFFER
    parameter WINDOWSIZE                = 16;
    parameter BUFFER_SLOTS              = 32;
    parameter RING_SLOT_WIDTH           = 16;

    // Typer
    parameter OPCODE_FIRST              = 8'h0;

    // ---------------------------SINGAL---------------------------------

    reg                                                 clk;
    reg                                                 rst_n;

    // AXI-stream input
    reg [AXIS_DATA_WIDTH-1:0]                           s_axis_tdata;
    reg [AXIS_KEEP_WIDTH-1:0]                           s_axis_tkeep;
    reg                                                 s_axis_tvalid;
    reg                                                 s_axis_tlast;
    wire                                                s_axis_tready;

    // AXI-stream output (Master)           
    wire [AXIS_DATA_WIDTH-1:0]                          m_axis_tdata;
    wire [AXIS_KEEP_WIDTH-1:0]                          m_axis_tkeep;
    wire                                                m_axis_tvalid;
    wire                                                m_axis_tlast;
    reg                                                 m_axis_tready;

    // Control & Debug          
    reg [7:0]                                           ingress_port;


    wire                                                deparser_to_aggregator_in_ready;
    wire [PKT_HDR_LEN-1:0]                              parser_to_deparser_header_out;

    // Aggregator Outputs (Monitored)
    wire [METADATA_LEN-1:0]                             aggregator_to_deparser_metadata_out;
    wire                                                aggregator_to_deparser_ack_build_en_out;                 // up_ack类型
    wire                                                aggregator_to_deparser_ack_down_en_out;                  // ack_down，实际不存在
    wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]      aggregator_to_deparser_payload_out;                      // 输出payload信息
    wire                                                aggregator_to_deparser_FAN_retrans_en_out;               // no_root_up_data，重传给父节点
    wire                                                aggregator_to_deparser_FAN_first_trans_en_out;           // no_root_up_data，转发给父节点
    wire                                                aggregator_to_deparser_down_broadcast_en_out;            // root_up_data转down_data/或down_data，广播给子节点
    wire                                                aggregator_to_deparser_port_retrans_en_out;  


    // =================================================================
    // DUT Instantiation
    // =================================================================
    allreduce_offload_top #(
        .PROT_NUM(PROT_NUM),
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
        .FIFO_DEPTH(32)
    ) dut (
        .sys_clk_90m(clk),
        .rst_n(rst_n),

        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),

        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tready(m_axis_tready),

        .ingress_port(ingress_port)
    );

    // =================================================================
    // [新增] 浮点测试辅助常量与函数
    // =================================================================
    // IEEE-754 单精度浮点数
    localparam [31:0] FP_1_0 = 32'h00003F80; // 1.0
    localparam [31:0] FP_2_0 = 32'h00004000; // 2.0
    localparam [31:0] FP_3_0 = 32'h40400000; // 3.0 (期望结果)

    // 辅助函数：将 32bit 浮点数复制填充到 512bit 向量中
    function [511:0] gen_float_vec;
        input [31:0] fp_val;
        integer k;
        begin
            for (k=0; k<16; k=k+1) begin
                gen_float_vec[32*k +: 32] = fp_val;
            end
        end
    endfunction

    // ------------------------------------------------------------------

    initial begin
        clk = 0;
        forever begin
            #5 clk = ~clk;
        end
    end

    task automatic send_pack;
        input [7:0]     in_port;
        input [47:0]    src_mac;
        input [47:0]    dst_mac;
        input [31:0]    src_ip;
        input [31:0]    dst_ip;
        input [15:0]    src_port;
        input [15:0]    dst_port;
        input [31:0]    qpn;
        input [31:0]    psn;
        input [7:0]     opcode;
        input [PAYLOAD_ITEM_WIDTH-1:0]  payload_start_val;

        integer i;
        reg [AXIS_DATA_WIDTH-1:0]   original_header;
        begin
            ingress_port = in_port;

            // 1. Construct Header (512 bits)
            original_header = 0;
            // Ethernet
            original_header[47:0]   =   dst_mac;
            original_header[95:48]  =   src_mac;
            original_header[111:96] =   16'h01;

            // IP
            original_header[119:112] = 8'h1;
            original_header[127:120] = 8'h0;
            original_header[143:128] = 16'h09;
            original_header[159:144] = 16'h02;
            original_header[175:160] = 16'h01;
            original_header[183:176] = 8'h8;
            original_header[191:184] = 8'h1;
            original_header[207:192] = 16'h11;
            original_header[208 +: 32] = src_ip;
            original_header[240 +: 32] = dst_ip;

            // UDP
            original_header[272 +: 16] = src_port;
            original_header[288 +: 16] = dst_port;
            original_header[319:304] = 16'd1024;
            original_header[335:320] = 16'h11;

            // BTH
            original_header[336 +: 8] = opcode;
            original_header[344 +: 8] = 8'h1;
            original_header[352 +: 16] = 16'h11;
            original_header[368 +: 32] = qpn;
            original_header[400 +: 32] = psn;

            // Payload
            original_header[432 +: 80] = 80'h0000_4444_3333_2222_1111;
            // 浮点
            // original_header[511:432] = payload_start_val[511:432];

            // @(posedge clk);

            // 2. Send Original header
            s_axis_tdata <= original_header;
            s_axis_tkeep <= {AXIS_KEEP_WIDTH{1'b1}};
            s_axis_tvalid <= 1'b1;
            s_axis_tlast  <= 1'b0;

            @(posedge clk);
            while (!s_axis_tready) begin
                @(posedge clk);
            end

            // 3. Send Payload
            for (i = 0; i < PAYLOAD_ITEM_NUM; i = i + 1) begin
                // 整数
                s_axis_tdata  <= payload_start_val + i;
         
          


                // // 浮点  -------------
                // // 1. 低 432 bit：放当前 Payload 的高位 [511:80]
                // s_axis_tdata[431:0]  <= payload_start_val[431:0];
                
                // // 2. 高 80 bit：放下一个 Payload 的低位 [79:0]
                // // 此时因为所有 Payload 数据相同(payload_start_val)，所以直接取同样的[79:0]
                // // 如果是最后一个 Item，高位就是 Padding (可以是 0 或任意值)
                // if (i == PAYLOAD_ITEM_NUM - 1) 
                //     s_axis_tdata[511:432] <= 0; 
                // else
                //     s_axis_tdata[511:432] <= payload_start_val[511:432];
                // // 浮点 2 ----------

                

                // s_axis_tdata <= {(AXIS_DATA_WIDTH/4){i[3:0]}};
                s_axis_tkeep  <= {AXIS_KEEP_WIDTH{1'b1}};
                s_axis_tvalid <= 1'b1;           

                if (i == PAYLOAD_ITEM_NUM - 1) begin
                    s_axis_tlast <= 1'b1;
                end
                else begin
                    s_axis_tlast <= 1'b0;
                end

                @(posedge clk);
                while (!s_axis_tready) @(posedge clk);
            end

            // 4. End Packet
            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
            s_axis_tdata  <= 0;
            s_axis_tkeep  <= 0;
            // @(posedge clk);
        end
    endtask

    // =================================================================
    // 3. Hash Helper Signals (For Backdoor Init)
    // =================================================================
    // 定义2组“命中”用的 Key 参数
    reg [47:0] hit_src_mac_0  = 48'hAABBCCDDEEFF;
    reg [47:0] hit_dst_mac_0  = 48'h112233445566;
    reg [31:0] hit_src_ip_0   = 32'h0A000001;
    reg [31:0] hit_dst_ip_0   = 32'h0A000002;
    reg [15:0] hit_src_port_0 = 16'd1234;
    reg [15:0] hit_dst_port_0 = 16'd5678;
    reg        hit_root_info_0 = 1'b1;
    reg        hit_valid     = 1'b1;
    
    wire [HASH_WIDTH-1:0]     hit_hash_value_0;
    reg  [HASH_KEY_WIDTH-1:0] full_hit_key_0;

    // 实例化 Hash 函数 (Helper)，用于计算 Index
    // 注意：这里的参数必须与 parser.v 内部实例化的一致
    hash_function #(
        .KEY_WIDTH(HASH_KEY_WIDTH), 
        .HASH_WIDTH(HASH_WIDTH)
    ) tb_hash_func_0 (
        // 拼接顺序必须与 Parser 内部提取 Key 的顺序严格一致
        .key_in({hit_dst_mac_0, hit_src_mac_0, hit_src_ip_0, hit_dst_ip_0, hit_src_port_0, hit_dst_port_0}),
        .hash_out(hit_hash_value_0)
    );

    reg [47:0] hit_src_mac_1  = 48'h112233DDEEFF;
    reg [47:0] hit_dst_mac_1  = 48'hAABBCC445566;
    reg [31:0] hit_src_ip_1   = 32'h0A000111;
    reg [31:0] hit_dst_ip_1   = 32'h0A000222;
    reg [15:0] hit_src_port_1 = 16'd1234;
    reg [15:0] hit_dst_port_1 = 16'd5678;
    reg        hit_root_info_1 = 1'b0;


    reg [15:0] nohit_dst_port_1 = 16'hffff;

    
    wire [HASH_WIDTH-1:0]     hit_hash_value_1;
    reg  [HASH_KEY_WIDTH-1:0] full_hit_key_1;

    // 实例化 Hash 函数 (Helper)，用于计算 Index
    // 注意：这里的参数必须与 parser.v 内部实例化的一致
    hash_function #(
        .KEY_WIDTH(HASH_KEY_WIDTH), 
        .HASH_WIDTH(HASH_WIDTH)
    ) tb_hash_func_1 (
        // 拼接顺序必须与 Parser 内部提取 Key 的顺序严格一致
        .key_in({hit_dst_mac_1, hit_src_mac_1, hit_src_ip_1, hit_dst_ip_1, hit_src_port_1, hit_dst_port_1}),
        .hash_out(hit_hash_value_1)
    );

    // Main Test
    initial begin
        rst_n = 0;
        s_axis_tvalid = 0;
        s_axis_tlast = 0;
        s_axis_tdata = 0;
        s_axis_tkeep = 0;

        m_axis_tready = 1;
        ingress_port = 0;

        #100;
        rst_n = 1;
        #100000;

        // ------------------------------------------------------------
        // Step 1: Configure Hash Table (Backdoor Write)
        // ------------------------------------------------------------
        @(posedge clk);
        full_hit_key_0 = {hit_dst_mac_0,hit_src_mac_0,hit_src_ip_0,hit_dst_ip_0,hit_src_port_0,hit_dst_port_0};
        dut.allreduce_parser.u_connection_table.table_mem[hit_hash_value_0][0] = {hit_root_info_0, full_hit_key_0, hit_valid}; 

        @(posedge clk);
        full_hit_key_1 = {hit_dst_mac_1,hit_src_mac_1,hit_src_ip_1,hit_dst_ip_1,hit_src_port_1,hit_dst_port_1};
        dut.allreduce_parser.u_connection_table.table_mem[hit_hash_value_1][0] = {hit_root_info_1, full_hit_key_1, hit_valid}; 


        // ------------------------------------------------------------
        // Step 2: Send Packet 1 (Port 0) -> Expect Buffering (to aggregator)
        // ------------------------------------------------------------
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0000),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // # 60;
        // ------------------------------------------------------------
        // Step 3: Send Packet 2 (Port 1) -> Expect Buffering (to aggregator)
        // ------------------------------------------------------------
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0000),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2222)
        // );



        // // ------------------------------------------------------------
        // // pipline test for more packet -> lookup hit pkt ~!
        // // ------------------------------------------------------------
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0000),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2222)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0000),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );                                                                  // √ root_up -> port retrans

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2222)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2222)                          // √ no_root_up 
        // );

        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)                          // √ down_broadcast -> down_down_broadcast
        // );
        
        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0000),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );                                                              // √ root_up -> down_down_broadcast


        // # 100;

        // // formal test for 2-layer-tree
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

    

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2222)
        // );

        

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2222)
        // );

        // #80;


        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0004),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2222)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0004),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h4444_4444)
        // );

        // #80;

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0004),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2222)
        // );

        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0004),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // #60;
        // #10;
        
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0004),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2222)
        // );

        // # 60 ;

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0004),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2222)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2222)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2222)
        // );

        //-------------------------------------------
        // #60;
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2222)
        // );


        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1112)
        // );

        // -------------------------------------------
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h4444_4444)
        // );

        // #60;

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2222)
        // );


        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h8888_8888)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h4444_4444)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );

        // --------------------------------------------------------------------------
        // noroot_FAN_trans -> noroot_FAN_trans
        // --------------------------------------------------------------------------
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0004),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0004),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );


 
        // --------------------------------------------------------------------------
        // 0.浮点计算:root_FAN_trans -> root_FAN_trans
        // --------------------------------------------------------------------------

        // 根节点上行
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0000),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(gen_float_vec(FP_1_0))
        // );



        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0000),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(gen_float_vec(FP_2_0))
        // );

        // 中间节点上行+ 广播
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0000),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(gen_float_vec(FP_1_0))
        // );

        // # 80;

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0000),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(gen_float_vec(FP_2_0))
        // );

        // # 80;

        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0000),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(gen_float_vec(FP_1_0))
        // );


        // --------------------------------------------------------------------------
        // 1.root_FAN_trans -> root_FAN_trans
        // --------------------------------------------------------------------------
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );

        // --------------------------------------------------------------------------
        // 2.noroot_FAN_trans -> root_FAN_trans -> down_broadcast
        // --------------------------------------------------------------------------
        send_pack(
            .in_port(8'd0),
            .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
            .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
            .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
            .qpn(32'h0001), .psn(32'h0000),
            .opcode(OPCODE_FIRST),
            .payload_start_val(512'h1111_1111)
        );

        send_pack(
            .in_port(8'd1),
            .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
            .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
            .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
            .qpn(32'h0001), .psn(32'h0000),
            .opcode(OPCODE_FIRST),
            .payload_start_val(512'h1111_1111)
        );
        

        
        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0000),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd3),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0000),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );

        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0000),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h7777_7777)
        // );

 

        // --------------------------------------------------------------------------
        // 3.noroot_FAN_trans -> noroot_FAN_trans -> down_broadcast -> down_broadcast -> noroot_FAN_trans
        // --------------------------------------------------------------------------
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2222)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2222)
        // );

        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );


        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );

        // --------------------------------------------------------------------------
        // 4.root_FAN_trans -> nohit -> root_FAN_trans
        // --------------------------------------------------------------------------
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );

        // //  #160;

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // --------------------------------------------------------------------------
        // 5.noroot_FAN_trans -> nohit -> root_FAN_trans -> nohit -> down_broadcast
        // 存在root_up_down_broadcast -> root_down_down_broadcast
        // --------------------------------------------------------------------------
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2222)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2222)
        // );
   
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h4444_4444)
        // );

        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h8888_8888)
        // );

        // --------------------------------------------------------------------------
        // 6.noroot_FAN_trans -> nohit -> noroot_FAN_trans -> nohit -> down_broadcast -> nohit ->  
        //   down_broadcast -> nohit -> noroot_FAN_trans
        // --------------------------------------------------------------------------
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h4444_4444)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );

        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_3333)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h4444_4444)
        // );

        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h6666_3333)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
  
        // --------------------------------------------------------------------------
        // 7.root_FAN_trans -> FAN_retrans -> root_FAN_trans
        // --------------------------------------------------------------------------
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h4444_4444)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h4444_4444)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h4444_4444)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h4444_4444)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );

        // --------------------------------------------------------------------------
        // 8.root_FAN_trans -> nohit -> FAN_retrans -> root_FAN_trans
        // --------------------------------------------------------------------------
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h4444_4444)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h4444_4444)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h4444_4444)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h4444_4444)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h4444_4444)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );

        // --------------------------------------------------------------------------
        // 10.noroot_FAN_trans -> port_retans -> root_FAN_trans -> down_broadcast
        // --------------------------------------------------------------------------
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );

        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );


        // --------------------------------------------------------------------------
        // 11.noroot_FAN_trans -> port_retans -> root_FAN_trans -> FAN_retrans -> down_broadcast
        // --------------------------------------------------------------------------
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );


        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );

        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );

        // --------------------------------------------------------------------------
        // 12.noroot_FAN_trans ->nohit -> port_retans -> nohit -> root_FAN_trans -> FAN_retrans -> nohit -> down_broadcast -> nohit
        // --------------------------------------------------------------------------
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h4444_4444)
        // );


        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h4444_4444)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h6666_6666)
        // );

        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_3333)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h7777_7777)
        // );

        // --------------------------------------------------------------------------
        // 13.noroot_FAN_trans -> port_retans -> noroot_FAN_trans -> down_broadcast  -> port_retans -> down_broadcast -> port_retans -> noroot_FAN_trans
        // --------------------------------------------------------------------------
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_1111)
        // );

        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2221)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2221_1111)
        // );

        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2222_2221)
        // );


        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h2221_1111)
        // );


        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0004),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0004),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h5555_5555)
        // );


        // -------------------测试上行聚合吞吐（子节点）-------------------：
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0000),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0004),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0005),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0006),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0007),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0008),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0009),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h000a),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h000b),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h000c),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h000d),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h000e),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h000f),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // //
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0000),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0004),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0005),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0006),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0007),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0008),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0009),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h000a),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h000b),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h000c),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h000d),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h000e),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h000f),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // //

        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0000),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0004),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0005),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0006),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0007),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0008),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0009),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h000a),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h000b),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h000c),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h000d),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h000e),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd2),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h000f),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
    


        // --------------上行聚合（根节点）------------------------
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0000),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0004),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0005),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0006),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0007),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0008),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0009),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h000a),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h000b),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h000c),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h000d),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd0),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h000e),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );


        // # 50;

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_1), .dst_mac(hit_dst_mac_1),
        //     .src_ip(hit_src_ip_1), .dst_ip(hit_dst_ip_1),
        //     .src_port(hit_src_port_1), .dst_port(hit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0000),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0001),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0003),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0004),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0005),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0006),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0007),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0008),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h0009),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h000a),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h000b),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h000c),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h000d),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(hit_dst_port_0),
        //     .qpn(32'h0001), .psn(32'h000e),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h1111_1111)
        // );

        // 非聚合报文
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );

        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );
        // send_pack(
        //     .in_port(8'd1),
        //     .src_mac(hit_src_mac_0), .dst_mac(hit_dst_mac_0),
        //     .src_ip(hit_src_ip_0), .dst_ip(hit_dst_ip_0),
        //     .src_port(hit_src_port_0), .dst_port(nohit_dst_port_1),
        //     .qpn(32'h0001), .psn(32'h0002),
        //     .opcode(OPCODE_FIRST),
        //     .payload_start_val(512'h3333_3333)
        // );


    
        # 400;
        $finish;

    end




endmodule
