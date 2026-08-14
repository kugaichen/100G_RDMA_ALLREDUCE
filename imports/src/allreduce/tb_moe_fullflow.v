`timescale 1ns / 1ps
`include "moe_defs.vh"

module tb_moe_fullflow;
    localparam AXIS_DATA_WIDTH = 512;
    localparam AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8;

    reg clk = 1'b0;
    reg rst_n = 1'b0;

    reg [AXIS_DATA_WIDTH-1:0] s_axis_tdata = {AXIS_DATA_WIDTH{1'b0}};
    reg [AXIS_KEEP_WIDTH-1:0] s_axis_tkeep = {AXIS_KEEP_WIDTH{1'b0}};
    reg s_axis_tvalid = 1'b0;
    reg s_axis_tlast = 1'b0;
    wire s_axis_tready;

    wire [AXIS_DATA_WIDTH-1:0] m_axis_tdata;
    wire [AXIS_KEEP_WIDTH-1:0] m_axis_tkeep;
    wire m_axis_tvalid;
    wire m_axis_tlast;
    reg m_axis_tready = 1'b0;
    wire [2:0] m_axis_route_type;
    wire m_axis_is_aggregated;
    wire [7:0] m_axis_agg_ingress_port;
    wire [255:0] dbg_moe_perf_counters_flat;
    wire [31:0] dbg_dispatch_accept_count = dbg_moe_perf_counters_flat[31:0];
    wire [31:0] dbg_init_accept_count = dbg_moe_perf_counters_flat[63:32];
    wire [31:0] dbg_data_accept_count = dbg_moe_perf_counters_flat[95:64];
    wire [31:0] dbg_release_accept_count = dbg_moe_perf_counters_flat[127:96];
    wire [31:0] dbg_dispatch_output_count = dbg_moe_perf_counters_flat[159:128];
    wire [31:0] dbg_combine_output_count = dbg_moe_perf_counters_flat[191:160];
    wire [31:0] dbg_output_stall_count = dbg_moe_perf_counters_flat[223:192];
    wire [31:0] dbg_drop_event_count = dbg_moe_perf_counters_flat[255:224];

    reg [AXIS_DATA_WIDTH-1:0] first_beat;
    integer output_count = 0;
    reg saw_duplicate_drop = 1'b0;
    reg saw_stall = 1'b0;

    allreduce_offload_top #(
        .ENABLE_MOE_COMBINE(1),
        .MOE_WINDOW_SIZE(8),
        .MOE_USE_REAL_PAYLOAD(1),
        .ENABLE_MOE_DISPATCH_INIT(1),
        .ENABLE_MOE_DISPATCH_EGRESS(0)
    ) dut (
        .rst_n(rst_n),
        .clk(clk),

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

        .m_axis_route_type(m_axis_route_type),
        .m_axis_is_aggregated(m_axis_is_aggregated),
        .m_axis_agg_ingress_port(m_axis_agg_ingress_port),
        .dbg_moe_perf_counters_flat(dbg_moe_perf_counters_flat),

        .ingress_port(8'd0),
        .cfg_is_root(1'b1),

        .cfg_my_mac_p0(48'h020000000307),
        .cfg_my_mac_p1(48'h020000000308),
        .cfg_my_ip_p0(32'hC0A80307),
        .cfg_my_ip_p1(32'hC0A80308),
        .cfg_my_qp_p0(24'h000100),
        .cfg_my_qp_p1(24'h000101),
        .cfg_my_port_p0(16'd4791),
        .cfg_my_port_p1(16'd4791),
        .cfg_peer_mac_p0(48'h6CB31188AB3E),
        .cfg_peer_mac_p1(48'h6CB31188AB3F),
        .cfg_peer_ip_p0(32'hC0A80305),
        .cfg_peer_ip_p1(32'hC0A80306),
        .cfg_peer_qp_p0(24'h000200),
        .cfg_peer_qp_p1(24'h000201),
        .cfg_peer_port_p0(16'd4791),
        .cfg_peer_port_p1(16'd4791)
    );

    always #5 clk = ~clk;

    task set_byte;
        inout [AXIS_DATA_WIDTH-1:0] word;
        input integer byte_idx;
        input [7:0] value;
        begin
            word[byte_idx*8 +: 8] = value;
        end
    endtask

    task put_mac;
        inout [AXIS_DATA_WIDTH-1:0] word;
        input integer base;
        input [47:0] mac;
        begin
            set_byte(word, base + 0, mac[47:40]);
            set_byte(word, base + 1, mac[39:32]);
            set_byte(word, base + 2, mac[31:24]);
            set_byte(word, base + 3, mac[23:16]);
            set_byte(word, base + 4, mac[15:8]);
            set_byte(word, base + 5, mac[7:0]);
        end
    endtask

    task put16;
        inout [AXIS_DATA_WIDTH-1:0] word;
        input integer base;
        input [15:0] value;
        begin
            set_byte(word, base + 0, value[15:8]);
            set_byte(word, base + 1, value[7:0]);
        end
    endtask

    task put24;
        inout [AXIS_DATA_WIDTH-1:0] word;
        input integer base;
        input [23:0] value;
        begin
            set_byte(word, base + 0, value[23:16]);
            set_byte(word, base + 1, value[15:8]);
            set_byte(word, base + 2, value[7:0]);
        end
    endtask

    task put32;
        inout [AXIS_DATA_WIDTH-1:0] word;
        input integer base;
        input [31:0] value;
        begin
            set_byte(word, base + 0, value[31:24]);
            set_byte(word, base + 1, value[23:16]);
            set_byte(word, base + 2, value[15:8]);
            set_byte(word, base + 3, value[7:0]);
        end
    endtask

    task build_moe_first_beat;
        output [AXIS_DATA_WIDTH-1:0] word;
        input [7:0] op_type;
        input [7:0] owner_rank;
        input [7:0] flags;
        input [31:0] seq;
        input [31:0] psn;
        begin
            word = {AXIS_DATA_WIDTH{1'b0}};

            put_mac(word, 0, 48'h020000000307);
            put_mac(word, 6, 48'h6CB31188AB3E);
            put16(word, 12, 16'h0800);

            set_byte(word, 14, 8'h45);
            set_byte(word, 23, 8'h11);
            put32(word, 26, 32'hC0A80305);
            put32(word, 30, 32'hC0A80307);

            put16(word, 34, 16'hCAFE);
            put16(word, 36, 16'd4791);
            put16(word, 38, 16'd1048);

            set_byte(word, 42, 8'h04);
            set_byte(word, 43, 8'h00);
            put16(word, 44, 16'hFFFF);
            set_byte(word, 46, 8'h00);
            put24(word, 47, 24'h000100);
            put32(word, 50, psn);

            put16(word, 54, `MOE_MAGIC);
            set_byte(word, 56, 8'h01);
            set_byte(word, 57, op_type);
            set_byte(word, 58, owner_rank);
            set_byte(word, 59, flags);
            put32(word, 60, seq);
        end
    endtask

    task send_moe_packet;
        input [7:0] op_type;
        input [7:0] owner_rank;
        input [7:0] flags;
        input [31:0] seq;
        input [31:0] psn;
        input [31:0] payload_word;
        begin
            build_moe_first_beat(first_beat, op_type, owner_rank, flags, seq, psn);

            @(posedge clk);
            while (!s_axis_tready) @(posedge clk);
            s_axis_tdata <= first_beat;
            s_axis_tkeep <= {AXIS_KEEP_WIDTH{1'b1}};
            s_axis_tvalid <= 1'b1;
            s_axis_tlast <= 1'b0;

            @(posedge clk);
            while (!s_axis_tready) @(posedge clk);
            s_axis_tdata <= {16{payload_word}};
            s_axis_tkeep <= {AXIS_KEEP_WIDTH{1'b1}};
            s_axis_tvalid <= 1'b1;
            s_axis_tlast <= 1'b1;

            @(posedge clk);
            s_axis_tvalid <= 1'b0;
            s_axis_tlast <= 1'b0;
            s_axis_tdata <= {AXIS_DATA_WIDTH{1'b0}};
            s_axis_tkeep <= {AXIS_KEEP_WIDTH{1'b0}};
        end
    endtask

    always @(posedge clk) begin
        if (dut.moe_data_drop_duplicate) begin
            saw_duplicate_drop <= 1'b1;
        end
        if (m_axis_tvalid && !m_axis_tready) begin
            saw_stall <= 1'b1;
        end

        if (m_axis_tvalid && m_axis_tready) begin
            output_count <= output_count + 1;

            if (output_count == 0) begin
                if (!m_axis_is_aggregated || m_axis_route_type !== 3'd2 ||
                    m_axis_agg_ingress_port !== 8'd0 ||
                    m_axis_tdata[343:336] !== 8'h04 ||
                    m_axis_tdata[447:432] !== `MOE_MAGIC ||
                    m_axis_tdata[455:448] !== `MOE_OP_COMBINE_RESULT ||
                    m_axis_tdata[463:456] !== 8'd0 ||
                    m_axis_tdata[511:480] !== 32'd0) begin
                    $display("FAIL: owner0 result header mismatch data=0x%0128h", m_axis_tdata);
                    $finish;
                end
            end
            else if (output_count == 1) begin
                if (m_axis_tdata[79:48] !== 32'd5 ||
                    m_axis_tdata[111:80] !== 32'd5 ||
                    m_axis_tlast) begin
                    $display("FAIL: owner0 result payload mismatch data=0x%0128h", m_axis_tdata);
                    $finish;
                end
            end
            else if (output_count == 16) begin
                if (!m_axis_tlast || m_axis_tkeep !== {{6{1'b0}}, {58{1'b1}}}) begin
                    $display("FAIL: owner0 result last beat mismatch");
                    $finish;
                end
            end
            else if (output_count == 17) begin
                if (!m_axis_is_aggregated || m_axis_route_type !== 3'd2 ||
                    m_axis_agg_ingress_port !== 8'd1 ||
                    m_axis_tdata[343:336] !== 8'h04 ||
                    m_axis_tdata[447:432] !== `MOE_MAGIC ||
                    m_axis_tdata[455:448] !== `MOE_OP_COMBINE_RESULT ||
                    m_axis_tdata[463:456] !== 8'd1 ||
                    m_axis_tdata[511:480] !== 32'd0) begin
                    $display("FAIL: owner1 result header mismatch data=0x%0128h", m_axis_tdata);
                    $finish;
                end
            end
            else if (output_count == 18) begin
                if (m_axis_tdata[79:48] !== 32'd9 ||
                    m_axis_tdata[111:80] !== 32'd9 ||
                    m_axis_tlast) begin
                    $display("FAIL: owner1 result payload mismatch data=0x%0128h", m_axis_tdata);
                    $finish;
                end
            end
            else if (output_count == 33) begin
                if (!m_axis_tlast || m_axis_tkeep !== {{6{1'b0}}, {58{1'b1}}}) begin
                    $display("FAIL: owner1 result last beat mismatch");
                    $finish;
                end
            end
        end
    end

    initial begin
        repeat (3000) @(posedge clk);
        $display("FAIL: MoE fullflow timeout output_count=%0d stall=%0d init=%0d data=%0d release=%0d combine_out=%0d drop=%0d",
                 output_count,
                 dbg_output_stall_count,
                 dbg_init_accept_count,
                 dbg_data_accept_count,
                 dbg_release_accept_count,
                 dbg_combine_output_count,
                 dbg_drop_event_count);
        $finish;
    end

    initial begin
        repeat (5) @(posedge clk);
        rst_n <= 1'b1;
        repeat (5) @(posedge clk);

        m_axis_tready <= 1'b1;

        send_moe_packet(`MOE_OP_DISPATCH, 8'd0, 8'h03, 32'd0, 32'h0000_1000, 32'd7);
        repeat (6) @(posedge clk);

        m_axis_tready <= 1'b0;
        send_moe_packet(`MOE_OP_COMBINE_DATA, 8'd0, 8'h00, 32'd0, 32'h0000_1001, 32'd2);
        repeat (2) @(posedge clk);
        send_moe_packet(`MOE_OP_COMBINE_DATA, 8'd0, 8'h00, 32'd0, 32'h0000_1002, 32'd2);
        repeat (2) @(posedge clk);
        send_moe_packet(`MOE_OP_COMBINE_DATA, 8'd0, 8'h01, 32'd0, 32'h0000_1003, 32'd3);

        wait (m_axis_tvalid === 1'b1);
        repeat (8) @(posedge clk);
        if (dbg_output_stall_count == 32'd0) begin
            $display("FAIL: output stall counter did not increment");
            $finish;
        end
        m_axis_tready <= 1'b1;

        wait (output_count >= 17);
        repeat (4) @(posedge clk);

        send_moe_packet(`MOE_OP_DISPATCH, 8'd1, 8'h03, 32'd0, 32'h0000_1005, 32'd8);
        repeat (6) @(posedge clk);
        send_moe_packet(`MOE_OP_COMBINE_DATA, 8'd1, 8'h00, 32'd0, 32'h0000_1006, 32'd4);
        repeat (2) @(posedge clk);
        send_moe_packet(`MOE_OP_COMBINE_DATA, 8'd1, 8'h01, 32'd0, 32'h0000_1007, 32'd5);

        wait (output_count >= 34);
        repeat (4) @(posedge clk);

        if (!saw_duplicate_drop) begin
            $display("FAIL: duplicate packet was not dropped");
            $finish;
        end

        if (dbg_dispatch_accept_count !== 32'd2 ||
            dbg_init_accept_count !== 32'd2 ||
            dbg_data_accept_count !== 32'd4 ||
            dbg_release_accept_count !== 32'd2 ||
            dbg_dispatch_output_count !== 32'd0 ||
            dbg_combine_output_count !== 32'd2 ||
            dbg_output_stall_count == 32'd0 ||
            dbg_drop_event_count !== 32'd1) begin
            $display("FAIL: fullflow counters mismatch disp_acc=%0d init=%0d data=%0d release=%0d disp_out=%0d comb_out=%0d stall=%0d drop=%0d",
                     dbg_dispatch_accept_count,
                     dbg_init_accept_count,
                     dbg_data_accept_count,
                     dbg_release_accept_count,
                     dbg_dispatch_output_count,
                     dbg_combine_output_count,
                     dbg_output_stall_count,
                     dbg_drop_event_count);
            $finish;
        end

        $display("TB_MOE_FULLFLOW_PASS");
        $finish;
    end
endmodule
