`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/25 16:35:44
// Design Name: 
// Module Name: tb_retrans_bram_arbiter_top
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


module tb_retrans_bram_arbiter_top;

    parameter FAN_IN = 2;
    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 8;
    parameter TEST_ITERATIONS = 200; // 定义测试迭代次数
    parameter TIMEOUT_CYCLES = TEST_ITERATIONS * 20; // 定义超时周期数

    reg                   clk;
    reg                   rst_n;
    reg                   in_valid;
    wire                  in_ready;
    reg [23:0]            in_metadata; // [16]:root, [15:8]:idx, [7:0]:port

    wire                  out_valid;
    reg                   out_ready;
    wire                  aggregate_buffer_en;
    wire                  read_buffer_en;
    wire                  FAN_retrans_check_en;

    // DUT
    retrans_bram_arbiter_top #(
        .FAN_IN(FAN_IN),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_metadata(in_metadata),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .aggregate_buffer_en(aggregate_buffer_en),
        .read_buffer_en(read_buffer_en),
        .FAN_retrans_check_en(FAN_retrans_check_en)
    );

    // 时钟生成
    initial clk = 0;
    always #5 clk = ~clk; // 10ns 周期

    // 复位序列
    task reset_dut;
        begin
            rst_n = 1'b0;
            in_valid = 1'b0;
            in_metadata = 24'b0;
            out_ready = 1'b1;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    //----------------------------------------------------------------
    // 激励生成任务
    //----------------------------------------------------------------
    // 发送单个数据包的任务，处理 valid/ready 握手
    task send_packet(input [23:0] metadata);
        begin
            // wait (in_ready); // 等待 DUT 准备好接收
            @(posedge clk);
            in_valid    <= 1'b1;
            in_metadata <= metadata;
            // @(posedge clk);
            // in_valid    <= 1'b0;
        end
    endtask

    //----------------------------------------------------------------
    // 主测试流程
    //----------------------------------------------------------------
    integer i;
    initial begin

        // BRAM 预加载：在复位后，为地址 0-7 加载初始状态
        // 这对于测试重传逻辑 (is_retrans) 至关重要
        for (i = 0; i < 8; i = i + 1) begin
            dut.arrival_state_uut.arrival_state[i] = 32'h00000000;
            dut.degree_bram_uut.mem[i] = 32'h00000000;
        end

        reset_dut();
        
        // --- 场景 1: 单个数据包测试 ---
        // 发送一个请求到地址 2，端口 1。由于地址 2 已有数据，这会触发重传逻辑
        send_packet({7'b0, 1'b1, 8'h02, 8'h01});
        repeat(1) @(posedge clk);
        in_valid    <= 1'b0;
        
        // 等待一段时间以观察结果
        repeat(10) @(posedge clk);


        // 测试连续访问arrival和degree的变化
        send_packet({7'b0, 1'b1, 8'h03, 8'h00}); // 地址 3, port 0 (首次到达)
        send_packet({7'b0, 1'b1, 8'h03, 8'h01}); // 地址 3, port 1 (重传)

        repeat(1) @(posedge clk);
        in_valid    <= 1'b0;

        repeat(10) @(posedge clk);

        // --- 场景 2: 背靠背满载测试 ---
        // 连续发送四个请求，测试流水线是否能被填满并持续处理
        send_packet({7'b0, 1'b1, 8'h03, 8'h00}); // 地址 3, port 0 (首次到达)
        // repeat(1) @(posedge clk);
        // in_valid    <= 1'b0;
        send_packet({7'b0, 1'b1, 8'h03, 8'h01}); // 地址 3, port 1 (重传)
        // repeat(1) @(posedge clk);
        // in_valid    <= 1'b0;
        send_packet({7'b0, 1'b1, 8'h04, 8'h00}); // 地址 4, port 0 (首次到达)
        // repeat(1) @(posedge clk);
        // in_valid    <= 1'b0;
        send_packet({7'b0, 1'b1, 8'h04, 8'h01}); // 地址 4, port 1 (重传)
        repeat(2) @(posedge clk);
        in_valid    <= 1'b0;

        // repeat(1) @(posedge clk);
        // in_valid    <= 1'b0;

        // 等待一段时间
        repeat(10) @(posedge clk);

        // --- 场景 3: 随机压力测试 ---
        // 在随机反压下，发送大量随机请求
        // for (i = 0; i < TEST_ITERATIONS; i = i + 1) begin
        //     send_packet({
        //         7'h0,                      // 保留位
        //         $random % 2,               // 随机的 root 标志
        //         $random % 8,              // 随机地址 (0-15)
        //         $random % (FAN_IN + 1)     // 随机端口 (0-2, 包含一个越界值)
        //     });
        // end

        // 等待所有操作完成
        repeat(50) @(posedge clk);
        $finish;
    end

    //----------------------------------------------------------------
    // 随机下游反压模拟
    //----------------------------------------------------------------
    // initial begin
    //     // 等待复位结束
    //     wait (rst_n === 1'b1);

    //     forever begin
    //         // 保持 out_ready 高电平一段随机时间 (5-20 周期)
    //         out_ready <= 1'b1;
    //         repeat (5 + $random % 16) @(posedge clk);

    //         // 保持 out_ready 低电平一段随机时间 (1-10 周期)，模拟下游阻塞
    //         out_ready <= 1'b0;
    //         repeat (1 + $random % 10) @(posedge clk);
    //     end
    // end


endmodule


