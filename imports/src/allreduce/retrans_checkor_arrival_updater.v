`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 2025/09/23 09:43:21
// Design Name:
// Module Name: retrans_checkor_arrival_updater
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//   - 维护一个基于BRAM的到达状态位图 (arrival_state)。
//   - 对于每个到来的请求 (由 psn/slot_idx 和 ingress_port 标识)，
//     执行“读-改-写”操作。
//   - 判断请求是首次到达还是重传。
//   - 判断在更新后，该slot的所有端口是否都已到齐。
//   - 通过标准的 ready/valid 握手协议与上下游模块交互。
//
// FSM Pipeline (3-cycle latency if out_ready is always high):
//   - ST_IDLE: 等待并接收请求。
//   - ST_READ: 从BRAM读取旧的位图。
//   - ST_UPDT: 计算新位图并写回BRAM。
//   - ST_OUT:  输出处理结果。
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module retrans_checkor_arrival_updater#(
    parameter FAN_IN               = 2,
    parameter METADATA_LEN         = 2*8+3+5,
    parameter RAM_SLOT_WIDTH       = 10,
    parameter BUFFER_SLOTS         = 16,
    parameter BUFFER_SLOTS_WIDTH   = $clog2(BUFFER_SLOTS),
    parameter FAN_IN_WIDTH         = $clog2(FAN_IN),
    parameter DATA_WIDTH           = 32,
    parameter ADDR_WIDTH           = 8

  )(
    input   wire                 clk,
    input   wire                 rst_n,

    //input
    input   wire                            in_valid,
    input   wire [METADATA_LEN-1:0]         in_metadata,

    //bitmap_rd
    output  reg                             arrival_state_rd_en,
    output  reg  [ADDR_WIDTH-1:0]           arrival_state_rd_addr,
    input   wire [DATA_WIDTH-1:0]           arrival_state_bitmap_in,
    input   wire                            arrival_state_rd_grant,

    //bitmap_wr bram
    input   wire                            arrival_state_wr_grant, 
    output  wire [ADDR_WIDTH-1:0]            arrival_state_wr_addr,
    output  wire                             arrival_state_wr_en,
    output  wire [DATA_WIDTH-1:0]            arrival_state_wr_data,

    //degree bram
    input   wire                            degree_state_rd_grant, 
    input   wire [DATA_WIDTH-1:0]           degree_state_in,
    output  reg                             degree_state_rd_en,
    output  reg  [ADDR_WIDTH-1:0]           degree_state_rd_addr,

    input   wire                            degree_state_wr_grant,
    output  wire  [ADDR_WIDTH-1:0]           degree_state_wr_addr,
    output  wire  [DATA_WIDTH-1:0]           degree_state_wr_data,
    output  wire                             degree_state_wr_en,

    //output_to_channel_buffer_controller                         
    output  wire                            to_buffer_valid,
    input   wire                            to_buffer_ready, 
    output  wire [METADATA_LEN-1:0]         to_buffer_metadata_out,  
    output  wire                            to_buffer_for_aggregate_payload_en,         
    output  wire                            to_buffer_need_aggregator_for_port_retrans,                       


    output  wire                            to_up_broadcast_valid,
    input   wire                            to_up_broadcast_ready,
    output  wire [METADATA_LEN-1:0]         to_up_broadcast_metadata_out,  
    output  wire                            to_broadcast_for_FAN_retrans_check_en,

    output  wire                            in_ready,

    // forwarding
    output  wire                            real_to_buffer_need_aggregator_for_port_retrans,
    output  wire                            real_to_broadcast_for_FAN_retrans_check_en 

 
    // ------------------------------------------------------------------
    // // forwarding data of bitmap_new / arrival_State from up_broadcast
    // input   wire                            forwarding_in_valid,
    // input   wire [ADDR_WIDTH-1:0]           forwarding_in_addr,
    // input   wire [DATA_WIDTH-1:0]           forwarding_in_data
    // ------------------------------------------------------------------

  );

// 状态机写法 

//   reg [7:0]      s1_idx_psn;
//   reg [7:0]      s1_ingress_port;
//   reg            s1_root_info;

//   reg [7:0]      s2_idx_psn;
//   reg [7:0]      s2_ingress_port;
//   reg            s2_root_info;

//   reg [DATA_WIDTH-1:0]      s2_port_mask;
//   reg [DATA_WIDTH-1:0]      s2_fin_mask;


//   localparam IDLE           = 2'd0;
//   localparam READ           = 2'd1;
//   localparam COMPUTE_UPDT   = 2'd2;
//   localparam OUT            = 2'd3;

//   reg [1:0] current_state, next_state;

//   wire                  is_retrans = |(arrival_state_bitmap_in & s2_port_mask);
//   wire                  is_first_arrival = !is_retrans;
//   wire [DATA_WIDTH-1:0] bitmap_new = arrival_state_bitmap_in | s2_port_mask;
//   wire                  fan_in_arrival = (arrival_state_bitmap_in & s2_fin_mask) == s2_fin_mask;

//   assign in_ready = (current_state == IDLE);

//   always @(*) begin

//     next_state = current_state;

//     case (current_state)
//         IDLE: begin
//             if (in_valid) begin
//                 next_state = READ;
//             end
//         end        

//         READ: begin
//             next_state = COMPUTE_UPDT;
//         end

//         COMPUTE_UPDT: begin
//             next_state = OUT;
//         end

//         OUT: begin
//             if (out_ready) begin
//                 next_state = IDLE;
//             end
//         end

//         default: begin
//             next_state = IDLE;
//         end
            
//     endcase
//   end


//   always @(posedge clk or negedge rst_n) begin
//     if(!rst_n) begin
//         current_state <= IDLE;
//         s1_idx_psn <= 0;
//         s1_ingress_port <= 0;
//         s1_root_info <= 0;

//         s2_idx_psn <= 0;
//         s2_ingress_port <= 0;
//         s2_root_info <= 0;
//         s2_fin_mask <= 0;
//         s2_port_mask <= 0;

//         degree_state_rd_addr <= 0;
//         degree_state_wr_data <= 0;
//         degree_state_wr_en <= 0;
//         degree_state_wr_data <= 0;

//         arrival_state_rd_addr <= 0;
//         arrival_state_wr_addr <= 0;
//         arrival_state_wr_en <= 0;
//         arrival_state_wr_data <= 0;

//         aggregate_buffer_en <= 0;
//         read_buffer_en <= 0;
//         FAN_retrans_check_en <= 0;
//         out_valid <= 0;
//     end

//     else begin
//         current_state <= next_state;

//         case (current_state) 
//             IDLE: begin
//                 s1_idx_psn <= in_metadata[15:8];
//                 s1_ingress_port <= in_metadata[7:0];
//                 s1_root_info <= in_metadata[16:16];
//                 arrival_state_rd_addr <= in_metadata[15:8];
//                 degree_state_rd_addr <= in_metadata[15:8];
//             end

//             READ: begin
//                 s2_idx_psn <= s1_idx_psn;
//                 s2_ingress_port <= s1_ingress_port;
//                 s2_root_info <= s1_root_info;
//                 s2_port_mask <= (s1_ingress_port <= FAN_IN) ? (32'h00000001 << s1_ingress_port) : {32{1'b0}};
//                 s2_fin_mask <= 32'h00000001 << FAN_IN;
//             end

//             COMPUTE_UPDT: begin
//                 out_valid <= 1'b1;
//                 degree_state_wr_en <= 1'b1;
//                 degree_state_wr_addr <= s2_idx_psn;
//                 degree_state_wr_data <= degree_state_in + 1;
//                 aggregate_buffer_en <= is_first_arrival;
//                 read_buffer_en <= (is_retrans && fan_in_arrival);
//                 FAN_retrans_check_en <= (!(is_retrans && fan_in_arrival)) & (!s2_root_info);
//                 if (is_first_arrival) begin
//                    arrival_state_wr_en <= 1'b1;
//                    arrival_state_wr_addr <= s2_idx_psn;
//                    // next_arrival_state_wr_data[s2_ingress_port] <= 1;
//                    arrival_state_wr_data <= bitmap_new;
//                 end
//             end

//             OUT: begin
//                 out_valid <= 1'b0;
//                 aggregate_buffer_en <= 0;
//                 read_buffer_en <= 0;
//                 FAN_retrans_check_en <= 0;
//                 arrival_state_wr_en <= 0;
//             end
            
//         endcase
//     end
//   end


// 流水线写法

    // S1, 解析in_metadata, 发起rd读
    reg [7:0]               s1_idx_psn;
    reg [7:0]               s1_ingress_port;
    reg                     s1_root_info;
    reg [METADATA_LEN-1:0]  s1_metadata;
    reg                     s1_valid;

    // S2，读延迟(arbiter)
    reg [7:0]               s2_idx_psn;
    reg [7:0]               s2_ingress_port;
    reg                     s2_root_info;
    reg [METADATA_LEN-1:0]  s2_metadata;
    reg                     s2_valid;
    // reg [DATA_WIDTH-1:0]    s2_port_mask;
    // reg [DATA_WIDTH-1:0]    s2_fin_mask;

    // S3, 读延迟(BRAM)
    reg [7:0]               s3_idx_psn;
    reg [7:0]               s3_ingress_port;
    reg                     s3_root_info;
    reg [METADATA_LEN-1:0]  s3_metadata;
    reg                     s3_valid;
    reg [DATA_WIDTH-1:0]    s3_arrival_state_in;
    reg [DATA_WIDTH-1:0]    s3_port_mask;
    reg [DATA_WIDTH-1:0]    s3_fin_mask;

    // // S4, 收回rd读后的数据，进行判断后计算
    // reg [7:0]               s4_idx_psn;
    // reg [7:0]               s4_ingress_port;
    // reg                     s4_root_info;
    // reg [METADATA_LEN-1:0]  s4_metadata;
    // reg                     s4_valid;

    // reg [DATA_WIDTH-1:0]    s4_port_mask;
    // reg [DATA_WIDTH-1:0]    s4_fin_mask;

    // reg [DATA_WIDTH-1:0]    s4_bitmap_new;
    // reg [DATA_WIDTH-1:0]    s4_degree_state_in;
    // reg [DATA_WIDTH-1:0]    s4_arrival_state_in;

    
    // S5, 发出计算后的数据写wr请求
    reg                     s5_valid;
    reg [7:0]               s5_idx_psn;
    reg [7:0]               s5_ingress_port;
    reg                     s5_root_info;
    reg [METADATA_LEN-1:0]  s5_metadata;

    reg                     s5_to_buffer_for_aggregate_payload_en;
    reg                     s5_need_agggregator_for_port_retrans;
    reg                     s5_to_broadcast_for_FAN_retrans_check_en;                     

    // S6 等待wr返回
    reg                     s6_valid;
    reg [METADATA_LEN-1:0]  s6_metadata;
    reg                     s6_to_buffer_for_aggregate_payload_en;
    reg                     s6_need_agggregator_for_port_retrans;
    reg                     s6_to_broadcast_for_FAN_retrans_check_en; 

    // S7 wr写成功
    reg                     s7_valid;
    reg [METADATA_LEN-1:0]  s7_metadata;
    reg                     s7_to_buffer_for_aggregate_payload_en;
    reg                     s7_need_agggregator_for_port_retrans;
    reg                     s7_to_broadcast_for_FAN_retrans_check_en; 


    // 状态判断信号
    // wire                    is_retrans;
    // wire                    is_first_arrival;
    // wire [DATA_WIDTH-1:0]   bitmap_new;
    // wire                    fan_in_arrival;

    reg                    is_retrans;
    reg                    is_first_arrival;
    reg [DATA_WIDTH-1:0]   bitmap_new;
    reg                    port_need_retrans;
    reg                    port_not_need_retrans;

    // // 反压信号
    // wire s1_can_accept;
    // wire s2_can_accept;
    // wire s3_can_accept;
    // wire s4_can_accept;
    // wire s5_can_accept;
    // wire s6_can_accept;
    // wire s7_can_accept;


    // // backpressure
    // wire task_for_buffer = s7_to_buffer_for_aggregate_payload_en || s7_need_agggregator_for_port_retrans;
    // wire task_for_up_broadcast = s7_to_broadcast_for_FAN_retrans_check_en;

    // // backpressure
    // wire buffer_done = !to_buffer_valid || (to_buffer_valid && to_buffer_ready);
    // wire up_broadcast_done = !to_up_broadcast_valid || (to_up_broadcast_valid && to_up_broadcast_ready);

    // wire out_ready = buffer_done && up_broadcast_done;
    
    // assign s7_can_accept = !s7_valid || (s7_valid && out_ready);
    // assign s6_can_accept = !s6_valid || (s6_valid && s7_can_accept);
    // assign s5_can_accept = !s5_valid || (s5_valid && s6_can_accept);
    // assign s4_can_accept = !s4_valid || (s4_valid && s5_can_accept);
    // assign s3_can_accept = !s3_valid || (s3_valid && s4_can_accept);
    // assign s2_can_accept = !s2_valid || (s2_valid && s3_can_accept);
    // assign s1_can_accept = !s1_valid || (s1_valid && s2_can_accept);

    // assign in_ready = s1_can_accept;
    // assign out_valid = s7_valid;

    // 流水线实现
    // S1逻辑实现
    localparam RETRANS_S1_STAGE_BUS_WIDTH = METADATA_LEN + 17;
    localparam RETRANS_S3_STAGE_BUS_WIDTH = METADATA_LEN + 17 + (2 * DATA_WIDTH);

    wire [RETRANS_S1_STAGE_BUS_WIDTH-1:0] s1_stage_bus;
    wire [RETRANS_S1_STAGE_BUS_WIDTH-1:0] s1_stage_bus_holdfix;
    wire [7:0] s1_idx_psn_holdfix;
    wire [7:0] s1_ingress_port_holdfix;
    wire s1_root_info_holdfix;
    wire [METADATA_LEN-1:0] s1_metadata_holdfix;

    wire [RETRANS_S1_STAGE_BUS_WIDTH-1:0] s2_stage_bus;
    wire [RETRANS_S1_STAGE_BUS_WIDTH-1:0] s2_stage_bus_holdfix;
    wire [7:0] s2_idx_psn_holdfix;
    wire [7:0] s2_ingress_port_holdfix;
    wire s2_root_info_holdfix;
    wire [METADATA_LEN-1:0] s2_metadata_holdfix;

    wire [RETRANS_S3_STAGE_BUS_WIDTH-1:0] s3_stage_bus;
    wire [RETRANS_S3_STAGE_BUS_WIDTH-1:0] s3_stage_bus_holdfix;
    wire [7:0] s3_idx_psn_holdfix;
    wire [7:0] s3_ingress_port_holdfix;
    wire s3_root_info_holdfix;
    wire [METADATA_LEN-1:0] s3_metadata_holdfix;
    wire [DATA_WIDTH-1:0] s3_port_mask_holdfix;
    wire [DATA_WIDTH-1:0] s3_fin_mask_holdfix;

    wire [DATA_WIDTH-1:0] arrival_state_bitmap_in_holdfix;
    wire [DATA_WIDTH-1:0] degree_state_in_holdfix;

    wire s1_valid_holdfix;
    wire s2_valid_holdfix;
    wire s3_valid_holdfix;
    wire s1_can_accept, s2_can_accept, s3_can_accept, s4_can_accept;
    // backpressure wires declared above

    assign s1_stage_bus = {
        s1_idx_psn,
        s1_ingress_port,
        s1_root_info,
        s1_metadata
    };
    assign {
        s1_idx_psn_holdfix,
        s1_ingress_port_holdfix,
        s1_root_info_holdfix,
        s1_metadata_holdfix
    } = s1_stage_bus_holdfix;

    assign s2_stage_bus = {
        s2_idx_psn,
        s2_ingress_port,
        s2_root_info,
        s2_metadata
    };
    assign {
        s2_idx_psn_holdfix,
        s2_ingress_port_holdfix,
        s2_root_info_holdfix,
        s2_metadata_holdfix
    } = s2_stage_bus_holdfix;

    assign s3_stage_bus = {
        s3_idx_psn,
        s3_ingress_port,
        s3_root_info,
        s3_metadata,
        s3_port_mask,
        s3_fin_mask
    };
    assign {
        s3_idx_psn_holdfix,
        s3_ingress_port_holdfix,
        s3_root_info_holdfix,
        s3_metadata_holdfix,
        s3_port_mask_holdfix,
        s3_fin_mask_holdfix
    } = s3_stage_bus_holdfix;

    genvar retrans_s1_holdfix_i;
    generate
        for (retrans_s1_holdfix_i = 0; retrans_s1_holdfix_i < RETRANS_S1_STAGE_BUS_WIDTH; retrans_s1_holdfix_i = retrans_s1_holdfix_i + 1) begin : retrans_s1_stage_holdfix_gen
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) retrans_s1_stage_holdfix_lut (
                .O(s1_stage_bus_holdfix[retrans_s1_holdfix_i]),
                .I0(s1_stage_bus[retrans_s1_holdfix_i])
            );
        end
    endgenerate

    genvar retrans_s2_holdfix_i;
    generate
        for (retrans_s2_holdfix_i = 0; retrans_s2_holdfix_i < RETRANS_S1_STAGE_BUS_WIDTH; retrans_s2_holdfix_i = retrans_s2_holdfix_i + 1) begin : retrans_s2_stage_holdfix_gen
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) retrans_s2_stage_holdfix_lut (
                .O(s2_stage_bus_holdfix[retrans_s2_holdfix_i]),
                .I0(s2_stage_bus[retrans_s2_holdfix_i])
            );
        end
    endgenerate

    genvar retrans_s3_holdfix_i;
    generate
        for (retrans_s3_holdfix_i = 0; retrans_s3_holdfix_i < RETRANS_S3_STAGE_BUS_WIDTH; retrans_s3_holdfix_i = retrans_s3_holdfix_i + 1) begin : retrans_s3_stage_holdfix_gen
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) retrans_s3_stage_holdfix_lut (
                .O(s3_stage_bus_holdfix[retrans_s3_holdfix_i]),
                .I0(s3_stage_bus[retrans_s3_holdfix_i])
            );
        end
    endgenerate

    genvar retrans_arrival_holdfix_i;
    generate
        for (retrans_arrival_holdfix_i = 0; retrans_arrival_holdfix_i < DATA_WIDTH; retrans_arrival_holdfix_i = retrans_arrival_holdfix_i + 1) begin : retrans_arrival_holdfix_gen
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) retrans_arrival_holdfix_lut (
                .O(arrival_state_bitmap_in_holdfix[retrans_arrival_holdfix_i]),
                .I0(arrival_state_bitmap_in[retrans_arrival_holdfix_i])
            );
        end
    endgenerate

    genvar retrans_degree_holdfix_i;
    generate
        for (retrans_degree_holdfix_i = 0; retrans_degree_holdfix_i < DATA_WIDTH; retrans_degree_holdfix_i = retrans_degree_holdfix_i + 1) begin : retrans_degree_holdfix_gen
            (* DONT_TOUCH = "TRUE" *) LUT1 #(
                .INIT(2'b10)
            ) retrans_degree_holdfix_lut (
                .O(degree_state_in_holdfix[retrans_degree_holdfix_i]),
                .I0(degree_state_in[retrans_degree_holdfix_i])
            );
        end
    endgenerate

    (* DONT_TOUCH = "TRUE" *) LUT1 #(
        .INIT(2'b10)
    ) retrans_s1_valid_holdfix_lut (
        .O(s1_valid_holdfix),
        .I0(s1_valid)
    );

    (* DONT_TOUCH = "TRUE" *) LUT1 #(
        .INIT(2'b10)
    ) retrans_s2_valid_holdfix_lut (
        .O(s2_valid_holdfix),
        .I0(s2_valid)
    );

    (* DONT_TOUCH = "TRUE" *) LUT1 #(
        .INIT(2'b10)
    ) retrans_s3_valid_holdfix_lut (
        .O(s3_valid_holdfix),
        .I0(s3_valid)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_idx_psn <= 0;
            s1_ingress_port <= 0;
            s1_root_info <= 0;
            s1_valid <= 0;
            s1_metadata <= 0;

            arrival_state_rd_en <= 0;
            degree_state_rd_en <= 0;
            arrival_state_rd_addr <= 0;
            degree_state_rd_addr <= 0;
        end
        else begin
            arrival_state_rd_en <= 0;
            degree_state_rd_en <= 0;

            if (s2_can_accept) begin // 如果下游准备好了
            // 从上游接收新数据
                s1_valid        <= in_valid; 
                s1_idx_psn      <= in_metadata[15:8];
                s1_ingress_port <= in_metadata[7:0];
                s1_root_info    <= in_metadata[8 + RAM_SLOT_WIDTH];
                s1_metadata     <= in_metadata;
            
                // 如果有新数据进来，就发起读请求
                if (in_valid) begin
                    arrival_state_rd_en   <= 1'b1;
                    degree_state_rd_en    <= 1'b1;
                    arrival_state_rd_addr <= in_metadata[15:8];
                    degree_state_rd_addr  <= in_metadata[15:8];
                end
            end

            // 如果下游没准备好 (s2_can_accept=0)，但 s1 本身是空的 (s1_valid=0)，
            // 也可以接收新数据。
            else if (!s1_valid) begin 
                s1_valid        <= in_valid;
                s1_idx_psn      <= in_metadata[15:8];
                s1_ingress_port <= in_metadata[7:0];
                s1_root_info    <= in_metadata[8 + RAM_SLOT_WIDTH];
                s1_metadata     <= in_metadata;

                if (in_valid) begin
                    arrival_state_rd_en   <= 1'b1;
                    degree_state_rd_en    <= 1'b1;
                    arrival_state_rd_addr <= in_metadata[15:8];
                    degree_state_rd_addr  <= in_metadata[15:8];
                end
            end

            // if(!s1_valid) begin
            //     if (in_valid && in_ready) begin
            //         s1_valid <= 1;
            //         s1_idx_psn <= in_metadata[15:8];
            //         s1_ingress_port <= in_metadata[7:0];
            //         s1_root_info <= in_metadata[16:16];

            //         arrival_state_rd_en <= 1;
            //         degree_state_rd_en <= 1;
            //         arrival_state_rd_addr <= in_metadata[15:8];
            //         degree_state_rd_addr <= in_metadata[15:8];
            //     end
            // end
            
            // else begin
            //     if (s1_valid && s2_can_accept) begin
            //         s1_valid <= 0;
            //     end              
            // end

                 
                 
        end
    end

    // S2的逻辑实现
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_idx_psn <= 0;
            s2_ingress_port <= 0;
            s2_root_info <= 0;
            s2_valid <= 0;
            s2_metadata <= 0;
        end

        else begin
            
            if (s3_can_accept) begin
                s2_valid <= s1_valid_holdfix;
                s2_idx_psn <= s1_idx_psn_holdfix;
                s2_ingress_port <= s1_ingress_port_holdfix;
                s2_root_info <= s1_root_info_holdfix;
                s2_metadata <= s1_metadata_holdfix;

            end

            else if (!s2_valid) begin
                s2_valid <= s1_valid_holdfix;
                s2_idx_psn <= s1_idx_psn_holdfix;
                s2_ingress_port <= s1_ingress_port_holdfix;
                s2_root_info <= s1_root_info_holdfix;
                s2_metadata <= s1_metadata_holdfix;
            end


            // if (!s2_valid) begin
            //     if (s1_valid && s2_can_accept) begin
            //         s2_valid <= 1;
            //         s2_idx_psn <= s1_idx_psn;
            //         s2_ingress_port <= s1_ingress_port;
            //         s2_root_info <= s1_root_info;
            //     end  
            // end

            // else begin
            //     if (s2_valid && s3_can_accept && arrival_state_rd_grant && degree_state_rd_grant) begin
            //         s2_valid <= 1'b0;
            //     end
            // end

    
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_idx_psn <= 0;
            s3_ingress_port <= 0;
            s3_root_info <= 0;
            s3_valid <= 0;
            s3_port_mask <= 0;
            s3_fin_mask <=0;
            s3_metadata <= 0;
        end

        else begin
            // s3_valid <= 0;
            if (s4_can_accept && arrival_state_rd_grant && degree_state_rd_grant) begin
                s3_valid <= s2_valid_holdfix;
                s3_idx_psn <= s2_idx_psn_holdfix;
                s3_ingress_port <= s2_ingress_port_holdfix;
                s3_root_info <= s2_root_info_holdfix;
                s3_metadata <= s2_metadata_holdfix;
                // s3_port_mask <= (s2_ingress_port <= FAN_IN) ? (32'h00000001 << s2_ingress_port) : {32{1'b0}};
                // s3_fin_mask <= 32'h00000001 << FAN_IN; 
                s3_port_mask <= (s2_ingress_port_holdfix <= FAN_IN) ? (64'h0000000000000001 << s2_ingress_port_holdfix) : {64{1'b0}};
                s3_fin_mask <= 64'h0000000000000001 << FAN_IN; 
            end

            else if (!s3_valid) begin
                    s3_valid <= s2_valid_holdfix;
                    s3_idx_psn <= s2_idx_psn_holdfix;
                    s3_ingress_port <= s2_ingress_port_holdfix;
                    s3_metadata <= s2_metadata_holdfix;
                    s3_root_info <= s2_root_info_holdfix;
                    // s3_port_mask <= (s2_ingress_port <= FAN_IN) ? (32'h00000001 << s2_ingress_port) : {32{1'b0}};
                    // s3_fin_mask <= 32'h00000001 << FAN_IN; 
                    s3_port_mask <= (s2_ingress_port_holdfix <= FAN_IN) ? (64'h0000000000000001 << s2_ingress_port_holdfix) : {64{1'b0}};
                    s3_fin_mask <= 64'h0000000000000001 << FAN_IN; 
            end

            else begin
                s3_valid <= 0;
                s3_metadata <= 0;
            end

            // if (!s3_valid) begin
            //     if (s2_valid && s3_can_accept && arrival_state_rd_grant && degree_state_rd_grant) begin
            //         s3_valid <= 1;
            //         s3_idx_psn <= s2_idx_psn;
            //         s3_ingress_port <= s2_ingress_port;
            //         s3_root_info <= s2_root_info;
            //         // s3_bitmap_new <= bitmap_new | s2_port_mask;
            //         s3_port_mask <= (s2_ingress_port <= FAN_IN) ? (32'h00000001 << s2_ingress_port) : {32{1'b0}};
            //         s3_fin_mask <= 32'h00000001 << FAN_IN;
            //     end              
            // end

            // else begin
            //      if (s3_valid && s4_can_accept) begin
            //         s3_valid <= 1'b0;
            //     end
            // end
            
        end
    end

    reg [METADATA_LEN-1:0]  s4_metadata;
    reg                     s4_valid;

    // result 
    reg                     s4_is_first_arrival;
    reg                     s4_is_retrans;
    reg                     s4_port_need_retrans;
    reg                     s4_port_not_need_retrans;
    reg [DATA_WIDTH-1:0]    s4_degree_state_in;
    reg [DATA_WIDTH-1:0]    s4_bitmap_new;
    reg [7:0]               s4_idx_psn;
    reg                     s4_root_info;


    // =========================================================================
    // [新增] S4 完成状态追踪寄存器
    // =========================================================================
    reg                     s4_write_done;      // 内部 BRAM 写操作是否已完成
    reg                     s4_buffer_done;     // Buffer 控制器请求是否已握手成功
    reg                     s4_broadcast_done;  // Broadcast 请求是否已握手成功

    // =========================================================================
    // Pipeline Control Logic (Backpressure)
    // =========================================================================
    
    // 定义任务 (Task Definition)
    wire task_for_buffer    = s4_valid && (s4_is_first_arrival || s4_is_retrans);
    wire task_for_broadcast = s4_valid && (s4_is_retrans && !s4_root_info);


    // 只有当所有需要的任务都完成(Done) 或者 不需要该任务时，才算 S4处理完毕
    wire buffer_finish    = !task_for_buffer    || s4_buffer_done;
    wire broadcast_finish = !task_for_broadcast || s4_broadcast_done;

    wire s4_done = buffer_finish && broadcast_finish;

    assign s4_can_accept = !s4_valid || s4_done;
    assign s3_can_accept = !s3_valid || (s3_valid && s4_can_accept);
    assign s2_can_accept = !s2_valid || (s2_valid && s3_can_accept);
    assign s1_can_accept = !s1_valid || (s1_valid && s2_can_accept);

    assign in_ready = s1_can_accept;

    // =========================================================================
    // Output Logic (Core Fix: Masking with !Done)
    // =========================================================================

    // 1. Valid 信号：必须屏蔽已完成的任务，防止重复握手
    assign to_buffer_valid       = task_for_buffer && !s4_buffer_done;
    assign to_up_broadcast_valid = task_for_broadcast && !s4_broadcast_done;

    // 2. 写信号：必须屏蔽已完成的写操作，防止重复累加
    assign degree_state_wr_en    = s4_valid && !s4_write_done; 
    assign arrival_state_wr_en   = s4_valid && s4_is_first_arrival && !s4_write_done;

    // 3. 数据总线 (保持直连)
    assign degree_state_wr_addr  = s4_idx_psn;
    assign degree_state_wr_data  = s4_degree_state_in + 1;
    assign arrival_state_wr_addr = s4_idx_psn;
    assign arrival_state_wr_data = s4_bitmap_new;

    assign to_buffer_metadata_out = s4_metadata;
    assign to_up_broadcast_metadata_out = s4_metadata;
    
    // 4. 控制信号 (Forwarding / Logic) 
    assign to_buffer_for_aggregate_payload_en          = s4_valid ? (s4_is_first_arrival && to_buffer_valid) : 0;
    
    assign to_buffer_need_aggregator_for_port_retrans  = s4_valid ? (s4_is_retrans && to_buffer_valid) : 0;
    assign to_broadcast_for_FAN_retrans_check_en       = s4_valid ? (s4_is_retrans && !s4_root_info && to_up_broadcast_valid) : 0;
    
    assign real_to_buffer_need_aggregator_for_port_retrans = s4_valid ? (s4_is_retrans && s4_port_need_retrans && to_buffer_valid) : 0;
    assign real_to_broadcast_for_FAN_retrans_check_en      = s4_valid ? (s4_is_retrans && s4_port_not_need_retrans && !s4_root_info && to_up_broadcast_valid) : 0;


    // =========================================================================
    // S4 Sequential Logic (State Machine)
    // =========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s4_metadata <= 0;
            s4_valid <= 0;
            s4_is_first_arrival <= 0;
            s4_is_retrans <= 0;
            s4_port_need_retrans <= 0;
            s4_port_not_need_retrans <= 0;
            s4_degree_state_in <= 0;
            s4_bitmap_new <= 0;
            s4_idx_psn <= 0;
            s4_root_info <= 0;
            
            // Reset Done Flags
            s4_write_done <= 0;
            s4_buffer_done <= 0;
            s4_broadcast_done <= 0;
        end

        else begin
            // Path 1: 流水线流动
            if (s4_can_accept) begin

                // 复位 Done 标记，准备接收下一包
                s4_write_done <= 0;
                s4_buffer_done <= 0;
                s4_broadcast_done <= 0;

                if (s3_valid_holdfix) begin
                    s4_valid <= 1'b1;

                    s4_metadata        <= s3_metadata_holdfix;
                    s4_idx_psn         <= s3_idx_psn_holdfix;
                    s4_root_info       <= s3_root_info_holdfix;
                    s4_degree_state_in <= degree_state_in_holdfix;

                    s4_is_retrans     <= |(arrival_state_bitmap_in_holdfix & s3_port_mask_holdfix);
                    s4_is_first_arrival <= !(|(arrival_state_bitmap_in_holdfix & s3_port_mask_holdfix));
                    s4_port_need_retrans <= |(arrival_state_bitmap_in_holdfix  & s3_fin_mask_holdfix);
                    s4_port_not_need_retrans <= !(|(arrival_state_bitmap_in_holdfix & s3_fin_mask_holdfix));
                    s4_bitmap_new     <= arrival_state_bitmap_in_holdfix | s3_port_mask_holdfix;
                end
                else begin
                    s4_valid <= 1'b0;
                end
            end
            
            // Path 2: 流水线停顿 (Stall)
            else begin
                // 在停顿期间，记录已完成的任务，防止重复输出

                // A. Buffer Handshake Capture
                if (to_buffer_valid && to_buffer_ready) begin
                    s4_buffer_done <= 1'b1;
                end

                // B. Broadcast Handshake Capture
                if (to_up_broadcast_valid && to_up_broadcast_ready) begin
                    s4_broadcast_done <= 1'b1;
                end

                // C. Write Operation Capture
                // 只要当前是 Valid 的，第一拍组合逻辑肯定已经发了写信号，
                // 所以我们标记 Write Done，下一拍 assign degree_state_wr_en 就会变成 0
                if (s4_valid) begin
                    s4_write_done <= 1'b1;
                end
            end     
        end
    end




    // wire task_for_buffer = s4_valid && (s4_is_first_arrival || (s4_is_retrans && s4_port_need_retrans));
    // wire task_for_broadcast = s4_valid && (s4_is_retrans && s4_port_not_need_retrans && !s4_root_info);

    // wire buffer_ready_check = !task_for_buffer || to_buffer_ready;
    // wire broadcast_ready_check = !task_for_broadcast || to_up_broadcast_ready;
    // wire s4_done = buffer_ready_check && broadcast_ready_check;

    // 只有当所有需要的任务都完成(Done) 或者 不需要该任务时，才算 S4处理完毕
    // wire buffer_finish    = !task_for_buffer    || s4_buffer_done;
    // wire broadcast_finish = !task_for_broadcast || s4_broadcast_done;

    // wire s4_done = buffer_finish && broadcast_finish;

    // assign s4_can_accept = !s4_valid || s4_done;
    // assign s3_can_accept = !s3_valid || (s3_valid && s4_can_accept);
    // assign s2_can_accept = !s2_valid || (s2_valid && s3_can_accept);
    // assign s1_can_accept = !s1_valid || (s1_valid && s2_can_accept);

    // assign in_ready = s1_can_accept;

    // =========================================================================
    // Output Logic (从 S4 直接输出，不再经过 S5-S7)
    // =========================================================================

    // Valid 信号直接由 S4_valid 和 握手逻辑 驱动
    // assign to_buffer_valid       = s4_valid && task_for_buffer;
    // assign to_up_broadcast_valid = s4_valid && task_for_broadcast;

    // Payload 信号
    // assign to_buffer_metadata_out = s4_metadata;
    // assign to_up_broadcast_metadata_out = s4_metadata;
    
    // assign to_buffer_for_aggregate_payload_en          = s4_valid ? s4_is_first_arrival : 0;
    // ----------- good

    // wire task_for_buffer = s4_valid && (s4_is_first_arrival || (s4_is_retrans && s4_port_need_retrans));
    // wire task_for_broadcast = s4_valid && (s4_is_retrans && s4_port_not_need_retrans && !s4_root_info);

    // assign to_buffer_need_agggregator_for_port_retrans = s4_valid ? (s4_is_retrans && s4_port_need_retrans) : 0;
    // assign to_broadcast_for_FAN_retrans_check_en       = s4_valid ? (s4_is_retrans && s4_port_not_need_retrans && !s4_root_info) : 0;
    // ------------ good

    // ------------------forwaridng
    // assign to_buffer_need_aggregator_for_port_retrans = s4_valid ? s4_is_retrans : 0;
    // assign to_broadcast_for_FAN_retrans_check_en       = s4_valid ? (s4_is_retrans && !s4_root_info) : 0;

    // assign real_to_buffer_need_aggregator_for_port_retrans = s4_valid ? (s4_is_retrans && s4_port_need_retrans) : 0;
    // assign real_to_broadcast_for_FAN_retrans_check_en       = s4_valid ? (s4_is_retrans && s4_port_not_need_retrans && !s4_root_info) : 0;

    // wire task_for_buffer = s4_valid && (s4_is_first_arrival || (s4_is_retrans));
    // wire task_for_broadcast = s4_valid && (s4_is_retrans && !s4_root_info);


    // =========================================================================
    // 输出掩码逻辑 (Output Masking) - 核心修复
    // =========================================================================
    
    // // 只有在 (需要发任务) 且 (该任务还没显示完成) 时，才拉高 Valid
    // assign to_buffer_valid       = task_for_buffer && !s4_buffer_done;
    // assign to_up_broadcast_valid = task_for_broadcast && !s4_broadcast_done;

    // // 写操作同理，防止 BRAM 被多次写入
    // assign degree_state_wr_en    = s4_valid && !s4_write_done;
    // assign arrival_state_wr_en   = s4_valid && s4_is_first_arrival && !s4_write_done;

    // // 数据总线不需要屏蔽，保持直连即可
    // assign degree_state_wr_addr  = s4_idx_psn;
    // assign degree_state_wr_data  = s4_degree_state_in + 1;
    // assign arrival_state_wr_addr = s4_idx_psn;
    // assign arrival_state_wr_data = s4_bitmap_new;

    // assign to_buffer_metadata_out = s4_metadata;
    // assign to_up_broadcast_metadata_out = s4_metadata;
    
    // // Control bit 保持原样 (valid 拉低后，这些信号的值无关紧要)
    // assign to_buffer_for_aggregate_payload_en          = s4_is_first_arrival;
    // assign to_buffer_need_aggregator_for_port_retrans  = s4_is_retrans; // 简化版，具体根据你的需求
    
    // // Forwarding specific
    // assign to_buffer_need_aggregator_for_port_retrans  = s4_valid ? s4_is_retrans : 0;
    // assign to_broadcast_for_FAN_retrans_check_en       = s4_valid ? (s4_is_retrans && !s4_root_info) : 0;
    
    // assign real_to_buffer_need_aggregator_for_port_retrans = s4_valid ? (s4_is_retrans && s4_port_need_retrans) : 0;
    // assign real_to_broadcast_for_FAN_retrans_check_en      = s4_valid ? (s4_is_retrans && s4_port_not_need_retrans && !s4_root_info) : 0;




    // //-------------------forwarding

    // // =========================================================================
    // // Write Logic (Parallel / Posted Write)
    // // =========================================================================
    
    // // 写入逻辑完全并行，由组合逻辑驱动
    // // 只要 S4 有效，我们就一直拉高 wr_en，直到 s4_valid 被新的或者空泡冲掉
    
    // assign degree_state_wr_en    = s4_valid; // 每次都写 Degree + 1
    // assign degree_state_wr_addr  = s4_idx_psn;
    // assign degree_state_wr_data  = s4_degree_state_in + 1;

    // assign arrival_state_wr_en   = s4_valid && s4_is_first_arrival; // 只有首次到达写 Bitmap
    // assign arrival_state_wr_addr = s4_idx_psn;
    // assign arrival_state_wr_data = s4_bitmap_new;

    // // S4的逻辑实现

    // always @(posedge clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         s4_metadata <= 0;
    //         s4_valid <= 0;
    //         s4_is_first_arrival <= 0;
    //         s4_is_retrans <= 0;
    //         s4_port_need_retrans <= 0;
    //         s4_port_not_need_retrans <= 0;
    //         s4_degree_state_in <= 0;
    //         s4_bitmap_new <= 0;
    //         s4_idx_psn <= 0;
    //         s4_root_info <= 0;
    //     end

    //     else begin
    //         if (s4_can_accept) begin

    //             s4_write_done <= 0;
    //             s4_buffer_done <= 0;
    //             s4_broadcast_done <= 0;
    //             if (s3_valid) begin
    //                 s4_valid <= 1'b1;

    //                 s4_metadata        <= s3_metadata;
    //                 s4_idx_psn         <= s3_idx_psn;
    //                 s4_root_info       <= s3_root_info;
    //                 s4_degree_state_in <= degree_state_in;

    //                 s4_is_retrans     <= |(arrival_state_bitmap_in & s3_port_mask);
    //                 s4_is_first_arrival <= !(|(arrival_state_bitmap_in & s3_port_mask));
    //                 s4_port_need_retrans <= |(arrival_state_bitmap_in  & s3_fin_mask);
    //                 s4_port_not_need_retrans <= !(|(arrival_state_bitmap_in & s3_fin_mask));
    //                 s4_bitmap_new     <= arrival_state_bitmap_in | s3_port_mask;
    //             end

    //             else begin
    //                 s4_valid <= 1'b0;
    //             end
    //         end

    //         else begin
    //             // --- Case 2: 流水线停顿 (Stall) ---
    //             // 在停顿期间，我们需要记录哪些任务正好在这一拍完成了。
    //             // 这样在下一拍（虽然还是由于其他原因停顿），已经完成的任务 valid 会变成 0，防止重复触发。

    //             // A. Track Buffer Handshake
    //             if (to_buffer_valid && to_buffer_ready) begin
    //                 s4_buffer_done <= 1'b1;
    //             end

    //             // B. Track Broadcast Handshake
    //             if (to_up_broadcast_valid && to_up_broadcast_ready) begin
    //                 s4_broadcast_done <= 1'b1;
    //             end

    //             // C. Track Internal Write
    //             // 写操作在 Valid 的第一拍肯定发出了（组合逻辑），
    //             // 所以只要当前是 Valid 的，且我们被迫停顿了，就标记写操作已完成，防止下一拍重复写。
    //             if (s4_valid) begin
    //                 s4_write_done <= 1'b1;
    //             end
    //         end
                 
    //     end
    // end


    ////           past ---------normal
    // // S4的逻辑实现
    // always @(posedge clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         s4_idx_psn <= 0;
    //         s4_ingress_port <= 0;
    //         s4_root_info <= 0;
    //         s4_metadata <= 0;
    //         s4_valid <= 0;
            
    //         s4_fin_mask <= 0;
    //         s4_port_mask <= 0;

    //         s4_degree_state_in <= 0;
    //         s4_arrival_state_in <= 0;
    //         is_retrans <= 0;
    //         is_first_arrival <= 0;
    //         port_need_retrans <= 0;
    //         port_not_need_retrans <= 0;
    //         s4_bitmap_new <= 0;

    //     end
    //     else begin
    //         // s4_valid <= 0;

    //         if (s5_can_accept) begin
    //             s4_valid <= s3_valid;
    //             s4_idx_psn <= s3_idx_psn;
    //             s4_ingress_port <= s3_ingress_port;
    //             s4_root_info <= s3_root_info;
    //             s4_metadata  <= s3_metadata;

    //             is_retrans <= |(arrival_state_bitmap_in & s3_port_mask);
    //             is_first_arrival <= !(|(arrival_state_bitmap_in & s3_port_mask));
    //             port_need_retrans <= |(arrival_state_bitmap_in  & s3_fin_mask);
    //             port_not_need_retrans <= !(|(arrival_state_bitmap_in & s3_fin_mask));

    //             // bitmap_new <= arrival_state_bitmap_in | s3_port_mask;

    //             s4_arrival_state_in <= arrival_state_bitmap_in;
    //             s4_degree_state_in <= degree_state_in;
    //             s4_bitmap_new <= arrival_state_bitmap_in | s3_port_mask;
    //             // s4_port_mask <= (s3_ingress_port <= FAN_IN) ? (32'h00000001 << s3_ingress_port) : {32{1'b0}};
    //             // s4_fin_mask <= 32'h00000001 << FAN_IN;  
    //         end
            
    //         else if (!s4_valid) begin
    //             s4_valid <= s3_valid;
    //             s4_idx_psn <= s3_idx_psn;
    //             s4_ingress_port <= s3_ingress_port;
    //             s4_root_info <= s3_root_info;
    //             s4_arrival_state_in <= arrival_state_bitmap_in;
    //             s4_degree_state_in <= degree_state_in;
    //             s4_metadata <= s3_metadata;

    //             is_retrans <= |(arrival_state_bitmap_in & s3_port_mask);
    //             is_first_arrival <= !(|(arrival_state_bitmap_in & s3_port_mask));
                
    //             port_need_retrans <= |(arrival_state_bitmap_in  & s3_fin_mask);
    //             port_not_need_retrans <= !(|(arrival_state_bitmap_in & s3_fin_mask));

    //             s4_bitmap_new <= arrival_state_bitmap_in | s3_port_mask;
    //             // s4_port_mask <= (s3_ingress_port <= FAN_IN) ? (32'h00000001 << s3_ingress_port) : {32{1'b0}};
    //             // s4_fin_mask <= 32'h00000001 << FAN_IN;  
    //         end

    //         else begin
    //             s4_valid <= 0;
    //             s4_idx_psn <= 0;
    //             s4_ingress_port <= 0;
    //             s4_root_info <= 0;
    //             s4_arrival_state_in <= 0;
    //             s4_degree_state_in <= 0;
    //             s4_bitmap_new <= 0;
    //             s4_port_mask <= 0;
    //             s4_fin_mask <= 0; 
    //             s4_metadata <= 0;
    //         end
                

    //         // if (!s4_valid) begin
    //         //     if (s3_valid && s4_can_accept) begin
    //         //         s4_valid <= 1;
    //         //         s4_idx_psn <= s3_idx_psn;
    //         //         s4_ingress_port <= s3_ingress_port;
    //         //         s4_root_info <= s3_root_info;
    //         //         s4_arrival_state_in <= arrival_state_bitmap_in;
    //         //         s4_degree_state_in <= degree_state_in;
    //         //         s4_bitmap_new <= arrival_state_bitmap_in | s3_port_mask;
    //         //         s4_port_mask <= (s3_ingress_port <= FAN_IN) ? (32'h00000001 << s3_ingress_port) : {32{1'b0}};
    //         //         s4_fin_mask <= 32'h00000001 << FAN_IN;
    //         //     end
    //         // end



    //         // else begin
    //         //     if (s4_valid && s5_can_accept) begin
    //         //         s4_valid <= 1'b0;
    //         //     end
    //         // end


    //     end
    // end

    // // S5的逻辑实现
    // always @(posedge clk or negedge rst_n) begin
    //     if(!rst_n) begin
    //         s5_idx_psn <= 0;
    //         s5_ingress_port <= 0;
    //         s5_root_info <= 0;
    //         s5_metadata <= 0;
    //         s5_valid <= 0;
    //         degree_state_wr_en  <= 0;
    //         arrival_state_wr_en <= 0;
    //         s5_to_buffer_for_aggregate_payload_en <= 0;
    //         s5_need_agggregator_for_port_retrans <= 0;
    //         s5_to_broadcast_for_FAN_retrans_check_en <= 0; 

    //     end

    //     else begin
    //         degree_state_wr_en <= 1'b0;
    //         arrival_state_wr_en <= 1'b0;
    //         s5_to_buffer_for_aggregate_payload_en <= 0;
    //         s5_need_agggregator_for_port_retrans <= 0;
    //         s5_to_broadcast_for_FAN_retrans_check_en <= 0; 
    //         // s5_valid <= 0;

    //         if (s6_can_accept) begin
    //             s5_valid <= s4_valid;
    //             s5_metadata <= s4_metadata;
    //             degree_state_wr_en <= s4_valid;
    //             degree_state_wr_addr <= s4_idx_psn;
    //             degree_state_wr_data <= s4_degree_state_in + 1;             
    //             if (is_first_arrival) begin
    //                 arrival_state_wr_en <= s4_valid;
    //                 arrival_state_wr_addr <= s4_idx_psn;
    //                 arrival_state_wr_data <= s4_bitmap_new;
    //             end             
    //             s5_to_buffer_for_aggregate_payload_en <= is_first_arrival;
    //             s5_need_agggregator_for_port_retrans <= (is_retrans && port_need_retrans);
    //             s5_to_broadcast_for_FAN_retrans_check_en <= is_retrans && port_not_need_retrans && !s4_root_info;
    //         end

    //         else if (!s5_valid) begin
    //             s5_valid <= s4_valid;
    //             s5_metadata <= s4_metadata;
    //             degree_state_wr_en <= 1'b1;
    //             degree_state_wr_addr <= s4_idx_psn;
    //             degree_state_wr_data <= s4_degree_state_in + 1;             
    //             if (is_first_arrival) begin
    //                 arrival_state_wr_en <= 1'b1;
    //                 arrival_state_wr_addr <= s4_idx_psn;
    //                 arrival_state_wr_data <= s4_bitmap_new;
    //             end             
    //             s5_to_buffer_for_aggregate_payload_en <= is_first_arrival;
    //             s5_need_agggregator_for_port_retrans <= (is_retrans && port_need_retrans);
    //             s5_to_broadcast_for_FAN_retrans_check_en <= is_retrans && port_not_need_retrans && !s4_root_info;
    //         end

    //         else begin
    //             s5_valid <= 0;
    //             s5_metadata <= 0;
    //             degree_state_wr_en <= 0;
    //             degree_state_wr_addr <= 0;
    //             degree_state_wr_data <= 0; 
    //             arrival_state_wr_en <= 0;
    //             arrival_state_wr_addr <= 0;
    //             arrival_state_wr_data <= 0;                          
    //             s5_to_buffer_for_aggregate_payload_en <= 0;
    //             s5_need_agggregator_for_port_retrans <= 0;
    //             s5_to_broadcast_for_FAN_retrans_check_en <= 0; 
    //         end

    //         // if (!s5_valid) begin
    //         //     if (s4_valid && s5_can_accept) begin
    //         //         s5_valid <= 1'b1;
    //         //         degree_state_wr_en <= 1'b1;
    //         //         degree_state_wr_addr <= s4_idx_psn;
    //         //         degree_state_wr_data <= s4_degree_state_in + 1;

    //         //         if (is_first_arrival) begin
    //         //             arrival_state_wr_en <= 1'b1;
    //         //             arrival_state_wr_addr <= s4_idx_psn;
    //         //             arrival_state_wr_data <= bitmap_new;
    //         //         end

    //         //         s5_aggregate_buffer_en <= is_first_arrival;
    //         //         s5_read_buffer_en <= (is_retrans && fan_in_arrival);
    //         //         s5_FAN_retrans_check_en <= (!(is_retrans && fan_in_arrival)) & (!s4_root_info);
    //         //     end 
    //         // end

    //         // else begin
    //         //     if (s5_valid && s6_can_accept) begin
    //         //         s5_valid <= 1'b0;
    //         //     end
    //         // end


    //     end 
                
    // end

    // always @(posedge clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         s6_valid <= 0;
    //         // out_valid <= 0;
    //         // aggregate_buffer_en <= 0;
    //         // read_buffer_en <= 0;
    //         // FAN_retrans_check_en <= 0;
    //         s6_to_buffer_for_aggregate_payload_en <= 0;
    //         s6_need_agggregator_for_port_retrans <= 0;
    //         s6_to_broadcast_for_FAN_retrans_check_en <= 0; 
    //     end

    //     else begin
    //         // s6_valid <= 0;
    //         // if (!s6_valid) begin
    //         //     if (s5_valid && s6_can_accept) begin
    //         //         s6_valid <= 1'b1;
                
    //         //         out_valid <= 1'b1;
    //         //         s6_aggregate_buffer_en <= s5_aggregate_buffer_en;
    //         //         s6_read_buffer_en <= s5_read_buffer_en;
    //         //         s6_FAN_retrans_check_en <= s5_FAN_retrans_check_en;     
             
    //         //     end 
    //         // end

    //         // else begin
    //         //     if (s6_valid && s7_can_accept && degree_state_wr_grant) begin
    //         //         s6_valid <= 1'b0;
    //         //         out_valid <= 1'b0;
    //         //     end 
    //         // end

    //         if (s7_can_accept) begin
    //             s6_valid <= s5_valid;
    //             // out_valid <= s5_valid;
    //             s6_metadata <= s5_metadata;
    //             s6_to_buffer_for_aggregate_payload_en <= s5_to_buffer_for_aggregate_payload_en;
    //             s6_need_agggregator_for_port_retrans <= s5_need_agggregator_for_port_retrans;
    //             s6_to_broadcast_for_FAN_retrans_check_en <= s5_to_broadcast_for_FAN_retrans_check_en;   
    //         end

    //         else if (!s6_valid) begin
    //             s6_valid <= s5_valid;
    //             // out_valid <= s5_valid;
    //             s6_metadata <= s5_metadata;
    //             s6_to_buffer_for_aggregate_payload_en <= s5_to_buffer_for_aggregate_payload_en;
    //             s6_need_agggregator_for_port_retrans <= s5_need_agggregator_for_port_retrans;
    //             s6_to_broadcast_for_FAN_retrans_check_en <= s5_to_broadcast_for_FAN_retrans_check_en; 
    //         end

    //         else begin
    //             s6_valid <= 0;
    //             // out_valid <= s5_valid;
    //             s6_metadata <= 0;
    //             s6_to_buffer_for_aggregate_payload_en <= 0;
    //             s6_need_agggregator_for_port_retrans <= 0;
    //             s6_to_broadcast_for_FAN_retrans_check_en <= 0;  
    //         end

    //     end
            
    // end

    // always @(posedge clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         s7_valid <= 0;
    //         s7_to_buffer_for_aggregate_payload_en <= 0;
    //         s7_need_agggregator_for_port_retrans <= 0;
    //         s7_to_broadcast_for_FAN_retrans_check_en <= 0; 
    //     end

    //     else begin
    //         s7_to_buffer_for_aggregate_payload_en <= 0;
    //         s7_need_agggregator_for_port_retrans <= 0;
    //         s7_to_broadcast_for_FAN_retrans_check_en <= 0; 
    //         // s7_valid <= 0;

    //         if (out_ready) begin
    //             if (degree_state_wr_grant) begin
    //                 s7_valid <= s6_valid;
    //                 s7_metadata <= s6_metadata;
    //                 s7_to_buffer_for_aggregate_payload_en <= s6_to_buffer_for_aggregate_payload_en;
    //                 s7_need_agggregator_for_port_retrans <= s6_need_agggregator_for_port_retrans;
    //                 s7_to_broadcast_for_FAN_retrans_check_en <= s6_to_broadcast_for_FAN_retrans_check_en; 
    //             end

    //             else begin
    //                 s7_valid <= 0;
    //                 s7_metadata <= 0;
    //                 s7_to_buffer_for_aggregate_payload_en <= 0;
    //                 s7_need_agggregator_for_port_retrans <= 0;
    //                 s7_to_broadcast_for_FAN_retrans_check_en <= 0; 
    //             end
    //         end 

    //         else begin
    //             if (!s7_valid) begin
    //                 s7_valid <= s6_valid;
    //                 s7_metadata <= s6_metadata;
    //                 s7_to_buffer_for_aggregate_payload_en <= s6_to_buffer_for_aggregate_payload_en;
    //                 s7_need_agggregator_for_port_retrans <= s6_need_agggregator_for_port_retrans;
    //                 s7_to_broadcast_for_FAN_retrans_check_en <= s6_to_broadcast_for_FAN_retrans_check_en;      
    //             end
    //         end

           
    //         // if (!s7_valid) begin
    //         //     if (s6_valid && s7_can_accept && degree_state_wr_grant) begin
    //         //         s7_valid <= 1'b1;
    //         //         if (degree_state_wr_grant) begin
    //         //             out_valid <= 1'b1;
    //         //             aggregate_buffer_en <= s6_aggregate_buffer_en;
    //         //             read_buffer_en <= s6_read_buffer_en;
    //         //             FAN_retrans_check_en <= s6_FAN_retrans_check_en;     
    //         //         end
                
    //         //     end
    //         // end

    //         // else begin
    //         //     if (s7_valid && out_ready) begin
    //         //         s7_valid <= 1'b0;
    //         //         out_valid <= 1'b0;
    //         //     end
    //         // end

    //     end
            
    // end

    // assign to_buffer_metadata_out = s7_metadata;
    // assign to_up_broadcast_metadata_out = s7_metadata;
    
    // assign to_buffer_valid = s7_valid && task_for_buffer;
    // assign to_up_broadcast_valid = s7_valid && task_for_up_broadcast;

    // assign to_buffer_for_aggregate_payload_en = s7_valid ? s7_to_buffer_for_aggregate_payload_en : 0;
    // assign to_buffer_need_agggregator_for_port_retrans = s7_valid ? s7_need_agggregator_for_port_retrans : 0;
    // assign to_broadcast_for_FAN_retrans_check_en = s7_valid ? s7_to_broadcast_for_FAN_retrans_check_en : 0; 
 
endmodule
