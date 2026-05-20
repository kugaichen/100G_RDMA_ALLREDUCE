`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/22 10:51:18
// Design Name: 
// Module Name: down_broadcast_checkor_arrival_updater
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


module down_broadcast_checkor_arrival_updater #(
    parameter PAYLOAD_ITEM_NUM      = 16,
    parameter PAYLOAD_ITEM_WIDTH    = 512,
    parameter METADATA_LEN          = 2*8+3+5,
    parameter FAN_IN                = 2,
    parameter BUFFER_SLOTS          = 16,
    parameter BUFFER_SLOTS_WIDTH    = $clog2(BUFFER_SLOTS),
    parameter FAN_IN_WIDTH          = $clog2(FAN_IN),
    parameter DATA_WIDTH            = 32,
    parameter ADDR_WIDTH            = 8
)(
    input   wire                    clk,
    input   wire                    rst_n,

    input   wire                    in_valid,
    input   wire [3*8-1:0]          in_metadata,
    
    // bitmap_rd
    output  reg                     arrival_state_rd_en, 
    output  reg  [ADDR_WIDTH-1:0]   arrival_state_rd_addr,
    input   wire [DATA_WIDTH-1:0]   arrival_state_bitmap_in,
    input   wire                    arrival_state_rd_grant,

    // bitmap_wr
    output  reg  [ADDR_WIDTH-1:0]   arrival_state_wr_addr,
    output  reg                     arrival_state_wr_en,
    output  reg  [DATA_WIDTH-1:0]   arrival_state_wr_data,
    input  wire                     arrival_state_wr_grant,
    
    // output
        // output_to_buffer_controller
    output  wire                    to_buffer_valid,
    input   wire                    to_buffer_ready,
    output  wire                    copy_buffer_en,
    output  wire [METADATA_LEN-1:0] to_buffer_metadata_out,

    // output  wire                    to_deparser_valid,
    // output  wire                    to_deparser_ready,  
    // output  wire                    down_broadcast_en,
    // output  wire [METADATA_LEN-1:0] to_deparser_metadata_out,

    output  wire                    in_ready

);
    // reg [7:0]                   s1_idx_psn;
    // reg [7:0]                   s1_ingress_port;
    // reg                         s1_root_info;

    // reg [7:0]                   s2_idx_psn;
    // reg [7:0]                   s2_ingress_port;
    // reg                         s2_root_info;

    // reg [DATA_WIDTH-1:0]        s2_port_mask;
    // reg [DATA_WIDTH-1:0]        s2_all_fin_mask;    



    // wire FAN_has_trans = |(arrival_state_bitmap_in & s2_port_mask);
    // wire need_broadcast = ((arrival_state_bitmap_in & s2_all_fin_mask) == s2_all_fin_mask);
    // wire FAN_first_trans = !FAN_has_trans;
    // wire [DATA_WIDTH-1:0] bitmap_new = arrival_state_bitmap_in | s2_port_mask;


    // localparam IDLE           = 2'd0;
    // localparam READ           = 2'd1;
    // localparam COMPUTE_UPDT   = 2'd2;
    // localparam OUT            = 2'd3;

    // reg [1:0]   current_state, next_state;

    // assign in_ready = (current_state == IDLE);

    // always @(*) begin
   
    //   next_state = current_state;
   
    //   case (current_state)
    //       IDLE: begin
    //           if (in_valid) begin
    //               next_state = READ;
    //           end
    //       end        
       
    //       READ: begin
    //           next_state = COMPUTE_UPDT;
    //       end
       
    //       COMPUTE_UPDT: begin
    //           next_state = OUT;
    //       end
       
    //       OUT: begin
    //           if (out_ready) begin
    //               next_state = IDLE;
    //           end
    //       end
       
    //       default: begin
    //           next_state = IDLE;
    //       end
              
    //   endcase
    // end
    
    // always @(posedge clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         s1_idx_psn <= 0;
    //         s1_ingress_port <= 0;
    //         s1_root_info <= 0;
    //         arrival_state_rd_addr <= 0;
    //         s2_idx_psn <= 0;
    //         s2_ingress_port <= 0;
    //         s2_root_info <= 0;
    //         s2_all_fin_mask <= 0;
    //         s2_port_mask <= 0;
    //         arrival_state_wr_en <= 0;
    //         arrival_state_wr_addr <= 0;
    //         arrival_state_wr_data <= 0;
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
    //                 if (FAN_first_trans && need_broadcast) begin
    //                     copy_buffer_en <= 1'b1;
    //                     down_broadcast_en <= 1'b1;
    //                     arrival_state_wr_en <= 1'b1;
    //                     arrival_state_wr_addr <= s2_idx_psn;
    //                     arrival_state_wr_data <= bitmap_new;
    //                 end

    //             end

    //             OUT: begin
    //                 out_valid <= 1'b0;
    //                 arrival_state_wr_en <= 0;
    //                 copy_buffer_en <= 0;
    //                 down_broadcast_en <= 0;
    //                 s1_idx_psn <= 0;
    //                 s1_ingress_port <= 0;
    //                 s1_root_info <= 0;
    //                 arrival_state_rd_addr <= 0;
    //                 arrival_state_wr_data <= 0;
    //             end
                
    //         endcase
    //     end
    // end


//流水线写法

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

    // S3, 读延迟(BRAM)
    reg [7:0]               s3_idx_psn;
    reg [7:0]               s3_ingress_port;
    reg                     s3_root_info;
    reg [METADATA_LEN-1:0]  s3_metadata;
    reg                     s3_valid;
    reg [DATA_WIDTH-1:0]    s3_arrival_state_in;
    reg [DATA_WIDTH-1:0]    s3_port_mask;
    reg [DATA_WIDTH-1:0]    s3_all_fin_mask;

    
    // S4, 收回rd读后的数据，进行判断后计算
    reg [7:0]               s4_idx_psn;
    reg [7:0]               s4_ingress_port;
    reg                     s4_root_info;
    reg [METADATA_LEN-1:0]  s4_metadata;
    reg                     s4_valid;

    reg [DATA_WIDTH-1:0]    s4_port_mask;
    reg [DATA_WIDTH-1:0]    s4_all_fin_mask;

    reg [DATA_WIDTH-1:0]    s4_bitmap_new;
    reg [DATA_WIDTH-1:0]    s4_arrival_state_in;

    // 中间变量
    reg                     s4_FAN_has_trans;
    reg                     s4_need_broadcast;
    reg                     s4_FAN_first_trans;

    // S5, 发出计算后的数据写wr请求
    reg                     s5_valid;
    reg [7:0]               s5_idx_psn;
    reg [7:0]               s5_ingress_port;
    reg                     s5_root_info;
    reg [METADATA_LEN-1:0]  s5_metadata;

    reg                     s5_copy_buffer_en;
    // reg                     s5_down_broadcast_en;
       
    // S6 等待wr返回
    reg                     s6_valid;
    reg [METADATA_LEN-1:0]  s6_metadata;
    reg                     s6_copy_buffer_en;
    // reg                     s6_down_broadcast_en;

    // S7 wr写成功
    reg                     s7_valid;
    reg [METADATA_LEN-1:0]  s7_metadata;
    reg                     s7_copy_buffer_en;
    // reg                     s7_down_broadcast_en;


    // 反压信号
    wire s1_can_accept;
    wire s2_can_accept;
    wire s3_can_accept;
    wire s4_can_accept;
    wire s5_can_accept;
    wire s6_can_accept;
    wire s7_can_accept; 

    // backpressure 
    wire task_for_buffer = s7_copy_buffer_en;
    // wire task_for_deparser = s7_down_broadcast_en;

    wire buffer_done = !to_buffer_valid || (to_buffer_valid && to_buffer_ready);
    // wire deparser_done = !to_deparser_valid || (to_deparser_valid && to_deparser_ready);

    // wire out_ready = buffer_done && deparser_done;
    wire out_ready = buffer_done;
    
    assign s7_can_accept = !s7_valid || (s7_valid && out_ready);
    assign s6_can_accept = !s6_valid || (s6_valid && s7_can_accept);
    assign s5_can_accept = !s5_valid || (s5_valid && s6_can_accept);
    assign s4_can_accept = !s4_valid || (s4_valid && s5_can_accept);
    assign s3_can_accept = !s3_valid || (s3_valid && s4_can_accept);
    assign s2_can_accept = !s2_valid || (s2_valid && s3_can_accept);
    assign s1_can_accept = !s1_valid || (s1_valid && s2_can_accept);

    assign in_ready = s1_can_accept;
    assign out_valid = s7_valid;

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
        end

        else begin
            arrival_state_rd_en <= 0;
            if (s2_can_accept || !s1_valid) begin
                s1_valid        <= in_valid; 
                s1_idx_psn      <= in_metadata[15:8];
                s1_ingress_port <= in_metadata[7:0];
                s1_root_info    <= in_metadata[16];
                s1_metadata     <= in_metadata;
                if (in_valid) begin
                    arrival_state_rd_en   <= 1'b1;
                    arrival_state_rd_addr <= in_metadata[15:8];
                end
            end
        end
    end

    // S2
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_idx_psn <= 0;
            s2_ingress_port <= 0;
            s2_root_info <= 0;
            s2_metadata <= 0;
            s2_valid <= 0;
        end
        else begin
            if (s3_can_accept || !s2_valid) begin
                s2_valid <= s1_valid;
                s2_idx_psn <= s1_idx_psn;
                s2_ingress_port <= s1_ingress_port;
                s2_root_info <= s1_root_info;
                s2_metadata <= s1_metadata;
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
            if ((s4_can_accept || !s3_valid) && arrival_state_rd_grant) begin
                s3_valid <= s2_valid;
                s3_idx_psn <= s2_idx_psn;
                s3_ingress_port <= s2_ingress_port;
                s3_root_info <= s2_root_info;
                s3_metadata <= s2_metadata;
                // s3_port_mask <= 32'h00000001 << FAN_IN;
                // s3_all_fin_mask <= 32'hFFFFFFFF >> (32 - FAN_IN);
                s3_port_mask <= 64'h0000000000000001 << FAN_IN;
                s3_all_fin_mask <= 64'hFFFFFFFFFFFFFFFF >> (64 - FAN_IN); 
            end
            else begin
                s3_valid <= 0;
                s3_idx_psn <= 0;
                s3_ingress_port <= 0;
                s3_metadata <= 0;
                s3_root_info <= 0;
                s3_port_mask <= 0;
                s3_all_fin_mask <= 0;
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
                s4_idx_psn <= s3_idx_psn;
                s4_ingress_port <= s3_ingress_port;
                s4_metadata <= s3_metadata;
                s4_root_info <= s3_root_info;
                s4_arrival_state_in <= arrival_state_bitmap_in;

                s4_FAN_has_trans <= |(arrival_state_bitmap_in & s3_port_mask);
                s4_need_broadcast <= ((arrival_state_bitmap_in & s3_all_fin_mask) == s3_all_fin_mask);
                s4_FAN_first_trans <= !(|(arrival_state_bitmap_in & s3_port_mask));
                s4_bitmap_new <= arrival_state_bitmap_in | s3_port_mask;
            end
        end  
    end

    // S5
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s5_idx_psn <= 0;
            s5_ingress_port <= 0;
            s5_root_info <= 0;
            s5_valid <= 0;
            s5_metadata <= 0;
            arrival_state_wr_en <= 0;
            s5_copy_buffer_en <= 0;
            // s5_down_broadcast_en <= 0;
        end

        else begin
            s5_copy_buffer_en <= 0;
            // s5_down_broadcast_en <= 0;
            arrival_state_wr_en <= 0;
            arrival_state_wr_addr <= 0;
            arrival_state_wr_data <= 0;

            if (s6_can_accept || !s5_valid) begin
                s5_valid <= s4_valid;
                s5_metadata <= s4_metadata;
                if (s4_FAN_first_trans && s4_need_broadcast) begin
                    s5_copy_buffer_en <= s4_valid;
                    // s5_down_broadcast_en <= s4_valid;
                    arrival_state_wr_en <= s4_valid;
                    arrival_state_wr_addr <= s4_idx_psn;
                    arrival_state_wr_data <= s4_bitmap_new;
                end
            end
        end
    end

    // S6
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s6_valid <= 0;
            s6_copy_buffer_en <= 0;
            // s6_down_broadcast_en <= 0;
            s6_metadata <= 0;
        end

        else begin
            if (s7_can_accept || !s6_valid) begin
                s6_valid <= s5_valid;
                s6_metadata <= s5_metadata;
                s6_copy_buffer_en <= s5_copy_buffer_en;
                // s6_down_broadcast_en <= s5_down_broadcast_en;
            end
        end
    end

    // S7
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s7_valid <= 0;
            s7_copy_buffer_en <= 0;
            // s7_down_broadcast_en <= 0; 
            s7_metadata <= 0;
        end

        else begin
            if ((out_ready || !s7_valid) && (s6_copy_buffer_en ? arrival_state_wr_grant : 1'b1)) begin
                s7_valid <= s6_valid;
                s7_metadata <= s6_metadata;
                s7_copy_buffer_en <= s6_copy_buffer_en;
                // s7_down_broadcast_en <= s6_down_broadcast_en;
            end
        end
    end

    assign to_buffer_metadata_out = s7_metadata;
    // assign to_deparser_metadata_out = s7_metadata;

    assign to_buffer_valid = s7_valid && task_for_buffer;
    // assign to_deparser_valid = s7_valid && task_for_deparser;

    assign copy_buffer_en =  s7_copy_buffer_en;
    // assign down_broadcast_en = s7_down_broadcast_en;

endmodule