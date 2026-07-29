# Static laboratory configuration. Worker QPNs are intentionally supplied
# at runtime to apply_allreduce_vio.tcl.
array set ar_cfg {
    ar_cfg_parent_port       0x00
    ar_cfg_child_port_mask   0x3
    ar_cfg_is_root           0x1
    ar_cfg_fpga_mac          0x020000000307
    ar_cfg_fpga_ip           0xC0A80307
    ar_cfg_fpga_qp           0x000100
    ar_cfg_fpga_udp_port     0x12B7
    ar_cfg_worker0_mac       0x6CB31188AB3E
    ar_cfg_worker0_ip        0xC0A80305
    ar_cfg_worker0_udp_port  0x12B7
    ar_cfg_worker1_mac       0x6CB31188A94E
    ar_cfg_worker1_ip        0xC0A80306
    ar_cfg_worker1_udp_port  0x12B7
    ar_cfg_worker2_mac       0x000000000000
    ar_cfg_worker2_ip        0x00000000
    ar_cfg_worker2_qp        0x000000
    ar_cfg_worker2_udp_port  0x0000
    ar_cfg_worker3_mac       0x000000000000
    ar_cfg_worker3_ip        0x00000000
    ar_cfg_worker3_qp        0x000000
    ar_cfg_worker3_udp_port  0x0000
}
