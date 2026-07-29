open_hw_manager
connect_hw_server -url TCP:127.0.0.1:3121
open_hw_target [lindex [get_hw_targets *Xilinx*] 0]
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set ltx_file "/home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj/artifacts/pre_codex23_clean_impl/qsfp28_100g_switch_4port_top.ltx"
set_property PROBES.FILE $ltx_file $dev
refresh_hw_device $dev
set vio [get_hw_vios hw_vio_2]
refresh_hw_vio $vio
foreach name {
    all_link_up
    all_test_pass
    any_error
    port_link_status
    port_error_status
} {
    set probe [get_hw_probes -quiet $name -of_objects $vio]
    if {[llength $probe] == 1} {
        puts "GLOBAL_VIO $name direction=IN value=[get_property INPUT_VALUE $probe]"
    } else {
        puts "GLOBAL_VIO $name missing"
    }
}
set port_enable [get_hw_probes -quiet vio_port_enable -of_objects $vio]
puts "GLOBAL_VIO vio_port_enable direction=OUT value=[get_property OUTPUT_VALUE $port_enable]"
disconnect_hw_server
close_hw_manager
