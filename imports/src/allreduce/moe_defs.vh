`ifndef MOE_DEFS_VH
`define MOE_DEFS_VH

// Fixed visible prefix carried at the beginning of the RoCE payload.
// Packet bytes 54..63 are the only payload bytes visible in the first
// 512-bit beat after the 54-byte Ethernet/IP/UDP/BTH header. The current
// prototype uses all 10 bytes for magic/version/op/owner/flags/seq_low,
// so tensor payload starts aligned at the second AXIS beat.
`define MOE_MAGIC                 16'h4D45  // "ME"
`define MOE_PREFIX_BASE_BYTES     10
`define MOE_DESC_WIDTH            128

`define MOE_OP_NONE               8'h00
`define MOE_OP_DISPATCH           8'h01
`define MOE_OP_COMBINE_INIT       8'h02
`define MOE_OP_COMBINE_DATA       8'h03
`define MOE_OP_COMBINE_RESULT     8'h04

`endif
