if {$argc != 2} {
    error "usage: hw_program_pair_codex22.tcl <bit_file> <ltx_file>"
}

set bit_file [file normalize [lindex $argv 0]]
set ltx_file [file normalize [lindex $argv 1]]
if {![file exists $bit_file] || ![file exists $ltx_file]} {
    error "bit or ltx file does not exist"
}

open_hw_manager
connect_hw_server -url TCP:127.0.0.1:3121
open_hw_target [lindex [get_hw_targets *Xilinx*] 0]

set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit_file $dev
set_property PROBES.FILE $ltx_file $dev
program_hw_devices $dev
after 3000
refresh_hw_device $dev

set vio_global [get_hw_vios hw_vio_2]
set port_enable [get_hw_probes vio_port_enable -of_objects $vio_global]
if {[llength $port_enable] != 1 || [get_property WIDTH $port_enable] != 4} {
    error "vio_port_enable probe is not the expected 4-bit probe"
}
set_property OUTPUT_VALUE b $port_enable
commit_hw_vio $vio_global

puts "CODEX22_PROGRAM_PAIR_PASS"
puts "BIT_FILE=$bit_file"
puts "LTX_FILE=$ltx_file"
puts "VIO_PORT_ENABLE=[get_property OUTPUT_VALUE $port_enable]"

disconnect_hw_server
close_hw_manager
