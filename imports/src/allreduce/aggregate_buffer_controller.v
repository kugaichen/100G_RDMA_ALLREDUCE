`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/09/26 20:26:00
// Design Name: 
// Module Name: aggregate_buffer_controller
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


module aggregate_buffer_controller #(
    parameter PAYLOAD_ITEM_NUM = 16,
    parameter PAYLOAD_ITEM_WIDTH = 512,
    parameter PAYLOAD_ITEM_COUNT_WIDTH = $clog2(PAYLOAD_ITEM_NUM),

    parameter SLOTS_WIDTH = 8,
    parameter BUFFER_SLOTS = 16,
    parameter METADATA_LEN = 2*8+3+5

)(
    input clk,
    input rst_n,
          
    input wire                              aggregate_payload_en,               // 聚合
    input wire                              for_port_retrans_read_buffer_en,    // 读取重传
    // input wire                              aggregate_is_float_en,              // [新增] 1=浮点加法, 0=整型加法

    input wire                              for_down_broadcast_copy_buffer_en,  // 数据下行时，直接复制payload
    input wire [METADATA_LEN-1:0]           metadata_in,                        // 用于读bram的地址->psn_out


    input wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]            payload_bram_rd_vector_pack,
    // rd_idx fans out to ~48 payload BRAM EN pins via a 1-level bank-decode
    // LUT. max_fanout lets the synthesizer replicate the driver FF so each
    // copy can be placed near its own sink cluster (1-level LUT means the
    // replicated FFs directly drive the BRAM EN, no intermediate combinational
    // hop to confuse placement).
    (* max_fanout = 16 *) output reg [7:0]                          payload_bram_rd_idx,
    output reg [SLOTS_WIDTH-1:0]                                    payload_bram_rd_addr,
    output reg [PAYLOAD_ITEM_NUM-1:0]                               payload_bram_rd_en_pack,

    input wire                                                      aggregate_bram_rd_grant,
    input wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]            aggregate_bram_rd_vector_pack,
    output reg [SLOTS_WIDTH-1:0]                                    aggregate_bram_rd_addr,
    output reg [PAYLOAD_ITEM_NUM-1:0]                               aggregate_bram_rd_en_pack,

    output reg [SLOTS_WIDTH-1:0]                                    updated_aggregate_bram_wr_addr,
    output reg [PAYLOAD_ITEM_NUM-1:0]                               updated_aggregate_bram_wr_en_pack,
    input wire                                                      updated_aggregate_bram_wr_grant,

    // Exposed for distributed adder in aggregator_core_top:
    // selects whether BRAM write data is the sum (aggregation) or the payload (download/copy)
    output reg                                                      task_is_aggregate_to_up_broadcast_out,

    output reg [METADATA_LEN-1:0]                                  to_deparser_metadata_out,
    output reg                                                     to_deparser_valid,
    output reg                                                     to_deparser_up_port_retrans_ok_en,
    output reg                                                     to_deparser_down_down_broadcast_ok_en,
    input wire                                                     to_deparser_ready,

    output reg [METADATA_LEN-1:0]                                  to_up_broadcast_metadata_out,
    output reg                                                     to_up_broadcast_valid,
    output reg                                                     to_up_broadcast_check_en,
    input wire                                                     to_up_broadcast_ready,

    output wire                                                    in_ready                  // 反压    
);
    reg task_is_aggregate_to_up_broadcast;
    reg task_is_retrans_to_deparser;
    reg task_is_copy_to_deparser;
    reg task_is_float;                           // [新增] 锁存当前任务是否为浮点
    reg [METADATA_LEN-1:0]      latched_metadata;

    // Mirror the latched task type to module port for the distributed adder mux.
    // Combinational tie-off: same timing as the internal reg (already stable when used).
    always @(*) task_is_aggregate_to_up_broadcast_out = task_is_aggregate_to_up_broadcast;

    localparam CTRL_INPUT_BUS_WIDTH = METADATA_LEN + 3;
    wire [CTRL_INPUT_BUS_WIDTH-1:0] ctrl_input_bus;
    wire [CTRL_INPUT_BUS_WIDTH-1:0] ctrl_input_bus_holdfix;
    wire [METADATA_LEN-1:0] metadata_in_holdfix;
    wire aggregate_payload_en_holdfix;
    wire for_port_retrans_read_buffer_en_holdfix;
    wire for_down_broadcast_copy_buffer_en_holdfix;

    assign ctrl_input_bus = {
        metadata_in,
        aggregate_payload_en,
        for_port_retrans_read_buffer_en,
        for_down_broadcast_copy_buffer_en
    };
    assign {
        metadata_in_holdfix,
        aggregate_payload_en_holdfix,
        for_port_retrans_read_buffer_en_holdfix,
        for_down_broadcast_copy_buffer_en_holdfix
    } = ctrl_input_bus_holdfix;

    genvar ctrl_input_holdfix_i;
    generate
        for (ctrl_input_holdfix_i = 0; ctrl_input_holdfix_i < CTRL_INPUT_BUS_WIDTH; ctrl_input_holdfix_i = ctrl_input_holdfix_i + 1) begin : gen_ctrl_input_holdfix
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) u_lut1_ctrl_input_holdfix (
                .I0(ctrl_input_bus[ctrl_input_holdfix_i]),
                .O(ctrl_input_bus_holdfix[ctrl_input_holdfix_i])
            );
        end
    endgenerate

    // ------------------------------------------------------------
    // NOTE: 8192-bit pipeline registers (payload_vec_lat / aggregate_vec_lat)
    //       and the chunk adders that used to live here have been moved out
    //       into aggregator_core_top's parallel_aggregate_bram generate block,
    //       so each adder sits next to its corresponding BRAM (avoids long
    //       cross-SLR routes on the 8192-bit data bus).
    //
    //       buffer_controller now only emits control signals (rd/wr addr+en,
    //       grants, metadata) and a single 1-bit task_is_aggregate_to_up_broadcast_out
    //       that selects sum vs. payload pass-through at each BRAM.
    // ------------------------------------------------------------

    localparam ADD_CHUNK_WIDTH = 32;
    localparam CHUNKS_ITEM = PAYLOAD_ITEM_WIDTH / ADD_CHUNK_WIDTH;

    localparam FP_LATENCY = 6;
    reg [4:0]  fp_latency_cnt;
    wire aggregate_is_float_en;
    assign aggregate_is_float_en = 0;





    // state defination

    reg [3:0]   current_state, next_state;

    localparam S_IDLE               = 4'b0000;
    localparam S_WAIT_READ          = 4'b0001;
    localparam S_COMPUTE_WRITE      = 4'b0010;
    localparam S_OUT_DEPARSER       = 4'b0011;
    localparam S_OUT_UP_BROADCAST   = 4'b0100;
    localparam S_CALC_FP            = 4'b0101;
    localparam S_PIPE               = 4'b0110;
    localparam S_PIPE2              = 4'b0111;
    // S_WAIT_READ2: 1-cycle bubble after grant. Compensates for the per-bank
    // local registration of rd_idx/rd_en_pack in aggregator_core_top, which
    // delays payload BRAM read by 1 cycle to keep the bank-decode LUT in the
    // same SLR as its BRAMs.
    localparam S_WAIT_READ2         = 4'b1000;


    assign in_ready = (current_state == S_IDLE);


    // ============================================================
    // 第一段：状态寄存器 (Sequential)
    // 只负责“过去”到“现在”的跳变
    // ============================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            current_state <= S_IDLE;
        else        
            current_state <= next_state;
    end

    always @(*) begin
        next_state = current_state;
        
        case (current_state) 
            S_IDLE: begin
                if ((aggregate_payload_en || for_port_retrans_read_buffer_en || for_down_broadcast_copy_buffer_en)) begin
                    next_state = S_WAIT_READ;
                end
            end

            S_WAIT_READ: begin
                if (aggregate_bram_rd_grant) begin
                    // Insert one extra wait cycle: payload BRAM read is
                    // delayed by 1 cycle due to per-bank local rd_idx/rd_en
                    // registration in aggregator_core_top.
                    next_state = S_WAIT_READ2;
                end
            end

            S_WAIT_READ2: begin
                if (task_is_retrans_to_deparser) begin
                    next_state = S_PIPE;
                end
                else if (task_is_float) begin
                    next_state = S_CALC_FP;
                end
                else begin
                    next_state = S_PIPE;
                end
            end

            S_PIPE: begin
                // 1st of 2-cycle bubble: per-bank FF -> bank mux -> payload_item_j_r.
                next_state = S_PIPE2;
            end

            S_PIPE2: begin
                // 2nd bubble: payload_item_j_r ready, aggregate_rd_data_j_r2 aligned.
                // Retrans path exits straight to deparser (no compute needed).
                if (task_is_retrans_to_deparser) begin
                    next_state = S_OUT_DEPARSER;
                end else begin
                    next_state = S_COMPUTE_WRITE;
                end
            end


            // S_WAIT_READ: begin
            //     if (aggregate_bram_rd_grant) begin
            //         next_state = task_is_retrans_to_deparser ? S_OUT_DEPARSER : S_COMPUTE_WRITE;
            //     end 
            // end

            S_CALC_FP: begin
                if (fp_latency_cnt == FP_LATENCY -1) begin
                    next_state = S_COMPUTE_WRITE;
                end
            end

            S_COMPUTE_WRITE: begin
                if (updated_aggregate_bram_wr_grant) begin
                    next_state = task_is_aggregate_to_up_broadcast ? S_OUT_UP_BROADCAST : S_OUT_DEPARSER;
                end
            end

            S_OUT_DEPARSER: begin
                if (to_deparser_ready) begin
                    next_state = S_IDLE;
                end
            end

            S_OUT_UP_BROADCAST: begin
                if (to_up_broadcast_ready) begin
                    next_state = S_IDLE;
                end
            end

            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

    // 处理输出的数据信号
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            payload_bram_rd_idx <= 0;
            payload_bram_rd_addr <= 0;
            payload_bram_rd_en_pack <= 0;
            aggregate_bram_rd_addr <= 0;
            aggregate_bram_rd_en_pack <= 0;
            updated_aggregate_bram_wr_addr <= 0;
            updated_aggregate_bram_wr_en_pack <= 0;

            task_is_aggregate_to_up_broadcast <= 0;
            task_is_copy_to_deparser <= 0;
            task_is_retrans_to_deparser <= 0;
            latched_metadata <= 0;
            task_is_float <= 0;
            fp_latency_cnt <= 0;


            // to_deparser_valid <= 0;
            to_deparser_up_port_retrans_ok_en <= 0;
            to_deparser_down_down_broadcast_ok_en <= 0;
            to_deparser_metadata_out <= 0;

            // to_up_broadcast_valid <= 0;
            to_up_broadcast_check_en <= 0;
            to_up_broadcast_metadata_out <= 0;
    
        end

        else begin

            // latency counter
            if (current_state == S_CALC_FP) begin
                fp_latency_cnt <= fp_latency_cnt + 1;
            end else begin
                fp_latency_cnt <= 0;
            end

                

            if (current_state != S_WAIT_READ) begin
                payload_bram_rd_en_pack <= 0;
                aggregate_bram_rd_en_pack <= 0;
            end
            
            updated_aggregate_bram_wr_en_pack <= 0;

            case (current_state)
                S_IDLE: begin

                    if (next_state == S_WAIT_READ) begin
                        task_is_aggregate_to_up_broadcast <= aggregate_payload_en_holdfix;
                        task_is_copy_to_deparser <= for_down_broadcast_copy_buffer_en_holdfix;
                        task_is_retrans_to_deparser <= for_port_retrans_read_buffer_en_holdfix;
                        latched_metadata <= metadata_in_holdfix;

                        task_is_float <= aggregate_is_float_en;

                        // payload_bram_rd_idx <= metadata_in[7:0];
                        // payload_bram_rd_addr <= metadata_in[15:8];
                        // payload_bram_rd_en_pack <= {PAYLOAD_ITEM_NUM{1'b1}};

                        // aggregate_bram_rd_addr <= metadata_in[15:8];
                        // aggregate_bram_rd_en_pack <= {PAYLOAD_ITEM_NUM{1'b1}};
                    end

                    if (next_state == S_IDLE) begin
                        payload_bram_rd_idx <= 0;
                        payload_bram_rd_addr <= 0;
                        aggregate_bram_rd_addr <= 0;
                        updated_aggregate_bram_wr_addr <= 0;
                    end
                end

                
                S_WAIT_READ: begin
                    payload_bram_rd_idx <= latched_metadata[7:0];
                    aggregate_bram_rd_addr <= latched_metadata[15:8];
                    payload_bram_rd_addr <= latched_metadata[15:8];

                    if (!aggregate_bram_rd_grant ) begin
                        aggregate_bram_rd_en_pack <= {PAYLOAD_ITEM_NUM{1'b1}};
                        payload_bram_rd_en_pack <= {PAYLOAD_ITEM_NUM{1'b1}};
                    end else begin
                        aggregate_bram_rd_en_pack <= 0;
                        payload_bram_rd_en_pack <= 0;
                    end
                end

                S_COMPUTE_WRITE: begin
                    updated_aggregate_bram_wr_addr <= latched_metadata[15:8];
                    updated_aggregate_bram_wr_en_pack <= {PAYLOAD_ITEM_NUM{1'b1}};
                    if (updated_aggregate_bram_wr_grant) begin
                       updated_aggregate_bram_wr_en_pack <= 0; 
                    end
                end

                
            endcase

            if (next_state == S_OUT_DEPARSER) begin
                to_deparser_metadata_out <= latched_metadata;
                to_deparser_up_port_retrans_ok_en <= task_is_retrans_to_deparser ? 1'b1 : 0;
                to_deparser_down_down_broadcast_ok_en <= task_is_copy_to_deparser ? 1'b1 : 0;
            end

            if (next_state == S_OUT_UP_BROADCAST) begin
                to_up_broadcast_metadata_out <= latched_metadata;
                to_up_broadcast_check_en <= 1'b1;
            end

            // 统一复位逻辑 
            if (next_state == S_IDLE) begin

                to_deparser_up_port_retrans_ok_en <= 0;
                to_up_broadcast_check_en <= 0;

                task_is_aggregate_to_up_broadcast <= 0;
                task_is_copy_to_deparser <= 0;
                task_is_retrans_to_deparser <= 0;
                latched_metadata <= 0;

                task_is_float <= 0;

                payload_bram_rd_idx <= 0;
                payload_bram_rd_addr <= 0;
                aggregate_bram_rd_addr <= 0;
                updated_aggregate_bram_wr_addr <= 0;
                to_deparser_metadata_out <= 0;
                to_up_broadcast_metadata_out <= 0;
                to_deparser_down_down_broadcast_ok_en <= 0;
            end
        end   
    end

    // 负责控制信号
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            to_deparser_valid <= 0;
            to_up_broadcast_valid <= 0;
        end
        else begin
            if (to_deparser_valid && to_deparser_ready) begin
                to_deparser_valid <= 0;
            end
            else if (next_state == S_OUT_DEPARSER) begin
                to_deparser_valid <= 1;
            end

            if (to_up_broadcast_valid && to_up_broadcast_ready) begin
                to_up_broadcast_valid <= 0;
            end
            else if (next_state == S_OUT_UP_BROADCAST) begin
                to_up_broadcast_valid <= 1;
            end
                
        end
        
    end
endmodule
