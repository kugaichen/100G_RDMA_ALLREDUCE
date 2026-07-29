`timescale 1ns / 1ps
// icrc_calc.v - RoCEv2 ICRC 计算模块 (Store-and-Forward)
// 在 deparser 输出后、wrapper 最终输出前串入
// 对 is_aggregated=1 的包计算 CRC32C 并覆盖末 4B; passthrough 包直接转发

module icrc_calc #(
    parameter AXIS_DATA_WIDTH = 512,
    parameter AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8,
    parameter FIFO_DEPTH      = 32
)(
    input wire                          clk,
    input wire                          rst_n,

    // AXIS Slave
    input wire [AXIS_DATA_WIDTH-1:0]    s_axis_tdata,
    input wire [AXIS_KEEP_WIDTH-1:0]    s_axis_tkeep,
    input wire                          s_axis_tvalid,
    input wire                          s_axis_tlast,
    output wire                         s_axis_tready,

    // Sideband in
    input wire [2:0]                    s_axis_route_type,
    input wire                          s_axis_is_aggregated,
    input wire [7:0]                    s_axis_agg_ingress_port,

    // AXIS Master
    output reg [AXIS_DATA_WIDTH-1:0]    m_axis_tdata,
    output reg [AXIS_KEEP_WIDTH-1:0]    m_axis_tkeep,
    output reg                          m_axis_tvalid,
    output reg                          m_axis_tlast,
    input wire                          m_axis_tready,

    // Sideband out
    output reg [2:0]                    m_axis_route_type,
    output reg                          m_axis_is_aggregated,
    output reg [7:0]                    m_axis_agg_ingress_port
);

    // CRC 初始状态: 8 字节全 0xFF (dummy LRH) 后的 CRC32C 状态
    localparam [31:0] CRC_INIT = 32'hDEBB20E3;

    // FSM
    localparam ST_IDLE    = 2'd0;
    localparam ST_INGEST  = 2'd1;
    localparam ST_DRAIN   = 2'd2;
    localparam ST_BYPASS  = 2'd3;

    reg [1:0] state, state_next;

    // FIFO 存储
    localparam FIFO_WIDTH = AXIS_DATA_WIDTH + AXIS_KEEP_WIDTH + 1 + 3 + 1 + 8; // tdata+tkeep+tlast+route+agg+ingress
    reg [FIFO_WIDTH-1:0] fifo_mem [0:FIFO_DEPTH-1];
    reg [$clog2(FIFO_DEPTH)-1:0] wr_ptr, rd_ptr;
    reg [$clog2(FIFO_DEPTH):0]   fifo_count;

    wire fifo_full  = (fifo_count == FIFO_DEPTH);
    wire fifo_empty = (fifo_count == 0);

    // 包计数器
    reg [4:0] beat_count;
    reg       is_single_beat;

    // CRC 状态
    reg [31:0] crc_state;
    reg [31:0] icrc_result;
    reg        crc_done;

    // CRC 核输出
    wire [31:0] crc_out_64B, crc_out_50B, crc_out_44B, crc_out_54B;

    // Mask 应用 (仅首拍, byte 14~63 中的特定字段)
    reg [AXIS_DATA_WIDTH-1:0] masked_data;
    always @(*) begin
        masked_data = s_axis_tdata;
        masked_data[8*15+7 : 8*15] = 8'hFF;  // byte 15: TOS
        masked_data[8*22+7 : 8*22] = 8'hFF;  // byte 22: TTL
        masked_data[8*24+7 : 8*24] = 8'hFF;  // byte 24: IP Checksum high
        masked_data[8*25+7 : 8*25] = 8'hFF;  // byte 25: IP Checksum low
        masked_data[8*40+7 : 8*40] = 8'hFF;  // byte 40: UDP Checksum high
        masked_data[8*41+7 : 8*41] = 8'hFF;  // byte 41: UDP Checksum low
        masked_data[8*46+7 : 8*46] = 8'hFF;  // byte 46: BTH Resv/FECN/BECN
    end

    // 首拍 CRC 输入: 跳过 Eth(14B), 取 byte 14~63 = 50 字节
    wire [50*8-1:0] first_beat_crc_data;
    assign first_beat_crc_data = masked_data[8*64-1 : 8*14]; // bits [511:112]

    // 中间拍 CRC 输入: 全 64 字节
    wire [64*8-1:0] mid_beat_crc_data;
    assign mid_beat_crc_data = s_axis_tdata;

    // 末拍 CRC 输入 (数据包): byte 0~53 = 54 字节 (58 valid - 4 ICRC = 54)
    wire [54*8-1:0] last_beat_crc_data;
    assign last_beat_crc_data = s_axis_tdata[8*54-1:0]; // bits [431:0]

    // ACK 单拍 CRC 输入: 跳过 Eth(14B), 取 byte 14~57 = 44 字节
    wire [44*8-1:0] ack_beat_crc_data;
    assign ack_beat_crc_data = masked_data[8*58-1 : 8*14]; // bits [463:112]

    // CRC 核实例化
    crc32c_64B u_crc64 (
        .data_in(mid_beat_crc_data),
        .crc_in(crc_state),
        .crc_out(crc_out_64B)
    );

    crc32c_50B u_crc50 (
        .data_in(first_beat_crc_data),
        .crc_in(crc_state),
        .crc_out(crc_out_50B)
    );

    crc32c_54B u_crc54 (
        .data_in(last_beat_crc_data),
        .crc_in(crc_state),
        .crc_out(crc_out_54B)
    );

    crc32c_44B u_crc44 (
        .data_in(ack_beat_crc_data),
        .crc_in(crc_state),
        .crc_out(crc_out_44B)
    );

    // CRC 选择
    wire [31:0] crc_next;
    assign crc_next = is_single_beat          ? crc_out_44B :
                      (beat_count == 0)       ? crc_out_50B :
                      (s_axis_tlast)          ? crc_out_54B :
                                                crc_out_64B;

    // s_axis_tready
    assign s_axis_tready = (state == ST_INGEST && !fifo_full) ||
                           (state == ST_BYPASS && m_axis_tready) ||
                           (state == ST_IDLE);

    // FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= ST_IDLE;
        else
            state <= state_next;
    end

    always @(*) begin
        state_next = state;
        case (state)
            ST_IDLE: begin
                if (s_axis_tvalid) begin
                    if (!s_axis_is_aggregated)
                        state_next = ST_BYPASS;
                    else if (s_axis_tlast)
                        state_next = ST_DRAIN;
                    else
                        state_next = ST_INGEST;
                end
            end
            ST_INGEST: begin
                if (s_axis_tvalid && !fifo_full && s_axis_tlast)
                    state_next = ST_DRAIN;
            end
            ST_DRAIN: begin
                if (m_axis_tready && !fifo_empty &&
                    fifo_mem[rd_ptr][AXIS_DATA_WIDTH + AXIS_KEEP_WIDTH])
                    state_next = ST_IDLE;
            end
            ST_BYPASS: begin
                if (s_axis_tvalid && m_axis_tready && s_axis_tlast)
                    state_next = ST_IDLE;
            end
        endcase
    end

    // FIFO 写入 + CRC 累积
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr         <= 0;
            beat_count     <= 0;
            crc_state      <= CRC_INIT;
            is_single_beat <= 0;
            crc_done       <= 0;
            icrc_result    <= 32'h0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (s_axis_tvalid && s_axis_is_aggregated) begin
                        fifo_mem[wr_ptr] <= {s_axis_agg_ingress_port,
                                             s_axis_is_aggregated,
                                             s_axis_route_type,
                                             s_axis_tlast,
                                             s_axis_tkeep,
                                             s_axis_tdata};
                        wr_ptr <= wr_ptr + 1;
                        beat_count <= 0;
                        crc_state <= CRC_INIT;
                        is_single_beat <= s_axis_tlast;
                        crc_done <= 0;

                        if (s_axis_tlast) begin
                            icrc_result <= crc_out_44B ^ 32'hFFFFFFFF;
                            crc_done <= 1;
                        end else begin
                            crc_state <= crc_out_50B;
                        end
                    end
                end

                ST_INGEST: begin
                    if (s_axis_tvalid && !fifo_full) begin
                        fifo_mem[wr_ptr] <= {s_axis_agg_ingress_port,
                                             s_axis_is_aggregated,
                                             s_axis_route_type,
                                             s_axis_tlast,
                                             s_axis_tkeep,
                                             s_axis_tdata};
                        wr_ptr <= wr_ptr + 1;
                        beat_count <= beat_count + 1;

                        if (s_axis_tlast) begin
                            icrc_result <= crc_out_54B ^ 32'hFFFFFFFF;
                            crc_done <= 1;
                        end else begin
                            crc_state <= crc_out_64B;
                        end
                    end
                end

                ST_DRAIN: begin
                    if (m_axis_tready && !fifo_empty &&
                        fifo_mem[rd_ptr][AXIS_DATA_WIDTH + AXIS_KEEP_WIDTH]) begin
                        wr_ptr     <= 0;
                        beat_count <= 0;
                        crc_done   <= 0;
                    end
                end

                default: ;
            endcase
        end
    end

    // FIFO 读指针 + count
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr     <= 0;
            fifo_count <= 0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (s_axis_tvalid && s_axis_is_aggregated)
                        fifo_count <= fifo_count + 1;
                end
                ST_INGEST: begin
                    if (s_axis_tvalid && !fifo_full)
                        fifo_count <= fifo_count + 1;
                end
                ST_DRAIN: begin
                    if (m_axis_tready && !fifo_empty) begin
                        rd_ptr <= rd_ptr + 1;
                        fifo_count <= fifo_count - 1;
                        if (fifo_mem[rd_ptr][AXIS_DATA_WIDTH + AXIS_KEEP_WIDTH]) begin
                            rd_ptr <= 0;
                            fifo_count <= 0;
                        end
                    end
                end
                default: ;
            endcase
        end
    end

    // FIFO 读出解包
    wire [AXIS_DATA_WIDTH-1:0] fifo_tdata   = fifo_mem[rd_ptr][AXIS_DATA_WIDTH-1:0];
    wire [AXIS_KEEP_WIDTH-1:0] fifo_tkeep   = fifo_mem[rd_ptr][AXIS_DATA_WIDTH +: AXIS_KEEP_WIDTH];
    wire                       fifo_tlast   = fifo_mem[rd_ptr][AXIS_DATA_WIDTH + AXIS_KEEP_WIDTH];
    wire [2:0]                 fifo_route   = fifo_mem[rd_ptr][AXIS_DATA_WIDTH + AXIS_KEEP_WIDTH + 1 +: 3];
    wire                       fifo_agg     = fifo_mem[rd_ptr][AXIS_DATA_WIDTH + AXIS_KEEP_WIDTH + 4];
    wire [7:0]                 fifo_ingress = fifo_mem[rd_ptr][AXIS_DATA_WIDTH + AXIS_KEEP_WIDTH + 5 +: 8];

    // ICRC 插入
    reg [AXIS_DATA_WIDTH-1:0] tdata_with_icrc;
    always @(*) begin
        tdata_with_icrc = fifo_tdata;
        if (fifo_tlast) begin
            if (is_single_beat) begin
                tdata_with_icrc[8*58+7 : 8*58] = icrc_result[ 7: 0];
                tdata_with_icrc[8*59+7 : 8*59] = icrc_result[15: 8];
                tdata_with_icrc[8*60+7 : 8*60] = icrc_result[23:16];
                tdata_with_icrc[8*61+7 : 8*61] = icrc_result[31:24];
            end else begin
                // 数据包末拍: tkeep=58B (54B payload + 4B ICRC), ICRC at byte 54-57
                tdata_with_icrc[8*54+7 : 8*54] = icrc_result[ 7: 0];
                tdata_with_icrc[8*55+7 : 8*55] = icrc_result[15: 8];
                tdata_with_icrc[8*56+7 : 8*56] = icrc_result[23:16];
                tdata_with_icrc[8*57+7 : 8*57] = icrc_result[31:24];
            end
        end
    end

    // 输出 mux
    always @(*) begin
        m_axis_tdata            = {AXIS_DATA_WIDTH{1'b0}};
        m_axis_tkeep            = {AXIS_KEEP_WIDTH{1'b0}};
        m_axis_tvalid           = 1'b0;
        m_axis_tlast            = 1'b0;
        m_axis_route_type       = 3'd0;
        m_axis_is_aggregated    = 1'b0;
        m_axis_agg_ingress_port = 8'd0;

        case (state)
            ST_DRAIN: begin
                if (!fifo_empty && crc_done) begin
                    m_axis_tdata            = tdata_with_icrc;
                    m_axis_tkeep            = fifo_tkeep;
                    m_axis_tvalid           = 1'b1;
                    m_axis_tlast            = fifo_tlast;
                    m_axis_route_type       = fifo_route;
                    m_axis_is_aggregated    = fifo_agg;
                    m_axis_agg_ingress_port = fifo_ingress;
                end
            end
            ST_BYPASS: begin
                m_axis_tdata            = s_axis_tdata;
                m_axis_tkeep            = s_axis_tkeep;
                m_axis_tvalid           = s_axis_tvalid;
                m_axis_tlast            = s_axis_tlast;
                m_axis_route_type       = s_axis_route_type;
                m_axis_is_aggregated    = s_axis_is_aggregated;
                m_axis_agg_ingress_port = s_axis_agg_ingress_port;
            end
            default: ;
        endcase
    end

endmodule
