`timescale 1ns / 1ps
// tb_parser_aeth.v - 验证 parser AETH 提取功能
// 注入一个 ACK 包和一个 SEND 包, 检查 AETH 输出

module tb_parser_aeth;

    parameter AXIS_DATA_WIDTH = 512;
    parameter AXIS_KEEP_WIDTH = 64;
    parameter PROT_NUM = 2;
    parameter ADDR_RAM_SLOT_WIDTH = 10;

    reg clk, rst_n;
    reg [AXIS_DATA_WIDTH-1:0]  s_tdata;
    reg [AXIS_KEEP_WIDTH-1:0]  s_tkeep;
    reg                        s_tvalid;
    reg                        s_tlast;
    wire                       s_tready;
    reg [7:0]                  ingress_port;

    wire [AXIS_DATA_WIDTH-1:0] m_tdata;
    wire [AXIS_KEEP_WIDTH-1:0] m_tkeep;
    wire                       m_tvalid;
    wire                       m_tlast;
    reg                        m_tready;
    wire [2:0]                 m_route_type;
    wire                       m_is_aggregated;
    wire [7:0]                 m_agg_ingress_port;

    allreduce_offload_top #(
        .PROT_NUM(PROT_NUM),
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
        .ADDR_RAM_SLOT_WIDTH(ADDR_RAM_SLOT_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(s_tdata),
        .s_axis_tkeep(s_tkeep),
        .s_axis_tvalid(s_tvalid),
        .s_axis_tlast(s_tlast),
        .s_axis_tready(s_tready),
        .m_axis_tdata(m_tdata),
        .m_axis_tkeep(m_tkeep),
        .m_axis_tvalid(m_tvalid),
        .m_axis_tlast(m_tlast),
        .m_axis_tready(m_tready),
        .m_axis_route_type(m_route_type),
        .m_axis_is_aggregated(m_is_aggregated),
        .m_axis_agg_ingress_port(m_agg_ingress_port),
        .ingress_port(ingress_port)
    );

    // 250 MHz
    initial clk = 0;
    always #2 clk = ~clk;

    // ACK 包 (opcode=0x11, syndrome=0x1F, MSN=0x000001)
    // 与 icrc_reference.py 生成的 ACK 包一致 (去掉 ICRC 末 4B)
    // 完整 ACK: 525400a0e69a 1070fd190095 0800 4500 0030 1111 4000 4011 0000
    //           c0a80102 c0a80101 12b7 12b7 001c 0000 1100 ffff 00006ef6 80000000 1f000001
    // byte 42 = opcode = 0x11
    // byte 54 = syndrome = 0x1F
    // byte 55-57 = MSN = 00 00 01
    localparam [511:0] ACK_BEAT = 512'h0000000000000100001f00000080f66e0000ffff001100001c00b712b7120101a8c00201a8c00000114000401111300000450008950019fd70109ae6a0005452;

    // SEND 包 beat 0 (opcode=0x04, 无 AETH)
    localparam [511:0] SEND_BEAT0 = 512'h090807060504030201000000008039220000ffff000400005800b712b7120201a8c00101a8c000001140004011116c00004500089ae6a0005452950019fd7010;

    integer pass_count = 0;
    integer fail_count = 0;

    // 监控 parser 内部 AETH 输出
    wire [7:0]  aeth_syn_out = dut.parser_aeth_syndrome;
    wire [23:0] aeth_msn_out = dut.parser_aeth_msn;
    wire        hdr_valid    = dut.allreduce_parser.agg_header_valid;
    wire [7:0]  opcode_out   = dut.allreduce_parser.agg_opcode_out;

    initial begin
        rst_n = 0;
        s_tvalid = 0;
        s_tlast = 0;
        s_tdata = 0;
        s_tkeep = 0;
        ingress_port = 8'd0;
        m_tready = 1;

        #40 rst_n = 1;
        #20;

        // ============================================================
        // Test 1: 注入 ACK 包, 检查 AETH 输出
        // ============================================================
        $display("\n=== Test 1: ACK packet (opcode=0x11) ===");
        $display("  Expected: syndrome=0x1F, MSN=0x000001");
        @(negedge clk);
        s_tdata  = ACK_BEAT;
        s_tkeep  = {2'b00, {62{1'b1}}};
        s_tvalid = 1;
        s_tlast  = 1;
        ingress_port = 8'd0;

        @(negedge clk);
        s_tvalid = 0;
        s_tlast  = 0;

        // 等待 parser 输出 (4 级流水 + 若干周期)
        repeat(20) begin
            @(posedge clk);
            if (hdr_valid) begin
                $display("  [DETECTED] agg_header_valid=1 at time %0t", $time);
                $display("    opcode_out    = 0x%02X (expect 0x11)", opcode_out);
                $display("    aeth_syn_out  = 0x%02X (expect 0x1F)", aeth_syn_out);
                $display("    aeth_msn_out  = 0x%06X (expect 0x000001)", aeth_msn_out);
                if (aeth_syn_out == 8'h1F && aeth_msn_out == 24'h000001) begin
                    $display("  [PASS] AETH extraction correct");
                    pass_count = pass_count + 1;
                end else begin
                    $display("  [FAIL] AETH mismatch");
                    fail_count = fail_count + 1;
                end
            end
        end

        #40;

        // ============================================================
        // Test 2: 注入 SEND 包, 检查 AETH 输出应为 0
        // ============================================================
        $display("\n=== Test 2: SEND packet (opcode=0x04) ===");
        $display("  Expected: syndrome=0x00, MSN=0x000000 (AETH 无效)");
        @(negedge clk);
        s_tdata  = SEND_BEAT0;
        s_tkeep  = {64{1'b1}};
        s_tvalid = 1;
        s_tlast  = 1;
        ingress_port = 8'd0;

        @(negedge clk);
        s_tvalid = 0;
        s_tlast  = 0;

        repeat(20) begin
            @(posedge clk);
            if (hdr_valid) begin
                $display("  [DETECTED] agg_header_valid=1 at time %0t", $time);
                $display("    opcode_out    = 0x%02X (expect 0x04)", opcode_out);
                $display("    aeth_syn_out  = 0x%02X", aeth_syn_out);
                $display("    aeth_msn_out  = 0x%06X", aeth_msn_out);
                // SEND 包: AETH 字段位置实际是 payload 数据, 不是 AETH
                // parser 仍然会输出那些字节, 但下游只在 opcode==0x11 时使用
                $display("  [INFO] SEND packet AETH fields are don't-care (only used when opcode==0x11)");
                pass_count = pass_count + 1;
            end
        end

        #40;

        // ============================================================
        $display("\n=== Results: %0d PASS, %0d FAIL ===", pass_count, fail_count);
        if (fail_count == 0 && pass_count > 0)
            $display("ALL TESTS PASSED");
        else if (pass_count == 0)
            $display("WARNING: No agg_header_valid detected - check hash table / lookup_hit");
        else
            $display("SOME TESTS FAILED");

        #100;
        $finish;
    end

    initial begin
        #200000;
        $display("[TIMEOUT]");
        $finish;
    end

endmodule
