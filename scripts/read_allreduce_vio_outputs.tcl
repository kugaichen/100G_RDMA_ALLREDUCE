open_hw_manager
connect_hw_server -url TCP:127.0.0.1:3121

set target [get_hw_targets -quiet -filter {NAME =~ *Xilinx/24B19005A*}]
if {[llength $target] != 1} {
    error "expected one Xilinx/24B19005A hardware target"
}
open_hw_target $target

set dev [get_hw_devices -quiet xcvu13p_0]
if {[llength $dev] != 1} {
    error "expected one xcvu13p_0 device"
}
current_hw_device $dev
set project_dir /home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj
set_property PROBES.FILE \
    [file join $project_dir 100G_4port_allreduce_proj.runs impl_1 qsfp28_100g_switch_4port_top.ltx] \
    $dev
refresh_hw_device $dev

set cfg_vio [get_hw_vios -quiet -filter {CELL_NAME =~ *u_vio_allreduce_cfg*}]
if {[llength $cfg_vio] != 1} {
    error "expected one u_vio_allreduce_cfg VIO"
}
refresh_hw_vio $cfg_vio

foreach probe [lsort [get_hw_probes -of_objects $cfg_vio]] {
    set name [get_property NAME $probe]
    if {![catch {get_property OUTPUT_VALUE $probe} value]} {
        puts "AR_VIO $name=$value"
    }
}

close_hw_target
disconnect_hw_server
close_hw_manager
