`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/09/05 15:17:05
// Design Name: 
// Module Name: hash_connection_table
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


module hash_connection_table#(
    parameter KEY_WIDTH  = 160,
    parameter HASH_WIDTH = 8,
    parameter DATA_WIDTH = 1,
    parameter TABLE_DEPTH = 1 << HASH_WIDTH,
    parameter BUCKET_SIZE = 4
)(
    input   wire                    clk,
    input   wire                    rst_n,

    // ---> READ
    input   wire                    read_key_valid,
    input   wire [KEY_WIDTH-1:0]    read_key,
    output  reg                     lookup_hit,
    output  reg  [DATA_WIDTH-1:0]   lookup_data,
    // 同时输出该 read_key 的 hash 值 (s1 计算, s2 寄存与 lookup_hit 同拍).
    // parser 用它当 connection 索引进 deparser header_mem (depth=16 即可),
    // 避免按 psn_mod 索引导致 1024 深度推不出 BRAM.
    output  reg  [HASH_WIDTH-1:0]   lookup_hash_value,

    // ---> WRITE
    input   wire                    write_en,
    input   wire [KEY_WIDTH-1:0]    write_key,
    input   wire [DATA_WIDTH-1:0]   write_data

);
    // entry bit layout : {data[DATA_WIDTH], key[KEY_WIDTH], valid[1]}
    // 总宽度 = KEY_WIDTH + DATA_WIDTH + 1 (默认 192+1+1 = 194 bit)
    reg [KEY_WIDTH + DATA_WIDTH:0] table_mem [0:TABLE_DEPTH-1][0:BUCKET_SIZE-1];

    // ================================================================
    // Hash Connection Table Backdoor Config (方案 C: RTL 硬编码两条 entry)
    // ================================================================
    // Key format : {dst_mac, src_mac, src_ip, dst_ip} = 160 bit
    // Entry      : {root_info[1], key[160], valid[1]} = 162 bit
    //
    // ---- 为什么用 initial 块而不是 reset 分支 -------------------------
    //   table_mem 总位数 = TABLE_DEPTH * BUCKET_SIZE * (KEY+DATA+1)
    //                    = 256 * 4 * 194 = 198,656 bit
    //   若在 reset 分支 for-loop 清 0, Vivado 推断不出 BRAM (BRAM 没有异步
    //   reset 端口), 会综合成 ~20 万个 FF, 每个都挂在 rst_n 上 -> rst_n
    //   扇出爆炸 -> 被推到 BUFG 跨 SLR 分发 -> [Route 35-535]
    //   allreduce_rst_n_BUFG not completely routed 失败。
    //   用 initial 块做上电初始化后, table_mem 可以被推断为 BRAM / distributed
    //   RAM, rst_n 只剩读端几个 reg, 扇出恢复正常。
    //
    // ---- 为什么 hash 值要预算成 localparam ---------------------------
    //   initial 块里若用 hash_function 实例的组合输出作数组下标, 依赖 Vivado
    //   在 elaboration 时把 module instance 输出折叠成常量, 但这不是综合
    //   保证行为。用 Python 离线预算的 localparam 是 100% 可靠的写法。
    //   若以后改 key, 必须同步重算 hash (见下方 translate_off 自检逻辑,
    //   仿真会立刻报错提醒)。
    //
    // ---- 两条 entry 的语义 -------------------------------------------
    //   Conn 0 : root_info=1 (本节点是 root), 走 root_up -> port_retrans /
    //            down_broadcast 路径
    //   Conn 1 : root_info=0 (本节点不是 root), 走 noroot_up ->
    //            FAN_first_trans / FAN_retrans 路径
    //   hash0=0xE8, hash1=0xC9, 不碰撞, 各占一桶 slot 0 无覆盖。
    // ================================================================

    // ---- Connection 0: root_info=1 (本节点是 root) -------------------
    localparam [47:0] HIT_DST_MAC_0   = 48'h020000000307;  // FPGA root virtual MAC
    localparam [47:0] HIT_SRC_MAC_0   = 48'hB8599F011122;  // worker1 ens9f0np0
    localparam [31:0] HIT_SRC_IP_0    = 32'hC0A80305;      // 192.168.3.5
    localparam [31:0] HIT_DST_IP_0    = 32'hC0A80307;      // 192.168.3.7
    localparam        HIT_ROOT_INFO_0 = 1'b1;
    localparam [KEY_WIDTH-1:0] HIT_KEY_0 = {
        HIT_DST_MAC_0, HIT_SRC_MAC_0, HIT_SRC_IP_0, HIT_DST_IP_0
    };
    // Python budget: hash_func(HIT_KEY_0) = 8'h40
    localparam [HASH_WIDTH-1:0] HIT_HASH_0 = 8'h40;

    // ---- Connection 1: root_info=0 (本节点不是 root) -----------------
    localparam [47:0] HIT_DST_MAC_1   = 48'h020000000307;  // FPGA root virtual MAC
    localparam [47:0] HIT_SRC_MAC_1   = 48'hB8599F011258;  // worker2 ens9f0np0
    localparam [31:0] HIT_SRC_IP_1    = 32'hC0A80306;      // 192.168.3.6
    localparam [31:0] HIT_DST_IP_1    = 32'hC0A80307;      // 192.168.3.7
    localparam        HIT_ROOT_INFO_1 = 1'b1;
    localparam [KEY_WIDTH-1:0] HIT_KEY_1 = {
        HIT_DST_MAC_1, HIT_SRC_MAC_1, HIT_SRC_IP_1, HIT_DST_IP_1
    };
    // Python budget: hash_func(HIT_KEY_1) = 8'h40
    localparam [HASH_WIDTH-1:0] HIT_HASH_1 = 8'h40;

    // ---- 上电初始化 table_mem ----------------------------------------
    integer i, j;
    initial begin
        for (i = 0; i < TABLE_DEPTH; i = i + 1) begin
            for (j = 0; j < BUCKET_SIZE; j = j + 1) begin
                table_mem[i][j] = {(KEY_WIDTH + DATA_WIDTH + 1){1'b0}};
            end
        end
        // entry = {data[DATA_WIDTH], key[KEY_WIDTH], valid[1]}
        table_mem[HIT_HASH_0][0] = {HIT_ROOT_INFO_0, HIT_KEY_0, 1'b1};
        table_mem[HIT_HASH_1][1] = {HIT_ROOT_INFO_1, HIT_KEY_1, 1'b1};
    end

    // ---- 仿真自检 ----------------------------------------------------
    // 综合时 translate_off 跳过, 不生成硬件; 仿真时做三层验证:
    //   (1) 静态: HIT_HASH_* localparam 与 hash_function(HIT_KEY_*) 一致
    //       覆盖 Python 离线预算 vs RTL hash 函数
    //   (2) 静态: 显式打印 HIT_KEY_* 字段拼接顺序, 方便对比 parser.v 的
    //       lookup_key 拼接 (parser.v line 469: {peer_mac, src_mac,
    //       src_ip, peer_ip, src_port, peer_port}, 其中 peer=包dst, src=包src,
    //       与本文件 {DST_MAC, SRC_MAC, SRC_IP, DST_IP, SRC_PORT, DST_PORT} 对齐)
    //   (3) 动态: 监视 read_key, 每当上游送入 HIT_KEY_*, 2 拍后必须
    //       lookup_hit=1 且 lookup_data == HIT_ROOT_INFO_*, 否则 $finish
    // 任一环节挂掉, 仿真立刻报错, 防止失配状态默默通过流到上板。
    // synthesis translate_off
    wire [HASH_WIDTH-1:0] sim_check_hash_0;
    wire [HASH_WIDTH-1:0] sim_check_hash_1;
    hash_function #(.KEY_WIDTH(KEY_WIDTH), .HASH_WIDTH(HASH_WIDTH)) sim_check_hash_func_0 (
        .key_in  (HIT_KEY_0),
        .hash_out(sim_check_hash_0)
    );
    hash_function #(.KEY_WIDTH(KEY_WIDTH), .HASH_WIDTH(HASH_WIDTH)) sim_check_hash_func_1 (
        .key_in  (HIT_KEY_1),
        .hash_out(sim_check_hash_1)
    );

    // (1)(2) 静态自检
    initial begin
        #1; // 等组合逻辑稳定
        $display("================================================================");
        $display("[hash_connection_table] Backdoor static self-check");
        $display("  HIT_KEY_0 = 160'h%040h (root_info=%0d)", HIT_KEY_0, HIT_ROOT_INFO_0);
        $display("            = {DST_MAC=%012h, SRC_MAC=%012h, SRC_IP=%08h, DST_IP=%08h}",
                 HIT_DST_MAC_0, HIT_SRC_MAC_0, HIT_SRC_IP_0, HIT_DST_IP_0);
        $display("  HIT_KEY_1 = 160'h%040h (root_info=%0d)", HIT_KEY_1, HIT_ROOT_INFO_1);
        $display("            = {DST_MAC=%012h, SRC_MAC=%012h, SRC_IP=%08h, DST_IP=%08h}",
                 HIT_DST_MAC_1, HIT_SRC_MAC_1, HIT_SRC_IP_1, HIT_DST_IP_1);
        if (sim_check_hash_0 !== HIT_HASH_0) begin
            $display("[hash_connection_table] FATAL: HIT_HASH_0 mismatch! localparam=0x%02h, computed=0x%02h",
                     HIT_HASH_0, sim_check_hash_0);
            $finish;
        end
        if (sim_check_hash_1 !== HIT_HASH_1) begin
            $display("[hash_connection_table] FATAL: HIT_HASH_1 mismatch! localparam=0x%02h, computed=0x%02h",
                     HIT_HASH_1, sim_check_hash_1);
            $finish;
        end
        if ((HIT_HASH_0 === HIT_HASH_1) && (HIT_KEY_0 === HIT_KEY_1)) begin
            $display("[hash_connection_table] FATAL: duplicate keys in same bucket!");
            $finish;
        end
        $display("  hash0=0x%02h hash1=0x%02h (slot0/slot1) -- static OK", sim_check_hash_0, sim_check_hash_1);
        $display("  Parser must build lookup_key as {dst_mac, src_mac, src_ip, dst_ip}");
        $display("  -> parser.v: {s1_peer_mac, s1_src_mac, s1_src_ip, s1_peer_ip}");
        $display("     where parser.peer=pkt.dst, parser.src=pkt.src (verified by line 507~516)");
        $display("================================================================");
    end

    // (3) 动态自检: 监视进来的 key, 等 2 拍 (s1_read_key 1 拍 + lookup_hit 1 拍) 后核对
    reg                  exp_key0_valid_d1, exp_key0_valid_d2;
    reg                  exp_key1_valid_d1, exp_key1_valid_d2;
    always @(posedge clk) begin
        // 入口: 上游送进的 (read_key, read_key_valid) 与 HIT_KEY_* 比较
        exp_key0_valid_d1 <= (read_key_valid && (read_key === HIT_KEY_0));
        exp_key1_valid_d1 <= (read_key_valid && (read_key === HIT_KEY_1));
        // 经过 s1 流水一拍, 再过比对一拍, 总共 2 拍到 lookup_hit
        exp_key0_valid_d2 <= exp_key0_valid_d1;
        exp_key1_valid_d2 <= exp_key1_valid_d1;

        if (rst_n) begin
            if (exp_key0_valid_d2) begin
                if (lookup_hit !== 1'b1) begin
                    $display("[%0t] [hash_connection_table] FATAL: HIT_KEY_0 sent but lookup_hit=0!", $time);
                    $finish;
                end
                if (lookup_data !== HIT_ROOT_INFO_0) begin
                    $display("[%0t] [hash_connection_table] FATAL: HIT_KEY_0 hit but lookup_data=%0d != HIT_ROOT_INFO_0=%0d",
                             $time, lookup_data, HIT_ROOT_INFO_0);
                    $finish;
                end
                $display("[%0t] [hash_connection_table] HIT_KEY_0 dynamic hit OK (root_info=%0d)",
                         $time, lookup_data);
            end
            if (exp_key1_valid_d2) begin
                if (lookup_hit !== 1'b1) begin
                    $display("[%0t] [hash_connection_table] FATAL: HIT_KEY_1 sent but lookup_hit=0!", $time);
                    $finish;
                end
                if (lookup_data !== HIT_ROOT_INFO_1) begin
                    $display("[%0t] [hash_connection_table] FATAL: HIT_KEY_1 hit but lookup_data=%0d != HIT_ROOT_INFO_1=%0d",
                             $time, lookup_data, HIT_ROOT_INFO_1);
                    $finish;
                end
                $display("[%0t] [hash_connection_table] HIT_KEY_1 dynamic hit OK (root_info=%0d)",
                         $time, lookup_data);
            end
        end
    end
    initial begin
        exp_key0_valid_d1 = 0; exp_key0_valid_d2 = 0;
        exp_key1_valid_d1 = 0; exp_key1_valid_d2 = 0;
    end
    // synthesis translate_on



    // ========================================================================
    // Read Logic (Pipelined)
    // ========================================================================

    // pipline - 1 compute hash value
    reg     [KEY_WIDTH-1:0]     s1_read_key;
    reg                         s1_read_key_valid;
    wire    [HASH_WIDTH-1:0]    s1_read_hash_value;    

    hash_function #(.KEY_WIDTH(KEY_WIDTH), .HASH_WIDTH(HASH_WIDTH)) read_hash_func (
        .key_in(s1_read_key),
        .hash_out(s1_read_hash_value)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_read_key <= 0;
            s1_read_key_valid <= 0;
        end

        else begin
            s1_read_key_valid <= read_key_valid;

            if (read_key_valid) begin
                s1_read_key <= read_key;
            end
        end
    end

    // always @(posedge clk) begin
    //     if (read_key_valid) begin
    //         s1_read_key <= read_key;
    //     end
    // end
    
    // pipeline - 2 hash compare
    wire                        hit_in_bucket;
    wire    [DATA_WIDTH-1:0]    data_from_bucket;
    wire    [BUCKET_SIZE-1:0]   match_vector;

    genvar k;
    generate
        for (k = 0; k < BUCKET_SIZE; k = k + 1) begin : READ_COMPARE_LOOP
            assign match_vector[k] = (table_mem[s1_read_hash_value][k][0]) && (table_mem[s1_read_hash_value][k][KEY_WIDTH:1] == s1_read_key);
        end 

        assign hit_in_bucket = |match_vector;

        // wire [DATA_WIDTH-1:0] data_bucket_vector [0:BUCKET_SIZE];
        // assign data_bucket_vector[0] = {DATA_WIDTH{1'b0}};
        // for (k = 0; k < BUCKET_SIZE; k = k + 1) begin : DATA_COMPARE_LOOP
        //     assign data_bucket_vector[k+1] = match_vector[k] ? table_mem[s1_read_hash_value][k][KEY_WIDTH + DATA_WIDTH : 1 + KEY_WIDTH] : 
        //         data_bucket_vector[k];
            
        // end

        assign data_from_bucket = 
            match_vector[0] ? table_mem[s1_read_hash_value][0][KEY_WIDTH + DATA_WIDTH : 1 + KEY_WIDTH]:
            match_vector[1] ? table_mem[s1_read_hash_value][1][KEY_WIDTH + DATA_WIDTH : 1 + KEY_WIDTH]:
            match_vector[2] ? table_mem[s1_read_hash_value][2][KEY_WIDTH + DATA_WIDTH : 1 + KEY_WIDTH]:
            match_vector[3] ? table_mem[s1_read_hash_value][3][KEY_WIDTH + DATA_WIDTH : 1 + KEY_WIDTH]:
            {DATA_WIDTH{1'b0}};
    endgenerate


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lookup_data <= {DATA_WIDTH{1'b0}};
            lookup_hit <= 1'b0;
            lookup_hash_value <= {HASH_WIDTH{1'b0}};
        end
        else begin
            lookup_hit <= hit_in_bucket && s1_read_key_valid;
            lookup_data <= data_from_bucket;
            // hash_value 与 lookup_hit/data 同一拍输出, 给 parser 当 connection slot 索引
            lookup_hash_value <= s1_read_hash_value;

        end
    end

    // ========================================================================
    // Write Logic (Control Plane)
    // ========================================================================
    wire [HASH_WIDTH-1:0]   write_hash_value;
    
    hash_function #(.KEY_WIDTH(KEY_WIDTH), .HASH_WIDTH(HASH_WIDTH)) write_hash_func (
        .key_in(write_key),
        .hash_out(write_hash_value)
    );

    reg [($clog2(BUCKET_SIZE))-1 : 0] write_index;
    reg found_slot;

    always @(*) begin
        write_index = 0;
        found_slot = 1'b0;
        if (table_mem[write_hash_value][0][0] && table_mem[write_hash_value][0][KEY_WIDTH:1] == write_key) begin
            write_index = 0; 
            found_slot = 1'b1;
        end
        else if (table_mem[write_hash_value][1][0] && table_mem[write_hash_value][1][KEY_WIDTH:1] == write_key) begin
            write_index = 1; 
            found_slot = 1'b1;
        end
        else if (table_mem[write_hash_value][2][0] && table_mem[write_hash_value][2][KEY_WIDTH:1] == write_key) begin
            write_index = 2; 
            found_slot = 1'b1;
        end
        else if (table_mem[write_hash_value][3][0] && table_mem[write_hash_value][3][KEY_WIDTH:1] == write_key) begin
            write_index = 3; 
            found_slot = 1'b1;
        end
        else begin
            if (!table_mem[write_hash_value][0][0]) begin
                write_index = 0;
                found_slot = 1'b1;
            end
            else if (!table_mem[write_hash_value][1][0]) begin
                write_index = 1;
                found_slot = 1'b1;
            end 
            else if (!table_mem[write_hash_value][2][0]) begin
                write_index = 2;
                found_slot = 1'b1;
            end
            else if (!table_mem[write_hash_value][3][0]) begin
                write_index = 3;
                found_slot = 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (write_en && found_slot) begin
            table_mem[write_hash_value][write_index] <= {write_data,write_key,1'b1};
        end
    end
endmodule
