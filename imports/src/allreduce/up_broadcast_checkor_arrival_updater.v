`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/16 14:34:17
// Design Name: 
// Module Name: broadcast_checkor_arrival_updater
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


`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/16 14:34:17
// Design Name: 
// Module Name: broadcast_checkor_arrival_updater
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


module up_broadcast_checkor_arrival_updater #(
    parameter FAN_IN                = 2,
    parameter BUFFER_SLOTS          = 16,
    parameter BUFFER_SLOTS_WIDTH    = $clog2(BUFFER_SLOTS),
    parameter FAN_IN_WIDTH          = $clog2(FAN_IN),
    parameter DATA_WIDTH            = 32,
    parameter ADDR_WIDTH            = 8,
    parameter PAYLOAD_ITEM_WIDTH    = 512,
    parameter PAYLOAD_ITEM_NUM      = 16,
    parameter METADATA_LEN = 2*8+3+5,
    parameter RAM_SLOT_WIDTH = 10

)(
    input wire                      clk,
    input wire                      rst_n,

    input wire [3*8-1:0]            in_metadata,

    // input wire                      controller_out_valid,
    input wire                      buffer_to_up_broadcast_check_en,
    input wire                      FAN_retrans_check_en,
    
    // bitmap_rd
    input wire [DATA_WIDTH-1:0]     arrival_state_bitmap_in,
    output reg [ADDR_WIDTH-1:0]     arrival_state_rd_addr,
    input wire                      arrival_state_rd_grant,
    output reg                      arrival_state_rd_en,

    // bitmap_wr
    output reg [ADDR_WIDTH-1:0]     arrival_state_wr_addr,
    output reg                      arrival_state_wr_en,
    output reg [DATA_WIDTH-1:0]     arrival_state_wr_data,
    input wire                      arrival_state_wr_grant,

    // degree_rd
    input wire [DATA_WIDTH-1:0]     degree_state_in,
    output reg [ADDR_WIDTH-1:0]     degree_state_rd_addr,
    input wire                      degree_state_rd_grant,
    output reg                      degree_state_rd_en,

    // aggregate_bram_rd
    input wire                                                      aggregate_bram_rd_grant,
    input wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]            aggregate_bram_rd_vector_pack,
    output reg [ADDR_WIDTH-1:0]                                     aggregate_bram_rd_addr,
    output reg [PAYLOAD_ITEM_NUM-1:0]                               aggregate_bram_rd_en_pack,


    // out
    output wire                     to_new_sloter_valid,
    input  wire                     to_new_sloter_ready,
    output wire                     new_slot_en,
    output wire [METADATA_LEN-1:0]  to_new_sloter_metadata_out, 
    
    output wire                     to_deparser_valid,
    input  wire                     to_deparser_ready,                 
    output wire                     need_aggregator_FAN_retrans_en,
    output wire                     need_aggregator_down_broadcast_en,
    output wire                     need_aggregator_FAN_trans_en,
    output wire [METADATA_LEN-1:0]  to_deparser_metadata_out,

    output wire [PAYLOAD_ITEM_NUM*PAYLOAD_ITEM_WIDTH-1:0]           aggregate_bram_rd_vector_pack_out,

    output wire                     in_ready,

    // arrival_State forwarding -> 预测优化
    output wire                     forwarding_valid,
    output wire [ADDR_WIDTH-1:0]    forwarding_addr,
    output wire [DATA_WIDTH-1:0]    forwarding_data,

    input wire                      last_forwarding_valid,
    input wire [ADDR_WIDTH-1:0]     last_forwarding_addr,
    input wire [DATA_WIDTH-1:0]     last_forwarding_data,

    input wire                      real_FAN_retrans_check_en

);
    // reg [7:0]                   s1_idx_psn;
    // reg [7:0]                   s1_ingress_port;
    // reg                         s1_root_info;

    // reg [7:0]                   s2_idx_psn;
    // reg [7:0]                   s2_ingress_port;
    // reg                         s2_root_info;

    // reg [DATA_WIDTH-1:0]        s2_port_mask;
    // reg [DATA_WIDTH-1:0]        s2_all_fin_mask;

    // wire need_broadcast = ((arrival_state_bitmap_in & s2_all_fin_mask) == s2_all_fin_mask);
    // wire is_receve_all_node = (degree_state_in[FAN_IN_WIDTH-1:0] == 0);
    // wire [DATA_WIDTH-1:0] bitmap_new = arrival_state_bitmap_in | s2_port_mask;

    // localparam IDLE                     = 2'd0;
    // localparam READ                     = 2'd1;
    // localparam COMPUTE_UPDT             = 2'd2;
    // localparam OUT                      = 2'd3;

    // reg [1:0]   current_state, next_state;

    // assign in_ready = (current_state == IDLE);

    // always @(*) begin

    //     next_state = current_state;

    //     case (current_state)
    //         IDLE: begin
    //             if (controller_out_valid) begin
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
    // end

    // always @(posedge clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         current_state <= IDLE;
    //         s1_idx_psn <= 0;
    //         s1_ingress_port <= 0;
    //         s1_root_info <= 0;
    //         arrival_state_rd_addr <= 0;
    //         degree_state_rd_addr <= 0;
    //         s2_idx_psn <= 0;
    //         s2_ingress_port <= 0;
    //         s2_root_info <= 0;
    //         s2_all_fin_mask <= 0;
    //         s2_port_mask <= 0;
    //         out_valid <= 0;
    //         arrival_state_wr_en <= 0;
    //         arrival_state_wr_addr <= 0;
    //         arrival_state_wr_data <= 0;
    //         down_broadcast_en <= 0;
    //         new_slot_en <= 0;
    //         FAN_retrans_en <= 0;
    //         FAN_trans_en <= 0;

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
    //                 s2_all_fin_mask <= 32'hFFFFFFFF >> (32 - FAN_IN);
    //                 s2_port_mask <= 32'h00000001 << FAN_IN;
    //             end

    //             COMPUTE_UPDT: begin
    //                 out_valid <= 1'b1;
    //                 if (need_broadcast && s2_root_info) begin
    //                     arrival_state_wr_en <= 1'b1;
    //                     arrival_state_wr_addr <= s2_idx_psn;
    //                     arrival_state_wr_data <= bitmap_new;
    //                     down_broadcast_en <= 1'b1;
    //                     new_slot_en <= 1'b1;
    //                 end

    //                 if (need_broadcast && !s2_root_info) begin
    //                     FAN_trans_en <= 1'b1;
    //                 end
                    
    //                 if (!s2_root_info && FAN_retrans_check_en && is_receve_all_node) begin
    //                     FAN_retrans_en <= 1'b1;
    //                 end
    //             end

    //             OUT: begin
    //                 out_valid <= 1'b0;
    //                 down_broadcast_en <= 1'b0;
    //                 new_slot_en <= 1'b0;
    //                 FAN_trans_en <= 1'b0;
    //                 FAN_retrans_en <= 1'b0;
    //                 s1_idx_psn <= 0;
    //                 s1_ingress_port <= 0;
    //                 s1_root_info <= 0;
    //                 arrival_state_rd_addr <= 0;
    //                 degree_state_rd_addr <= 0;
    //                 arrival_state_wr_en <= 1'b0;
    //                 arrival_state_wr_data <= 0;
    //             end

    //         endcase
    //     end
            
    // end


// 流水线写法

    // S1, 解析in_metadata, 发起rd读
    reg [7:0]               s1_idx_psn;
    reg [7:0]               s1_ingress_port;
    reg                     s1_root_info;
    reg [METADATA_LEN-1:0]  s1_metadata;
    reg                     s1_valid;
    reg                     s1_FAN_retrans_check_en;
    reg                     s1_real_FAN_retrans_check_en;

    // S2，读延迟(arbiter)
    reg [7:0]               s2_idx_psn;
    reg [7:0]               s2_ingress_port;
    reg                     s2_root_info;
    reg [METADATA_LEN-1:0]  s2_metadata;
    reg                     s2_valid;
    reg                     s2_FAN_retrans_check_en;
    reg                     s2_real_FAN_retrans_check_en;

    // S3, 读延迟(BRAM)
    reg [7:0]               s3_idx_psn;
    reg [7:0]               s3_ingress_port;
    reg                     s3_root_info;
    reg [METADATA_LEN-1:0]  s3_metadata;
    reg                     s3_valid;
    reg [DATA_WIDTH-1:0]    s3_arrival_state_in;
    reg [DATA_WIDTH-1:0]    s3_port_mask;
    reg [DATA_WIDTH-1:0]    s3_all_fin_mask;
    reg                     s3_FAN_retrans_check_en;

    
    // S4, 收回rd读后的数据，进行判断后计算
    reg [7:0]               s4_idx_psn;
    reg [7:0]               s4_ingress_port;
    reg                     s4_root_info;
    reg [METADATA_LEN-1:0]  s4_metadata;
    reg                     s4_valid;
    reg                     s4_FAN_retrans_check_en;

    reg [DATA_WIDTH-1:0]    s4_port_mask;
    reg [DATA_WIDTH-1:0]    s4_all_fin_mask;

    reg [DATA_WIDTH-1:0]    s4_bitmap_new;
    reg [DATA_WIDTH-1:0]    s4_arrival_state_in;   
    reg [DATA_WIDTH-1:0]    s4_degree_state_in;
    
    // 中间变量
    reg                     s4_need_broadcast;
    reg                     s4_is_receve_all_node;


    // S5, 发出计算后的数据写wr请求
    reg [METADATA_LEN-1:0]  s5_metadata;
    reg                     s5_valid;
    reg [7:0]               s5_idx_psn;
    reg [7:0]               s5_ingress_port;
    // reg                     s5_root_info;

    reg                     s5_FAN_retrans_en;
    reg                     s5_down_broadcast_en;
    reg                     s5_new_slot_en;
    reg                     s5_FAN_trans_en;
       
    // S6 等待wr返回
    reg                     s6_valid;
    reg [METADATA_LEN-1:0]  s6_metadata;
    reg                     s6_FAN_retrans_en;
    reg                     s6_down_broadcast_en;
    reg                     s6_new_slot_en;
    reg                     s6_FAN_trans_en;

    // S7 wr写成功
    reg                     s7_valid;
    reg [METADATA_LEN-1:0]  s7_metadata;
    reg                     s7_FAN_retrans_en;
    reg                     s7_down_broadcast_en;
    reg                     s7_new_slot_en;
    reg                     s7_FAN_trans_en;

    // 反压信号
    wire s1_can_accept;
    wire s2_can_accept;
    wire s3_can_accept;
    wire s4_can_accept;
    wire s5_can_accept;
    wire s6_can_accept;
    wire s7_can_accept; 

    wire task_for_sloter = s7_new_slot_en;
    wire task_for_deparser = s7_down_broadcast_en || s7_FAN_retrans_en || s7_FAN_trans_en;

    wire sloter_done = !to_new_sloter_valid || (to_new_sloter_valid && to_new_sloter_ready);
    wire deparser_done = !to_deparser_valid || (to_deparser_valid && to_deparser_ready);

    wire out_ready = sloter_done && deparser_done;

    // wire control_valid = FAN_retrans_check_en || buffer_to_up_broadcast_check_en;
    wire control_valid = real_FAN_retrans_check_en || buffer_to_up_broadcast_check_en;

    assign s7_can_accept = !s7_valid || (s7_valid && out_ready);
    assign s6_can_accept = !s6_valid || (s6_valid && s7_can_accept);
    assign s5_can_accept = !s5_valid || (s5_valid && s6_can_accept);
    assign s4_can_accept = !s4_valid || (s4_valid && s5_can_accept);
    assign s3_can_accept = !s3_valid || (s3_valid && s4_can_accept);
    assign s2_can_accept = !s2_valid || (s2_valid && s3_can_accept);
    assign s1_can_accept = !s1_valid || (s1_valid && s2_can_accept);

    assign in_ready = s1_can_accept;

    // S1
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_idx_psn <= 0;
            s1_ingress_port <= 0;
            s1_root_info <= 0;
            s1_metadata <= 0;
            s1_valid <= 0;

            arrival_state_rd_en <= 0;
            arrival_state_rd_addr <= 0;
            degree_state_rd_en <= 0;
            degree_state_rd_addr <= 0;
            s1_FAN_retrans_check_en <= 0;
            s1_real_FAN_retrans_check_en <= 0;
        end

        else begin
            arrival_state_rd_en <= 0;
            degree_state_rd_en <= 0;
            if (s2_can_accept || !s1_valid) begin
                s1_valid        <= control_valid; 
                s1_metadata     <= in_metadata;
                s1_idx_psn      <= in_metadata[15:8];
                s1_ingress_port <= in_metadata[7:0];
                s1_root_info    <= in_metadata[8 + RAM_SLOT_WIDTH];
                s1_FAN_retrans_check_en <= FAN_retrans_check_en;
                s1_real_FAN_retrans_check_en <= real_FAN_retrans_check_en;
                if (control_valid) begin
                    arrival_state_rd_en   <= 1'b1;
                    arrival_state_rd_addr <= in_metadata[15:8];
                    degree_state_rd_en    <= 1'b1;
                    degree_state_rd_addr  <= in_metadata[15:8];
                end
            end
            else begin
                s1_valid <= 0;
                degree_state_rd_en <= 0;
                arrival_state_rd_en <= 0;
                s1_idx_psn <= 0;
                s1_ingress_port <= 0;
                s1_root_info <= 0;
                s1_metadata <= 0;
            end 

        end
    end

    // S2
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_idx_psn <= 0;
            s2_metadata <= 0;
            s2_ingress_port <= 0;
            s2_root_info <= 0;
            s2_valid <= 0;
        end
        else begin
            if (s3_can_accept || !s2_valid) begin
                s2_valid <= s1_valid;
                s2_metadata <= s1_metadata;
                s2_idx_psn <= s1_idx_psn;
                s2_ingress_port <= s1_ingress_port;
                s2_root_info <= s1_root_info;
                if (last_forwarding_valid && last_forwarding_data[FAN_IN] && last_forwarding_addr == s1_idx_psn) begin
                    s2_FAN_retrans_check_en <= s1_FAN_retrans_check_en;
                end
                else if (last_forwarding_valid == 0 && last_forwarding_data == 0 && last_forwarding_addr == 0) begin
                    // s2_FAN_retrans_check_en <= s1_FAN_retrans_check_en;
                    s2_FAN_retrans_check_en <= s1_real_FAN_retrans_check_en;
                end 
                else begin
                    s2_FAN_retrans_check_en <= 0;
                end
                // s2_FAN_retrans_check_en <= s1_FAN_retrans_check_en;
            end
            else begin
                s2_valid <= 0;
                s2_idx_psn <= 0;
                s2_metadata <= 0;
                s2_ingress_port <= 0;
                s2_root_info <= 0;
            end
        end
    end

    // S3
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_idx_psn <= 0;
            s3_ingress_port <= 0;
            s3_root_info <= 0;
            s3_metadata <= 0;
            s3_valid <= 0;
            s3_port_mask <= 0;
            s3_all_fin_mask <=0;
        end
        else begin
            if ((s4_can_accept || !s3_valid) && arrival_state_rd_grant && degree_state_rd_grant) begin
                s3_valid <= s2_valid;
                s3_idx_psn <= s2_idx_psn;
                s3_ingress_port <= s2_ingress_port;
                s3_metadata <= s2_metadata;
                s3_root_info <= s2_root_info;
                s3_FAN_retrans_check_en <= s2_FAN_retrans_check_en;
                // s3_port_mask <= 32'h00000001 << FAN_IN;
                // s3_all_fin_mask <= 32'hFFFFFFFF >> (32 - FAN_IN);
                s3_port_mask <= 64'h0000000000000001 << FAN_IN;
                s3_all_fin_mask <= 64'hFFFFFFFFFFFFFFFF >> (64 - FAN_IN);

            end
            else begin
                s3_valid <= 0;
                s3_metadata <= 0;
                s3_idx_psn <= 0;
                s3_ingress_port <= 0;
                s3_root_info <= 0;
                s3_port_mask <= 0;
                s3_all_fin_mask <= 0;
                s3_FAN_retrans_check_en <= 0;
            end
        end
    end

    // S4
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s4_idx_psn <= 0;
            s4_ingress_port <= 0;
            s4_root_info <= 0;
            s4_metadata <= 0;
            s4_valid <= 0;
            s4_all_fin_mask <= 0;
            s4_port_mask <= 0;

            s4_arrival_state_in <= 0;

        end

        else begin

            if (s5_can_accept || !s4_valid) begin
                s4_valid <= s3_valid;
                s4_metadata <= s3_metadata;
                s4_idx_psn <= s3_idx_psn;
                s4_ingress_port <= s3_ingress_port;
                s4_root_info <= s3_root_info;
                s4_arrival_state_in <= arrival_state_bitmap_in;
                s4_degree_state_in <= degree_state_in;
                s4_FAN_retrans_check_en <= s3_FAN_retrans_check_en;

                s4_is_receve_all_node <= (degree_state_in[FAN_IN_WIDTH-1:0] == 0);
                s4_need_broadcast <= ((arrival_state_bitmap_in & s3_all_fin_mask) == s3_all_fin_mask);
                s4_bitmap_new <= arrival_state_bitmap_in | s3_port_mask;
            end
            else begin
                s4_valid <= 0;
                s4_metadata <= 0;
                s4_idx_psn <= 0;
                s4_ingress_port <= 0;
                s4_root_info <= 0;
                s4_arrival_state_in <= 0;
                s4_degree_state_in <= 0;
                s4_FAN_retrans_check_en <= 0;

                s4_is_receve_all_node <= 0;
                s4_need_broadcast <= 0;
                s4_bitmap_new <= 0;
            end
                
        end  
    end

    // forwarding logic 
    assign forwarding_valid = s4_valid && !s4_FAN_retrans_check_en && s4_need_broadcast && s4_root_info;
    assign forwarding_addr = s4_idx_psn;
    assign forwarding_data = s4_bitmap_new;

    // S5   
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s5_idx_psn <= 0;
            s5_ingress_port <= 0;
            // s5_root_info <= 0;
            s5_valid <= 0;
            s5_metadata <= 0;

            s5_FAN_retrans_en <= 0;
            s5_down_broadcast_en <= 0;
            s5_new_slot_en <= 0;
            s5_FAN_trans_en <= 0;
            arrival_state_wr_en <= 0;

            aggregate_bram_rd_addr <= 0;
            aggregate_bram_rd_en_pack <= 0;

        end

        else begin
            s5_FAN_retrans_en <= 0;
            s5_down_broadcast_en <= 0;
            s5_new_slot_en <= 0;
            s5_FAN_trans_en <= 0;
            s5_metadata <= 0;
            arrival_state_wr_en <= 0;
            arrival_state_wr_data <= 0;
            arrival_state_wr_addr <= 0;

            aggregate_bram_rd_addr <= 0;
            aggregate_bram_rd_en_pack <= 0;

            if (s6_can_accept || !s5_valid) begin
                s5_metadata <= s4_metadata;
                s5_valid <= s4_valid;
                if (!s4_FAN_retrans_check_en && s4_need_broadcast && s4_root_info) begin
                    arrival_state_wr_en <= s4_valid;
                    arrival_state_wr_addr <= s4_idx_psn;
                    arrival_state_wr_data <= s4_bitmap_new;

                    aggregate_bram_rd_addr <= s4_idx_psn;
                    aggregate_bram_rd_en_pack <= {16{s4_valid}};
                    s5_down_broadcast_en <= s4_valid;
                    s5_new_slot_en <= s4_valid;
                end

                else if (s4_FAN_retrans_check_en && s4_is_receve_all_node && !s4_root_info && s4_need_broadcast) begin
                    s5_FAN_retrans_en <= s4_valid;
                    aggregate_bram_rd_addr <= s4_idx_psn;
                    aggregate_bram_rd_en_pack <= {16{s4_valid}};
                end

                else if (!s4_FAN_retrans_check_en && s4_need_broadcast && !s4_root_info) begin
                    s5_FAN_trans_en <= s4_valid;
                    aggregate_bram_rd_addr <= s4_idx_psn;
                    aggregate_bram_rd_en_pack <= {16{s4_valid}};
                end

            end
            else begin
                s5_valid <= 0;
                s5_FAN_retrans_en <= 0;
                s5_down_broadcast_en <= 0;
                s5_new_slot_en <= 0;
                s5_FAN_trans_en <= 0;
                s5_metadata <= 0;
                arrival_state_wr_en <= 0;
                arrival_state_wr_data <= 0;
                arrival_state_wr_addr <= 0;

                aggregate_bram_rd_addr <= 0;
                aggregate_bram_rd_en_pack <= 0;
            end
        end
    end

    // S6 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s6_valid <= 0;
            s6_metadata <= 0;
            s6_FAN_retrans_en <= 0;
            s6_down_broadcast_en <= 0;
            s6_new_slot_en <= 0;
            s6_FAN_trans_en <= 0;
        end

        else begin
            if (s7_can_accept || !s6_valid) begin
                s6_valid <= s5_valid;
                s6_metadata <= s5_metadata;
                s6_FAN_retrans_en <= s5_FAN_retrans_en;
                s6_down_broadcast_en <= s5_down_broadcast_en;
                s6_new_slot_en <= s5_new_slot_en;
                s6_FAN_trans_en <= s5_FAN_trans_en;
            end
            else begin
                s6_valid <= 0;
                s6_metadata <= 0;
                s6_FAN_retrans_en <= 0;
                s6_down_broadcast_en <= 0;
                s6_new_slot_en <= 0;
                s6_FAN_trans_en <= 0;
            end
        end
    end

    // S7
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s7_valid <= 0;
            s7_metadata <=0 ;
            s7_FAN_retrans_en <= 0;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         
            s7_down_broadcast_en <= 0;
            s7_new_slot_en <= 0;
            s7_FAN_trans_en <= 0;
        end

        else begin
            // if ((out_ready || !s7_valid) && (s6_down_broadcast_en ? arrival_state_wr_grant : 1'b1) && 
            //     (s6_down_broadcast_en ? aggregate_bram_rd_grant : s6_FAN_retrans_en ? aggregate_bram_rd_grant : s6_FAN_trans_en ?
            //         aggregate_bram_rd_grant : 1'b1) ) begin
            //     s7_valid <= s6_valid;
            //     s7_metadata <= s6_metadata;
            //     s7_FAN_retrans_en <= s6_FAN_retrans_en;
            //     s7_down_broadcast_en <= s6_down_broadcast_en;
            //     s7_new_slot_en <= s6_new_slot_en;
            //     s7_FAN_trans_en <= s6_FAN_trans_en;
            // end
            // else begin
            //     s7_valid <= 0;
            //     s7_metadata <= 0;
            //     s7_FAN_retrans_en <= 0;
            //     s7_down_broadcast_en <= 0;
            //     s7_new_slot_en <= 0;
            //     s7_FAN_trans_en <= 0;
            // end
            
            // 1. 只有当 (下游 Ready) 或者 (S7 当前为空/气泡) 时，才允许流水线流动
            if (out_ready || !s7_valid) begin
                
                // 2. 在允许流动的前提下，检查 S6 是否有数据以及 Grant 是否到达
                if (s6_valid && 
                    (s6_down_broadcast_en ? arrival_state_wr_grant : 1'b1) && 
                    (s6_down_broadcast_en ? aggregate_bram_rd_grant : s6_FAN_retrans_en ? aggregate_bram_rd_grant : s6_FAN_trans_en ? aggregate_bram_rd_grant : 1'b1)) 
                begin
                    // Grant 满足，加载 S6 数据进入 S7
                    s7_valid <= s6_valid;
                    s7_metadata <= s6_metadata;
                    s7_FAN_retrans_en <= s6_FAN_retrans_en;
                    s7_down_broadcast_en <= s6_down_broadcast_en;
                    s7_new_slot_en <= s6_new_slot_en;
                    s7_FAN_trans_en <= s6_FAN_trans_en;
                end
                else begin
                    // S6 无数据，或者 Grant 未满足（此时视为操作失败或无操作）
                    // 插入气泡
                    s7_valid <= 0;
                    s7_metadata <= 0;
                    s7_FAN_retrans_en <= 0;
                    s7_down_broadcast_en <= 0;
                    s7_new_slot_en <= 0;
                    s7_FAN_trans_en <= 0;
                end
            end
        end
    end


    assign to_new_sloter_valid = s7_valid && task_for_sloter;
    assign to_deparser_valid = s7_valid && task_for_deparser;

    assign to_new_sloter_metadata_out = to_new_sloter_valid ? s7_metadata : 0;
    assign to_deparser_metadata_out = to_deparser_valid ? s7_metadata : 0;

    assign need_aggregator_FAN_retrans_en = s7_FAN_retrans_en;
    assign need_aggregator_down_broadcast_en = s7_down_broadcast_en;
    assign new_slot_en = s7_new_slot_en;
    assign need_aggregator_FAN_trans_en = s7_FAN_trans_en;
    assign aggregate_bram_rd_vector_pack_out = aggregate_bram_rd_vector_pack;


endmodule
