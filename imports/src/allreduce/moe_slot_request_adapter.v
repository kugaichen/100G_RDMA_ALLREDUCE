`timescale 1ns / 1ps
`include "moe_defs.vh"
`include "slot_req_defs.vh"

module moe_slot_request_adapter #(
    parameter DESC_WIDTH = `MOE_DESC_WIDTH,
    parameter OWNER_WIDTH = 8,
    parameter GLOBAL_SEQ_WIDTH = 32,
    parameter PSN_WIDTH = 32,
    parameter EXPECTED_BITMAP_WIDTH = 64,
    parameter ROUTE_MASK_WIDTH = 8
) (
    input wire desc_valid,
    input wire [7:0] desc_op_type,
    input wire [DESC_WIDTH-1:0] desc_in,

    output wire slot_req_valid,
    output reg [2:0] slot_req_kind,
    output wire [OWNER_WIDTH-1:0] slot_owner_rank,
    output wire [7:0] slot_op_arg,
    output wire [7:0] slot_flags,
    output wire [GLOBAL_SEQ_WIDTH-1:0] slot_global_seq,
    output wire [GLOBAL_SEQ_WIDTH-1:0] slot_token_id,
    output wire [PSN_WIDTH-1:0] slot_psn,
    output wire [7:0] slot_ingress_id,
    output wire [7:0] slot_psn_mod,
    output wire [EXPECTED_BITMAP_WIDTH-1:0] slot_expected_bitmap,
    output wire [ROUTE_MASK_WIDTH-1:0] slot_route_mask,
    output wire [5:0] slot_lane_id,

    output wire is_dispatch,
    output wire is_combine_init,
    output wire is_combine_data,
    output wire is_combine_result
);
    wire [15:0] magic = desc_in[127:112];
    wire [7:0] version = desc_in[111:104];
    wire [7:0] embedded_op_type = desc_in[103:96];
    wire prefix_ok = (magic == `MOE_MAGIC) && (version == 8'h01) &&
                     (embedded_op_type == desc_op_type);

    assign slot_owner_rank = desc_in[95:88];
    assign slot_op_arg = desc_in[87:80];
    assign slot_flags = slot_op_arg;
    assign slot_global_seq = desc_in[79:48];
    assign slot_token_id = desc_in[79:48];
    assign slot_psn = desc_in[47:16];
    assign slot_ingress_id = desc_in[15:8];
    assign slot_psn_mod = desc_in[7:0];
    assign slot_expected_bitmap = {{(EXPECTED_BITMAP_WIDTH-8){1'b0}}, slot_op_arg};
    assign slot_route_mask = slot_op_arg[ROUTE_MASK_WIDTH-1:0];
    assign slot_lane_id = slot_op_arg[5:0];

    assign is_dispatch = slot_req_valid &&
                         (desc_op_type == `MOE_OP_DISPATCH);
    assign is_combine_init = slot_req_valid &&
                             (desc_op_type == `MOE_OP_COMBINE_INIT);
    assign is_combine_data = slot_req_valid &&
                             (desc_op_type == `MOE_OP_COMBINE_DATA);
    assign is_combine_result = slot_req_valid &&
                               (desc_op_type == `MOE_OP_COMBINE_RESULT);

    assign slot_req_valid = desc_valid && prefix_ok &&
                            (slot_req_kind != `SLOT_REQ_KIND_NONE);

    always @(*) begin
        slot_req_kind = `SLOT_REQ_KIND_NONE;

        case (desc_op_type)
            `MOE_OP_DISPATCH: begin
                slot_req_kind = `SLOT_REQ_KIND_DISPATCH;
            end
            `MOE_OP_COMBINE_INIT: begin
                slot_req_kind = `SLOT_REQ_KIND_INIT;
            end
            `MOE_OP_COMBINE_DATA: begin
                slot_req_kind = `SLOT_REQ_KIND_UPDATE;
            end
            `MOE_OP_COMBINE_RESULT: begin
                slot_req_kind = `SLOT_REQ_KIND_RESULT;
            end
            default: begin
                slot_req_kind = `SLOT_REQ_KIND_NONE;
            end
        endcase
    end
endmodule
