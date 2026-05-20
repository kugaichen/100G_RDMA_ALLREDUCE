`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/25 20:08:50
// Design Name: 
// Module Name: aggregator_top_tb
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


module aggregator_top_tb;
    parameter METADATA_LEN                  = 2*8+3+5;
    parameter PAYLOAD_ITEM_WIDTH            = 512;
    parameter INGRESS_PROT_NUM              = 2;
    parameter RING_SLOT_WIDTH               = 8;
    parameter WINDOWSIZE                    = RING_SLOT_WIDTH;
    parameter ADDR_WIDTH                    = 8;
    parameter DATA_WIDTH                    = 32;
    parameter OPCODE_WIDTH                  = 8;

    parameter OPCODE_ACK                    = 8'h11;
    parameter OPCODE_FIRST                  = 8'h0;
    parameter OPCODE_MIDDLE                 = 8'h1;
    parameter OPCODE_LAST                   = 8'h2;
    parameter OPCODE_SEND_ONLY              = 8'h4;

    parameter PAYLOAD_ITEM_NUM              = 2 * WINDOWSIZE;
    parameter PAYLOAD_ITEM_COUNT_WIDTH      = $clog2(PAYLOAD_ITEM_NUM);
    parameter BUFFER_SLOTS                  = 2 * WINDOWSIZE;
    parameter BUFFER_SLOTS_WIDTH            = $clog2(BUFFER_SLOTS);
    parameter FAN_IN                        = INGRESS_PROT_NUM;
    parameter FAN_IN_WIDTH                  = $clog2(FAN_IN);


    reg                                                 clk;
    reg                                                 rst_n;

    // Input from Parser
    reg [METADATA_LEN-1:0]                              parser_agg_metadata;
    reg [OPCODE_WIDTH-1:0]                              parser_agg_opcode;
    reg                                                 parser_agg_payload_fire_en;
    reg [RING_SLOT_WIDTH+PAYLOAD_ITEM_COUNT_WIDTH-1:0]  parser_payload_wr_addr;
    reg [PAYLOAD_ITEM_WIDTH-1:0]                        parser_payload_wr_data;
    reg                                                 parser_payload_wr_en;

    // Backpressure from Deparser
    reg                                                 deparser_in_ready;

    // Outputs
    wire                                                parser_out_ready;
    wire [METADATA_LEN-1:0]                             metadata_with_type_out_to_deparser;
    wire                                                Typer_ack_build_en_out_to_deparser;
    wire                                                Typer_ack_down_en_out_to_deparser;
    wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]      aggregate_bram_payload_out_to_deparser;
    wire                                                aggregator_FAN_retrans_en_out_to_deparser;
    wire                                                aggregator_FAN_first_trans_en_out_to_deparser;
    wire                                                aggregator_down_broadcast_en_out_to_deparser;
    wire                                                aggregator_port_retrans_en_out_to_deparser;
    

    initial begin
        clk = 0;
        forever begin
            #5 clk = ~clk;
        end
    end

    aggregator_core_top #(
        .METADATA_LEN(METADATA_LEN),
        .PAYLOAD_ITEM_WIDTH(PAYLOAD_ITEM_WIDTH),
        .INGRESS_PROT_NUM(INGRESS_PROT_NUM),
        .RING_SLOT_WIDTH(RING_SLOT_WIDTH),
        .WINDOWSIZE(WINDOWSIZE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .OPCODE_WIDTH(OPCODE_WIDTH),
        .OPCODE_ACK(OPCODE_ACK),
        .OPCODE_FIRST(OPCODE_FIRST),
        .OPCODE_MIDDLE(OPCODE_MIDDLE),
        .OPCODE_LAST(OPCODE_LAST),
        .OPCODE_SEND_ONLY(OPCODE_SEND_ONLY)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        
        .parser_agg_metadata(parser_agg_metadata),
        .parser_agg_opcode(parser_agg_opcode),
        .parser_agg_payload_fire_en(parser_agg_payload_fire_en),
        .parser_payload_wr_addr(parser_payload_wr_addr),
        .parser_payload_wr_data(parser_payload_wr_data),
        .parser_payload_wr_en(parser_payload_wr_en),
        .parser_out_ready(parser_out_ready),
        
        .deparser_in_ready(deparser_in_ready),
        .metadata_with_type_out_to_deparser(metadata_with_type_out_to_deparser),
        .Typer_ack_build_en_out_to_deparser(Typer_ack_build_en_out_to_deparser),
        .Typer_ack_down_en_out_to_deparser(Typer_ack_down_en_out_to_deparser),
        .aggregate_bram_payload_out_to_deparser(aggregate_bram_payload_out_to_deparser),
        .aggregator_FAN_retrans_en_out_to_deparser(aggregator_FAN_retrans_en_out_to_deparser),
        .aggregator_FAN_first_trans_en_out_to_deparser(aggregator_FAN_first_trans_en_out_to_deparser),
        .aggregator_down_broadcast_en_out_to_deparser(aggregator_down_broadcast_en_out_to_deparser),
        .aggregator_port_retrans_en_out_to_deparser(aggregator_port_retrans_en_out_to_deparser)
    );


    // Task: initialize the payload bram
    task write_payload;
        input [7:0] port;
        input [ADDR_WIDTH-1:0] slot_idx;
        input is_root;
        input [PAYLOAD_ITEM_WIDTH-1:0] start_data;
        integer i;
        begin
            $display("[WR] Writing Payload: Port=%d, Slot=%d, StartData=%h", port, slot_idx, start_data);
            
            parser_agg_metadata[7:0] = port;
            parser_agg_metadata[15:8] = slot_idx;
            parser_agg_metadata[16] = is_root;

            for (i = 0; i < PAYLOAD_ITEM_NUM; i = i + 1) begin
                @(posedge clk);
                parser_payload_wr_en = 1;
                parser_payload_wr_addr = {slot_idx, i[3:0]}; 
                parser_payload_wr_data = start_data + i;
            end

            @(posedge clk);
            parser_payload_wr_en = 0;
            parser_payload_wr_data = 0;
            parser_payload_wr_addr = 0;
        end
    endtask

    task send_packet;
        input [7:0] port;
        input [7:0] psn; // 这里假设 PSN 对应 Slot Index
        input is_root;
        input [7:0] opcode;
        begin
            $display("[SEND] Sending Packet: Port=%d, PSN=%d, Root=%b, Opcode=%h", port, psn, is_root, opcode);
            
            // 等待 DUT Ready
            wait(parser_out_ready == 1);
            @(posedge clk);

            // 构造 Metadata (参考 Typer.v 的解析逻辑)
            // [7:0]   = Ingress Port
            // [15:8]  = PSN
            // [16]    = Root Info
            parser_agg_metadata = 0;
            parser_agg_metadata[7:0] = port;
            parser_agg_metadata[15:8] = psn;
            parser_agg_metadata[16] = is_root;
            
            parser_agg_opcode = opcode;
            parser_agg_payload_fire_en = 1;

            @(posedge clk);
            parser_agg_payload_fire_en = 0;
        end
    endtask


    task random_backpressure;
        input integer duration;
        integer i;
        begin
            for (i=0; i<duration; i=i+1) begin
                @(posedge clk);
                if ($urandom % 100 < 30) deparser_in_ready <= 0;
                else                     deparser_in_ready <= 1;
            end
            deparser_in_ready <= 1;
        end
    endtask


    // Test
    initial begin

        // reset
        rst_n = 0;
        parser_agg_metadata = 0;
        parser_agg_opcode = 0;
        parser_agg_payload_fire_en = 0;
        parser_payload_wr_addr = 0;
        parser_payload_wr_data = 0;
        parser_payload_wr_en = 0;
        deparser_in_ready = 0; 

        #20;
        rst_n = 1;
        #20;
        deparser_in_ready = 1; // 默认下游是 Ready 的

        // ---------------------------------------------------------------------
        // 场景 1: 基础功能测试 (Slot 1, Port 0 -> Port 1)
        // ---------------------------------------------------------------------
        //  写入payload数据
        #20;
        write_payload(8'd0, 8'd1, 1'b0, 512'hAAAA_0000_0000_0000);        // √ noroot_up_data_port_0  
        send_packet(8'd0, 8'd1, 1'b0, OPCODE_FIRST);

        // #70;
        write_payload(8'd1, 8'd1, 1'b0, 512'h0000_BBBB_0000_0000);        // √ noroot_up_data_port_1   -> up_port_trans
        send_packet(8'd1, 8'd1, 1'b0, OPCODE_FIRST);

        #70;
        send_packet(8'd0, 8'd2, 1'b1, OPCODE_FIRST);

        #70;
        send_packet(8'd1, 8'd2, 1'b1, OPCODE_FIRST);                      // √ root_up                -> port retrans


        #180;
        send_packet(8'd0, 8'd1, 1'b0, OPCODE_FIRST);    

        #180;
        send_packet(8'd1, 8'd1, 1'b0, OPCODE_FIRST);                      // √ noroot_up              -> all ports retrans again -> FAN_retrans

        #80;
        write_payload(8'd2, 8'd1, 1'b0, 512'hCCCC_CCCC_0000_0000);        // √ down_broadcast         -> down_down_broadcast
        send_packet(8'd2, 8'd1, 1'b0, OPCODE_FIRST);

        #80;
        write_payload(8'd1, 8'd1, 1'b0, 512'h0000_BBBB_0000_0000);        // √ noroot_up_data_port_1  -> FAN already ok -> up_port_retrans
        send_packet(8'd1, 8'd1, 1'b0, OPCODE_FIRST);

        #80;
        write_payload(8'd0, 8'd1, 1'b0, 512'hAAAA_0000_0000_0000);        // √ noroot_up_data_port_0  
        send_packet(8'd0, 8'd1, 1'b0, OPCODE_FIRST);

        #80;
        write_payload(8'd1, 8'd1, 1'b0, 512'h0000_BBBB_0000_0000);        // √ noroot_up_data_port_1   -> up_port_trans
        send_packet(8'd1, 8'd1, 1'b0, OPCODE_FIRST);

        #280;
        write_payload(8'd0, 8'd2, 1'b1, 512'h1111_BBBB_0000_0000);        // √ root_up_data_port_1   -> up_port_trans
        send_packet(8'd0, 8'd2, 1'b1, OPCODE_FIRST);

        #80;
        write_payload(8'd1, 8'd2, 1'b1, 512'hBBBB_1111_0000_0000);        // √ root_up_data_port_1   -> up_port_trans -> up_down_broadcast
        send_packet(8'd1, 8'd2, 1'b1, OPCODE_FIRST);                      // 这里应该是一定会转发广播，所以FAN一定会成功，后面的重传都是port retrans

        #180;
        send_packet(8'd0, 8'd2, 1'b1, OPCODE_FIRST);

        #180;
        send_packet(8'd1, 8'd2, 1'b1, OPCODE_FIRST);                      // √ root_up                -> port retrans

        // #20;
        // ---------------------------------------------------------------------
        // 场景 2: 流水线压力测试 - 不同 Slot 交错 (Interleaving)
        // ---------------------------------------------------------------------
        // write_payload(8'd0, 8'd3, 1'b0, 512'h1111_0000_0000_0000);
        // send_packet(8'd0, 8'd3, 1'b0, OPCODE_FIRST);

        // write_payload(8'd1, 8'd3, 1'b0, 512'h2222_0000_0000_0000);
        // send_packet(8'd1, 8'd3, 1'b0, OPCODE_FIRST);

        // write_payload(8'd0, 8'd2, 1'b1, 512'h1111_0000_0000_0000);
        // send_packet(8'd0, 8'd2, 1'b1, OPCODE_FIRST);

        // write_payload(8'd1, 8'd2, 1'b1, 512'h2222_0000_0000_0000);
        // send_packet(8'd1, 8'd2, 1'b1, OPCODE_FIRST);

        // write_payload(8'd1, 8'd3, 1'b0, 512'h2222_0000_0000_0000);
        // send_packet(8'd1, 8'd3, 1'b0, OPCODE_FIRST);

        // write_payload(8'd0, 8'd3, 1'b0, 512'h1111_0000_0000_0000);
        // send_packet(8'd0, 8'd3, 1'b0, OPCODE_FIRST);

        // write_payload(8'd2, 8'd3, 1'b0, 512'h4444_0000_0000_0000);
        // send_packet(8'd2, 8'd3, 1'b0, OPCODE_FIRST);

        // write_payload(8'd1, 8'd4, 1'b0, 512'h2222_0000_0000_0000);
        // send_packet(8'd1, 8'd4, 1'b0, OPCODE_MIDDLE);

        // write_payload(8'd1, 8'd4, 1'b0, 512'h2222_0000_0000_0000);
        // send_packet(8'd1, 8'd4, 1'b0, OPCODE_MIDDLE);

        // write_payload(8'd0, 8'd4, 1'b0, 512'h2222_0000_0000_0000);
        // send_packet(8'd0, 8'd4, 1'b0, OPCODE_MIDDLE);



        // ---------------------------------------------------------------------
        // 场景 3: 反压测试 (Backpressure)
        // ---------------------------------------------------------------------
        // 启动一个并行线程产生随机反压
        // fork
        //     random_backpressure(500); // 持续 500 个周期随机拉低 ready
        //     begin
        //         // 在反压期间发送正常的数据流
        //         write_payload(8'd0, 8'd10, 1'b0, 512'hAAAA_AAAA_0000_0000);
        //         send_packet(8'd0, 8'd10, 1'b0, OPCODE_FIRST);

        //         write_payload(8'd1, 8'd10, 1'b0, 512'h5555_5555_0000_0000);
        //         send_packet(8'd1, 8'd10, 1'b0, OPCODE_FIRST);
                
        //         // 检查波形：to_deparser_valid 是否只在 deparser_in_ready=1 时拉高
        //         // 检查波形：内部状态机是否正确 Stall
        //     end
        // join


        // ---------------------------------------------------------------------
        // 场景 4: 增强版反压测试
        // --------------------------------------------------------------------
        // fork
        //     // 1. 制造恶劣的反压环境
        //     begin
        //         // 阶段 A: 随机反压 (模拟网络抖动)
        //         random_backpressure(10); 
                
        //         #10;
        //         // 阶段 B: 完全堵死 (模拟下游拥塞)
        //         deparser_in_ready = 0;
        //         #600; // 堵塞 500ns
                
        //         // 阶段 C: 瞬间释放
        //         @(posedge clk);
        //         deparser_in_ready = 1;
        //     end

        //     // 2. 在此期间发送聚合任务
        //     begin
        //         // 发送 Port 0 数据 (Slot 10)
        //         write_payload(8'd0, 8'd10, 1'b0, 512'hAAAA_AAAA_0000_0000);
        //         send_packet(8'd0, 8'd10, 1'b0, OPCODE_FIRST);

        //         // 发送 Port 1 数据 (Slot 10) -> 应该触发聚合
        //         write_payload(8'd1, 8'd10, 1'b0, 512'h5555_5555_0000_0000);
        //         send_packet(8'd1, 8'd10, 1'b0, OPCODE_FIRST);
        //     end
        // join


        // ---------------------------------------------------------------------
        // 场景 5: 多包聚合序列 (FIRST -> MIDDLE -> LAST) // 存在问题 -> 测试无意义
        // ---------------------------------------------------------------------
        // // 1. 发送 FIRST 包
        // write_payload(8'd0, 8'd5, 1'b0, 512'h1111_1111_0000_0000);
        // send_packet(8'd0, 8'd5, 1'b0, OPCODE_FIRST);
        
        // write_payload(8'd1, 8'd5, 1'b0, 512'h2222_2222_0000_0000);
        // send_packet(8'd1, 8'd5, 1'b0, OPCODE_FIRST); 
        // // 预期: 输出聚合结果 3333... Opcode=FIRST

        // #50;

        // // 2. 发送 MIDDLE 包 (同一个 Slot 5)
        // write_payload(8'd0, 8'd5, 1'b0, 512'h1010_1010_0000_0000);
        // send_packet(8'd0, 8'd5, 1'b0, OPCODE_MIDDLE);
        
        // write_payload(8'd1, 8'd5, 1'b0, 512'h2020_2020_0000_0000);
        // send_packet(8'd1, 8'd5, 1'b0, OPCODE_MIDDLE);
        // // 预期: 输出聚合结果 3030... Opcode=MIDDLE

        // #50;

        // // 3. 发送 LAST 包
        // write_payload(8'd0, 8'd5, 1'b0, 512'h0001_0001_0000_0000);
        // send_packet(8'd0, 8'd5, 1'b0, OPCODE_LAST);
        
        // write_payload(8'd1, 8'd5, 1'b0, 512'h0002_0002_0000_0000);
        // send_packet(8'd1, 8'd5, 1'b0, OPCODE_LAST);
        // // 预期: 输出聚合结果 0003... Opcode=LAST
        
        // // 4. 发送 ACK 包
        // write_payload(8'd0, 8'd5, 1'b0, 512'h0111_0001_0000_0000);
        // send_packet(8'd0, 8'd5, 1'b0, OPCODE_ACK);
        
        // write_payload(8'd1, 8'd5, 1'b0, 512'h0222_0002_0000_0000);
        // send_packet(8'd1, 8'd5, 1'b0, OPCODE_ACK);


        // ---------------------------------------------------------------------
        // 场景 5: 窗口满载测试 (Window Saturation)
        // ---------------------------------------------------------------------   
        
        // no-root
        // 1. 填满所有 Slot (假设 WINDOWSIZE=8, Slot 0-7)
        // 只发送 Port 0，让它们都处于 "Waiting for Port 1" 的状态
        // write_payload(8'd0, 8'd0, 1'b0, 512'h1); send_packet(8'd0, 8'd0, 1'b0, OPCODE_FIRST);
        // write_payload(8'd0, 8'd1, 1'b0, 512'h2); send_packet(8'd0, 8'd1, 1'b0, OPCODE_FIRST);
        // write_payload(8'd0, 8'd2, 1'b0, 512'h3); send_packet(8'd0, 8'd2, 1'b0, OPCODE_FIRST);
        // write_payload(8'd0, 8'd3, 1'b0, 512'h4); send_packet(8'd0, 8'd3, 1'b0, OPCODE_FIRST);
        // write_payload(8'd0, 8'd4, 1'b0, 512'h5); send_packet(8'd0, 8'd4, 1'b0, OPCODE_FIRST);
        // write_payload(8'd0, 8'd5, 1'b0, 512'h6); send_packet(8'd0, 8'd5, 1'b0, OPCODE_FIRST);
        // write_payload(8'd0, 8'd6, 1'b0, 512'h7); send_packet(8'd0, 8'd6, 1'b0, OPCODE_FIRST);
        // write_payload(8'd0, 8'd7, 1'b0, 512'h8); send_packet(8'd0, 8'd7, 1'b0, OPCODE_FIRST);
        
        // #100;
        // // 此时系统应该存储了所有数据，但没有输出。
        
        // // 2. 逐个释放 (发送 Port 1)
        // write_payload(8'd1, 8'd0, 1'b0, 512'h8); send_packet(8'd1, 8'd0, 1'b0, OPCODE_FIRST);
        // write_payload(8'd1, 8'd1, 1'b0, 512'h7); send_packet(8'd1, 8'd1, 1'b0, OPCODE_FIRST);
        // write_payload(8'd1, 8'd2, 1'b0, 512'h6); send_packet(8'd1, 8'd2, 1'b0, OPCODE_FIRST);
        // write_payload(8'd1, 8'd3, 1'b0, 512'h5); send_packet(8'd1, 8'd3, 1'b0, OPCODE_FIRST);
        // write_payload(8'd1, 8'd4, 1'b0, 512'h4); send_packet(8'd1, 8'd4, 1'b0, OPCODE_FIRST);
        // write_payload(8'd1, 8'd5, 1'b0, 512'h3); send_packet(8'd1, 8'd5, 1'b0, OPCODE_FIRST);
        // write_payload(8'd1, 8'd6, 1'b0, 512'h2); send_packet(8'd1, 8'd6, 1'b0, OPCODE_FIRST);
        // write_payload(8'd1, 8'd7, 1'b0, 512'h1); send_packet(8'd1, 8'd7, 1'b0, OPCODE_FIRST);

        // #100;
        // // root
        // // 1. 填满所有 Slot (假设 WINDOWSIZE=8, Slot 0-7)
        // // 只发送 Port 0，让它们都处于 "Waiting for Port 1" 的状态
        // write_payload(8'd0, 8'd0, 1'b1, 512'h1); send_packet(8'd0, 8'd0, 1'b1, OPCODE_FIRST);
        // write_payload(8'd0, 8'd1, 1'b1, 512'h2); send_packet(8'd0, 8'd1, 1'b1, OPCODE_FIRST);
        // write_payload(8'd0, 8'd2, 1'b1, 512'h3); send_packet(8'd0, 8'd2, 1'b1, OPCODE_FIRST);
        // write_payload(8'd0, 8'd3, 1'b1, 512'h4); send_packet(8'd0, 8'd3, 1'b1, OPCODE_FIRST);
        // write_payload(8'd0, 8'd4, 1'b1, 512'h5); send_packet(8'd0, 8'd4, 1'b1, OPCODE_FIRST);
        // write_payload(8'd0, 8'd5, 1'b1, 512'h6); send_packet(8'd0, 8'd5, 1'b1, OPCODE_FIRST);
        // write_payload(8'd0, 8'd6, 1'b1, 512'h7); send_packet(8'd0, 8'd6, 1'b1, OPCODE_FIRST);
        // write_payload(8'd0, 8'd7, 1'b1, 512'h8); send_packet(8'd0, 8'd7, 1'b1, OPCODE_FIRST);
        
        // #100;
        // // 此时系统应该存储了所有数据，但没有输出。
        
        // // 2. 逐个释放 (发送 Port 1)
        // write_payload(8'd1, 8'd0, 1'b1, 512'h8); send_packet(8'd1, 8'd0, 1'b1, OPCODE_FIRST);
        // write_payload(8'd1, 8'd1, 1'b1, 512'h7); send_packet(8'd1, 8'd1, 1'b1, OPCODE_FIRST);
        // write_payload(8'd1, 8'd2, 1'b1, 512'h6); send_packet(8'd1, 8'd2, 1'b1, OPCODE_FIRST);
        // write_payload(8'd1, 8'd3, 1'b1, 512'h5); send_packet(8'd1, 8'd3, 1'b1, OPCODE_FIRST);
        // write_payload(8'd1, 8'd4, 1'b1, 512'h4); send_packet(8'd1, 8'd4, 1'b1, OPCODE_FIRST);
        // write_payload(8'd1, 8'd5, 1'b1, 512'h3); send_packet(8'd1, 8'd5, 1'b1, OPCODE_FIRST);
        // write_payload(8'd1, 8'd6, 1'b1, 512'h2); send_packet(8'd1, 8'd6, 1'b1, OPCODE_FIRST);
        // write_payload(8'd1, 8'd7, 1'b1, 512'h1); send_packet(8'd1, 8'd7, 1'b1, OPCODE_FIRST);
        

        #270
        $finish;

    end






endmodule
