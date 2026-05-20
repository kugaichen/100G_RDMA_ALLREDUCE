`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/09/18 16:28:32
// Design Name: 
// Module Name: Typer
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


module Typer #(
    parameter OPCODE_ACK            = 8'h11,
    parameter OPCODE_FIRST          = 8'h0,
    parameter OPCODE_MIDDLE         = 8'h1,
    parameter OPCODE_LAST           = 8'h2,
    parameter OPCODE_SEND_ONLY      = 8'h4,

    parameter FAN_IN = 2,

    parameter TYPE_ACK_UP           = 3'b001,
    parameter TYPE_NOROOT_DATA_UP   = 3'b010,
    parameter TYPE_ROOT_DATA_UP     = 3'b011,
    parameter TYPE_DATA_DOWN        = 3'b100,
    parameter TYPE_ACK_DOWN         = 3'b101,
    parameter TYPE_NOVALID          = 3'b000,

    parameter RAM_SLOT_WIDTH        = 10

)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [3*8-1:0]        metadata_without_type,
    input  wire                  aggregate_en,
    input  wire [7:0]            opcode,
    
    output wire  [3*8-1:0]       metadata_with_type,
    // output wire                  valid_out,

    output reg                   data_root_up_en,
    output reg                   data_down_en,
    output reg                   ack_up_en,
    output reg                   data_noroot_up_en,
    output reg                   ack_down_en,

    output wire                  to_up_retrans_valid,
    output wire                  to_down_broadcast_valid,
    output wire                  to_deparser_valid,

    input wire                   to_up_retrans_ready,
    input wire                   to_down_broadcast_ready,
    input wire                   to_deparser_ready,

    output wire                  in_ready

);

    // ============================================================
    // Pipeline Control (Backpressure)
    // ============================================================
    wire stall;
    
    // Stage 2 (Output Stage) Valid Signal
    reg s2_valid;

    // 只有当 S2 有效且对应的下游未准备好时，才暂停流水线
    // 注意：这里利用了 s2_valid 和具体的 enable 信号来判断具体是哪条路堵了
    wire s2_stalled_by_up   = to_up_retrans_valid     && !to_up_retrans_ready;
    wire s2_stalled_by_down = to_down_broadcast_valid && !to_down_broadcast_ready;
    wire s2_stalled_by_dep  = to_deparser_valid       && !to_deparser_ready;

    assign stall = s2_valid && (s2_stalled_by_up || s2_stalled_by_down || s2_stalled_by_dep);
    assign in_ready = !stall;

    // pipeline Stage 1
    reg                         s1_valid;
    reg [7:0]                   s1_ingress_port;
    reg                         s1_root_info;
    reg [7:0]                   s1_opcode;
    reg [RAM_SLOT_WIDTH-1:0]    s1_psn;

    localparam S1_STAGE_BUS_WIDTH = 8 + 1 + 8 + RAM_SLOT_WIDTH;

    wire [S1_STAGE_BUS_WIDTH-1:0] s1_stage_bus;
    wire [S1_STAGE_BUS_WIDTH-1:0] s1_stage_bus_holdfix;
    wire [7:0]                    s1_ingress_port_holdfix;
    wire                          s1_root_info_holdfix;
    wire [7:0]                    s1_opcode_holdfix;
    wire [RAM_SLOT_WIDTH-1:0]     s1_psn_holdfix;
    wire                          s1_valid_holdfix;
    genvar                        s1_stage_holdfix_i;

    assign s1_stage_bus = {s1_ingress_port, s1_root_info, s1_opcode, s1_psn};
    assign {s1_ingress_port_holdfix, s1_root_info_holdfix, s1_opcode_holdfix, s1_psn_holdfix} =
        s1_stage_bus_holdfix;

    generate
        for (s1_stage_holdfix_i = 0; s1_stage_holdfix_i < S1_STAGE_BUS_WIDTH; s1_stage_holdfix_i = s1_stage_holdfix_i + 1) begin : gen_s1_stage_holdfix
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) u_lut1_s1_stage_holdfix (
                .I0(s1_stage_bus[s1_stage_holdfix_i]),
                .O(s1_stage_bus_holdfix[s1_stage_holdfix_i])
            );
        end
    endgenerate

    (* DONT_TOUCH = "TRUE" *) LUT1 #(
        .INIT(2'b10)
    ) u_lut1_s1_valid_holdfix (
        .I0(s1_valid),
        .O(s1_valid_holdfix)
    );

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            s1_valid           <= 1'b0;
            s1_ingress_port    <= 8'h00;
            s1_root_info       <= 1'b0;
            s1_opcode          <= 8'h00;
            s1_psn             <= {RAM_SLOT_WIDTH{1'b0}};
        end
        else if (!stall) begin
            s1_valid <= aggregate_en;
            if (aggregate_en) begin
                s1_ingress_port    <= metadata_without_type[7:0];
                s1_psn             <= metadata_without_type[8 +: RAM_SLOT_WIDTH];
                s1_root_info       <= metadata_without_type[8 + RAM_SLOT_WIDTH];
                s1_opcode          <= opcode;
            end
            else begin
                s1_ingress_port    <= 8'h00;
                s1_root_info       <= 1'b0;
                s1_opcode          <= 8'h00;
                s1_psn             <= {RAM_SLOT_WIDTH{1'b0}};
            end

        end
    end

    // ============================================================
    // Combinational Decode Logic (Between S1 and S2)
    // ============================================================
    reg [2:0] next_type;

    // 辅助判断信号
    wire is_data_op = (s1_opcode_holdfix == OPCODE_FIRST) || (s1_opcode_holdfix == OPCODE_MIDDLE) ||
                      (s1_opcode_holdfix == OPCODE_LAST)  || (s1_opcode_holdfix == OPCODE_SEND_ONLY);
    wire is_ack_op  = (s1_opcode_holdfix == OPCODE_ACK);
    wire is_root_port = (s1_ingress_port_holdfix == FAN_IN);

    always @(*) begin
        next_type = TYPE_NOVALID;
        if (s1_valid_holdfix) begin
            if (is_data_op) begin
                if (is_root_port)
                    next_type = TYPE_DATA_DOWN;
                else // Middle Port
                    next_type = s1_root_info_holdfix ? TYPE_ROOT_DATA_UP : TYPE_NOROOT_DATA_UP;
            end 
            else if (is_ack_op) begin
                if (is_root_port)
                    next_type = TYPE_ACK_DOWN;
                else // Middle Port
                    next_type = TYPE_ACK_UP;
            end
        end
    end

    // ============================================================
    // Stage 2: Output Register (Result Latch)
    // ============================================================
    reg [23:0] s2_metadata;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid          <= 1'b0;
            s2_metadata       <= 24'd0;
            data_root_up_en   <= 1'b0;
            data_noroot_up_en <= 1'b0;
            data_down_en      <= 1'b0;
            ack_up_en         <= 1'b0;
            ack_down_en       <= 1'b0;
        end else if (!stall) begin
            s2_valid <= s1_valid_holdfix;
            
            // 打包 Metadata (layout: {padding, type[2:0], root_info, psn[RAM_SLOT_WIDTH-1:0], ingress[7:0]})
            s2_metadata <= {{(12-RAM_SLOT_WIDTH){1'b0}}, next_type, s1_root_info_holdfix, s1_psn_holdfix, s1_ingress_port_holdfix};

            // 直接根据组合逻辑结果生成 Enable 信号，保证输出无毛刺
            data_root_up_en   <= s1_valid_holdfix && (next_type == TYPE_ROOT_DATA_UP);
            data_noroot_up_en <= s1_valid_holdfix && (next_type == TYPE_NOROOT_DATA_UP);
            data_down_en      <= s1_valid_holdfix && (next_type == TYPE_DATA_DOWN);
            ack_up_en         <= s1_valid_holdfix && (next_type == TYPE_ACK_UP);
            ack_down_en       <= s1_valid_holdfix && (next_type == TYPE_ACK_DOWN);
        end
    end

    // ============================================================
    // Output Assignments
    // ============================================================
    
    assign metadata_with_type = s2_metadata;

    // 下游 Valid 信号生成 (基于 Stage 2 的寄存器状态)
    assign to_up_retrans_valid     = s2_valid && (data_root_up_en || data_noroot_up_en);
    assign to_down_broadcast_valid = s2_valid && data_down_en;
    assign to_deparser_valid       = s2_valid && (ack_down_en || ack_up_en);




    // // pipeline Stage 2
    // reg                         s2_valid;
    // reg [7:0]                   s2_type;
    // reg [7:0]                   s2_type_next;
    // reg                         s2_root_info;
    // reg [7:0]                   s2_ingress_port;
    // reg [7:0]                   s2_psn;

    // wire                        is_data_opcode;
    // wire                        is_ack_opcode;
    // wire                        is_middle_port;
    // wire                        is_root_port;
    // wire                        is_root;

    // assign is_data_opcode = (s1_opcode == OPCODE_FIRST) || (s1_opcode == OPCODE_MIDDLE) ||
    //                         (s1_opcode == OPCODE_LAST) || (s1_opcode == OPCODE_SEND_ONLY);

    // assign is_ack_opcode  = (s1_opcode == OPCODE_ACK);
    // assign is_middle_port = (s1_ingress_port < FAN_IN);
    // assign is_root_port   = (s1_ingress_port == FAN_IN);
    // assign is_root        = (s1_root_info == 1);
    
    // always @(*) begin
    //     s2_type_next = TYPE_NOVALID;
        
    //     if (s1_valid) begin
    //         case ({is_data_opcode, is_ack_opcode, is_middle_port, is_root_port, is_root})
    //             5'b10101: s2_type_next = TYPE_ROOT_DATA_UP;
    //             5'b10100: s2_type_next = TYPE_NOROOT_DATA_UP;
    //             5'b10010: s2_type_next = TYPE_DATA_DOWN;
    //             5'b10011: s2_type_next = TYPE_DATA_DOWN;
    //             5'b01100: s2_type_next = TYPE_ACK_UP;
    //             5'b01011: s2_type_next = TYPE_ACK_DOWN;
    //             default : s2_type_next = TYPE_NOVALID;                    

    //         endcase    
    //     end
    // end


    // always @(posedge clk or negedge rst_n) begin
    //     if(!rst_n) begin   
    //         s2_valid            <= 1'b0;
    //         s2_type             <= TYPE_NOVALID;
    //         s2_root_info        <= 0;
    //         s2_ingress_port     <= 0;
    //         s2_psn              <= 0;
    //         s2_type_next        <= 0;
    //     end   
    //     else if (!stall) begin
    //         s2_valid            <= s1_valid;
    //         s2_root_info        <= s1_root_info;
    //         s2_psn              <= s1_psn;
    //         s2_ingress_port     <= s1_ingress_port;
    //         s2_type             <= s2_type_next;
    //     end          
    // end

    // // pipeline Stage 3
    // reg         s3_valid;
    // reg [23:0]  s3_metadata_with_type;

    // always @(posedge clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         s3_valid            <= 1'b0;
    //         s3_metadata_with_type <= 0;
    //         data_down_en        <= 0;
    //         data_root_up_en     <= 0;
    //         ack_up_en           <= 0;
    //         data_noroot_up_en   <= 0;
    //         ack_down_en         <= 0;
    //     end
    //     else if (!stall) begin
    //         s3_valid <= s2_valid;
    //         s3_metadata_with_type <= {4'b0000,s2_type,s2_root_info,s2_psn,s2_ingress_port};

    //         data_root_up_en <= s2_valid & (s2_type == TYPE_ROOT_DATA_UP);
    //         data_noroot_up_en <= s2_valid & (s2_type == TYPE_NOROOT_DATA_UP);
    //         data_down_en <= s2_valid & (s2_type == TYPE_DATA_DOWN);
    //         ack_up_en <= s2_valid & (s2_type == TYPE_ACK_UP);
    //         ack_down_en <= s2_valid & (s2_type == TYPE_ACK_DOWN);
    //     end
    // end

    
    // // 1. 判断当前 Stage 3 的数据是否被下游卡住
    // // 只有当 Valid 为高，且对应的 Ready 为低时，才需要 Stall
    // wire s3_stalled_by_up   = to_up_retrans_valid && !to_up_retrans_ready;
    // wire s3_stalled_by_down = to_down_broadcast_valid  && !to_down_broadcast_ready;
    // wire s3_stalled_by_dep  = to_deparser_valid && !to_deparser_ready;

    // // 只要任意一个有效路径被堵住，整个流水线就必须暂停
    // assign stall = s3_valid && (s3_stalled_by_up || s3_stalled_by_down || s3_stalled_by_dep);

    // // 告诉上游：如果我不暂停，我就能接收新数据
    // assign in_ready = !stall;

    // // assign valid_out = s3_valid;
    // assign metadata_with_type = s3_metadata_with_type;
    // assign to_up_retrans_valid = s3_valid && (data_root_up_en || data_noroot_up_en);
    // assign to_down_broadcast_valid = s3_valid && data_down_en;
    // assign to_deparser_valid = s3_valid && (ack_down_en || ack_up_en);

endmodule
