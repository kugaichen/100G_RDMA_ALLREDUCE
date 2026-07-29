`timescale 1ns / 1ps
module tb_icrc_calc;

    parameter AXIS_DATA_WIDTH = 512;
    parameter AXIS_KEEP_WIDTH = 64;

    reg clk, rst_n;
    reg [AXIS_DATA_WIDTH-1:0]  s_tdata;
    reg [AXIS_KEEP_WIDTH-1:0]  s_tkeep;
    reg                        s_tvalid;
    reg                        s_tlast;
    wire                       s_tready;
    reg [2:0]                  s_route_type;
    reg                        s_is_aggregated;
    reg [7:0]                  s_agg_ingress;

    wire [AXIS_DATA_WIDTH-1:0] m_tdata;
    wire [AXIS_KEEP_WIDTH-1:0] m_tkeep;
    wire                       m_tvalid;
    wire                       m_tlast;
    reg                        m_tready;
    wire [2:0]                 m_route_type;
    wire                       m_is_aggregated;
    wire [7:0]                 m_agg_ingress;

    icrc_calc #(
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
        .AXIS_KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .FIFO_DEPTH(32)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(s_tdata),
        .s_axis_tkeep(s_tkeep),
        .s_axis_tvalid(s_tvalid),
        .s_axis_tlast(s_tlast),
        .s_axis_tready(s_tready),
        .s_axis_route_type(s_route_type),
        .s_axis_is_aggregated(s_is_aggregated),
        .s_axis_agg_ingress_port(s_agg_ingress),
        .m_axis_tdata(m_tdata),
        .m_axis_tkeep(m_tkeep),
        .m_axis_tvalid(m_tvalid),
        .m_axis_tlast(m_tlast),
        .m_axis_tready(m_tready),
        .m_axis_route_type(m_route_type),
        .m_axis_is_aggregated(m_is_aggregated),
        .m_axis_agg_ingress_port(m_agg_ingress)
    );

    // 250 MHz
    initial clk = 0;
    always #2 clk = ~clk;

    // 测试向量 (Python 生成, 已验证字节序)
    // tdata[7:0]=byte0, tdata[511:504]=byte63, Verilog hex MSB first
    localparam [511:0] ACK_BEAT = 512'h0000000000000100001f00000080f66e0000ffff001100001c00b712b7120101a8c00201a8c00000114000401111300000450008950019fd70109ae6a0005452;
    localparam [511:0] SEND_BEAT0 = 512'h090807060504030201000000008039220000ffff000400005800b712b7120201a8c00101a8c000001140004011116c00004500089ae6a0005452950019fd7010;
    localparam [511:0] SEND_BEAT1 = 512'h000000000000000000003f3e3d3c3b3a393837363534333231302f2e2d2c2b2a292827262524232221201f1e1d1c1b1a191817161514131211100f0e0d0c0b0a;

    // 期望 ICRC (little-endian 整数)
    // ACK wire bytes: 64 b5 73 5f -> LE int = 0x5F73B564
    // SEND wire bytes: 19 63 12 ba -> LE int = 0xBA126319
    localparam [31:0] EXPECTED_ICRC_ACK  = 32'h5F73B564;
    localparam [31:0] EXPECTED_ICRC_SEND = 32'hBA126319;

    integer pass_count = 0;
    integer fail_count = 0;

    task automatic check_icrc;
        input [511:0] out_data;
        input integer byte_pos;
        input [31:0]  expected;
        input [8*10-1:0] test_name;
        reg [31:0] got;
        reg [511:0] shifted;
        begin
            shifted = out_data >> (byte_pos * 8);
            got[7:0]   = shifted[7:0];
            got[15:8]  = shifted[15:8];
            got[23:16] = shifted[23:16];
            got[31:24] = shifted[31:24];
            if (got == expected) begin
                $display("[PASS] %0s: ICRC = 0x%08X", test_name, got);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s: got=0x%08X, expected=0x%08X", test_name, got, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        rst_n = 0;
        s_tvalid = 0;
        s_tlast = 0;
        s_tdata = 0;
        s_tkeep = 0;
        s_route_type = 3'd2;
        s_is_aggregated = 1;
        s_agg_ingress = 8'h01;
        m_tready = 1;

        #20 rst_n = 1;
        #10;

        // ============================================================
        // Test 1: ACK 包 - 单拍, 62 字节有效, ICRC at byte 58-61
        // ============================================================
        $display("\n=== Test 1: ACK packet (single beat, 62B) ===");
        @(negedge clk);  // 在负沿驱动, 避免与 DUT posedge 竞争
        s_tdata  = ACK_BEAT;
        s_tkeep  = {2'b00, {62{1'b1}}};
        s_tvalid = 1;
        s_tlast  = 1;
        s_is_aggregated = 1;

        @(negedge clk);
        s_tvalid = 0;
        s_tlast  = 0;

        // 等 DRAIN 输出, 在 valid 时立即采样
        @(posedge clk);
        while (!(m_tvalid && m_tlast)) @(posedge clk);
        // 此时 m_tdata 有效, 立即检查 (不要等 negedge, FIFO 会在 NBA 后清空)
        // Debug: 打印内部信号
        $display("  DEBUG: crc_state=0x%08X", dut.crc_state);
        $display("  DEBUG: icrc_result=0x%08X", dut.icrc_result);
        $display("  DEBUG: crc_out_44B=0x%08X", dut.crc_out_44B);
        $display("  DEBUG: is_single_beat=%b", dut.is_single_beat);
        $display("  DEBUG: ack_beat_crc_data[7:0]=0x%02X (expect 0x45)", dut.ack_beat_crc_data[7:0]);
        $display("  DEBUG: ack_beat_crc_data[15:8]=0x%02X (expect 0xFF)", dut.ack_beat_crc_data[15:8]);
        $display("  DEBUG: masked_data[119:112]=0x%02X (byte14, expect 0x45)", dut.masked_data[119:112]);
        $display("  DEBUG: masked_data[127:120]=0x%02X (byte15 TOS, expect 0xFF)", dut.masked_data[127:120]);
        check_icrc(m_tdata, 58, EXPECTED_ICRC_ACK, "ACK");

        #40;

        // ============================================================
        // Test 2: SEND_ONLY 包 - 2 拍, beat1 有 58B, ICRC at byte 54-57
        // ============================================================
        $display("\n=== Test 2: SEND_ONLY packet (2 beats, 122B) ===");
        @(negedge clk);
        s_tdata  = SEND_BEAT0;
        s_tkeep  = {64{1'b1}};
        s_tvalid = 1;
        s_tlast  = 0;
        s_is_aggregated = 1;

        @(negedge clk);
        s_tdata  = SEND_BEAT1;
        s_tkeep  = {{6{1'b0}}, {58{1'b1}}};
        s_tlast  = 1;

        @(negedge clk);
        s_tvalid = 0;
        s_tlast  = 0;

        // 等末拍输出
        @(posedge clk);
        while (!(m_tvalid && m_tlast)) @(posedge clk);
        check_icrc(m_tdata, 54, EXPECTED_ICRC_SEND, "SEND");

        #40;

        // ============================================================
        $display("\n=== Results: %0d PASS, %0d FAIL ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        #100;
        $finish;
    end

    initial begin
        #100000;
        $display("[TIMEOUT]");
        $finish;
    end

endmodule
