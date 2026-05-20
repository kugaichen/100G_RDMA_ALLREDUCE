`timescale 1ns / 1ps
// 极简 tb: 直接测试 crc32c_44B 核, 不经过 icrc_calc FSM
module tb_crc32c_44B_direct;

    wire [351:0] data_in;
    wire [31:0]  crc_in;
    wire [31:0]  crc_out;

    // 已知正确的输入 (Python 矩阵验证通过)
    // data_in[7:0] = 0x45 (IP byte 0), data_in[351:344] = 0x01 (AETH MSN last byte)
    assign data_in = 352'h0100001f000000fff66e00ffffff0011ffff1c00b712b7120101a8c00201a8c0ffff11ffffff11113000ff45;
    assign crc_in  = 32'hB798B438;

    crc32c_44B dut (
        .data_in(data_in),
        .crc_in(crc_in),
        .crc_out(crc_out)
    );

    initial begin
        #10;
        $display("crc_out = 0x%08X", crc_out);
        $display("Expected: 0x226CC99D");
        if (crc_out == 32'h226CC99D)
            $display("[PASS] CRC core is correct");
        else
            $display("[FAIL] CRC core mismatch");
        $finish;
    end
endmodule
