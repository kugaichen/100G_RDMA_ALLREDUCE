# Create the optional AllReduce debug configuration VIO IP.
# Usage inside Vivado project:
#   source scripts/create_vio_allreduce_cfg.tcl
#   set_property verilog_define {ENABLE_VIO_ALLREDUCE_CFG} [get_filesets sources_1]

if {[llength [get_ips vio_allreduce_cfg -quiet]] == 0} {
    create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_allreduce_cfg
}

set vio_ip [get_ips vio_allreduce_cfg]
set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN {0} \
    CONFIG.C_NUM_PROBE_OUT {24} \
    CONFIG.C_PROBE_OUT0_WIDTH {1} \
    CONFIG.C_PROBE_OUT1_WIDTH {8} \
    CONFIG.C_PROBE_OUT2_WIDTH {4} \
    CONFIG.C_PROBE_OUT3_WIDTH {1} \
    CONFIG.C_PROBE_OUT4_WIDTH {48} \
    CONFIG.C_PROBE_OUT5_WIDTH {32} \
    CONFIG.C_PROBE_OUT6_WIDTH {24} \
    CONFIG.C_PROBE_OUT7_WIDTH {16} \
    CONFIG.C_PROBE_OUT8_WIDTH {48} \
    CONFIG.C_PROBE_OUT9_WIDTH {32} \
    CONFIG.C_PROBE_OUT10_WIDTH {24} \
    CONFIG.C_PROBE_OUT11_WIDTH {16} \
    CONFIG.C_PROBE_OUT12_WIDTH {48} \
    CONFIG.C_PROBE_OUT13_WIDTH {32} \
    CONFIG.C_PROBE_OUT14_WIDTH {24} \
    CONFIG.C_PROBE_OUT15_WIDTH {16} \
    CONFIG.C_PROBE_OUT16_WIDTH {48} \
    CONFIG.C_PROBE_OUT17_WIDTH {32} \
    CONFIG.C_PROBE_OUT18_WIDTH {24} \
    CONFIG.C_PROBE_OUT19_WIDTH {16} \
    CONFIG.C_PROBE_OUT20_WIDTH {48} \
    CONFIG.C_PROBE_OUT21_WIDTH {32} \
    CONFIG.C_PROBE_OUT22_WIDTH {24} \
    CONFIG.C_PROBE_OUT23_WIDTH {16} \
] $vio_ip

generate_target all $vio_ip
export_ip_user_files -of_objects $vio_ip -no_script -sync -force -quiet
