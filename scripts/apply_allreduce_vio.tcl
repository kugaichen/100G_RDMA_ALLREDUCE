# Usage:
# vivado -mode batch -source scripts/apply_allreduce_vio.tcl \
#   -tclargs <worker0_qpn> <worker1_qpn>

if {$argc != 2} {
    error "usage: apply_allreduce_vio.tcl <worker0_qpn> <worker1_qpn>"
}

set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
source [file join $project_dir configs lab_2worker_vio.tcl]

set worker0_qpn [expr {[lindex $argv 0] & 0x00ffffff}]
set worker1_qpn [expr {[lindex $argv 1] & 0x00ffffff}]
set ar_cfg(ar_cfg_worker0_qp) $worker0_qpn
set ar_cfg(ar_cfg_worker1_qp) $worker1_qpn

if {[info exists ::env(VIO_DRY_RUN)] && $::env(VIO_DRY_RUN) eq "1"} {
    foreach name [lsort [array names ar_cfg]] {
        puts [format "VIO_DRY_RUN %-28s 0x%x" $name $ar_cfg($name)]
    }
    puts [format "VIO_DRY_RUN_PASS worker0_qpn=0x%06x worker1_qpn=0x%06x" \
          $worker0_qpn $worker1_qpn]
    exit 0
}

proc set_vio_probe {name value} {
    set probe [get_hw_probes -quiet $name]
    if {[llength $probe] != 1} {
        error "expected exactly one VIO probe named $name, got [llength $probe]"
    }
    set width [get_property WIDTH $probe]
    set hex_digits [expr {($width + 3) / 4}]
    set_property OUTPUT_VALUE [format "%0*x" $hex_digits $value] $probe
}

proc verify_vio_probe {name expected} {
    set probe [get_hw_probes -quiet $name]
    set actual_text [get_property OUTPUT_VALUE $probe]
    scan $actual_text %x actual
    if {$actual != $expected} {
        error [format "%s mismatch: expected 0x%x, read 0x%x" $name $expected $actual]
    }
    puts [format "VIO_OK %-28s 0x%x" $name $actual]
}

open_hw_manager
connect_hw_server -url TCP:127.0.0.1:3121
set target [get_hw_targets -quiet -filter {NAME =~ *Xilinx/24B19005A*}]
if {[llength $target] != 1} {
    error "expected Xilinx/24B19005A hardware target"
}
open_hw_target $target

set dev [get_hw_devices -quiet xcvu13p_0]
if {[llength $dev] != 1} {
    error "expected one xcvu13p_0 device"
}
current_hw_device $dev
set ltx_file [file join $project_dir 100G_4port_allreduce_proj.runs impl_1 qsfp28_100g_switch_4port_top.ltx]
set_property PROBES.FILE $ltx_file $dev
refresh_hw_device $dev

set cfg_vio [get_hw_vios -quiet -filter {CELL_NAME =~ *u_vio_allreduce_cfg*}]
if {[llength $cfg_vio] != 1} {
    error "expected one u_vio_allreduce_cfg VIO, got [llength $cfg_vio]"
}

# Commit data fields while update is low.
set_vio_probe ar_cfg_update_en 0
foreach name [lsort [array names ar_cfg]] {
    set_vio_probe $name $ar_cfg($name)
}
commit_hw_vio $cfg_vio

# Level-sensitive register update: one explicit 0 -> 1 -> 0 transaction.
set_vio_probe ar_cfg_update_en 1
commit_hw_vio $cfg_vio
after 100
set_vio_probe ar_cfg_update_en 0
commit_hw_vio $cfg_vio

foreach name [lsort [array names ar_cfg]] {
    verify_vio_probe $name $ar_cfg($name)
}
verify_vio_probe ar_cfg_update_en 0

puts [format "VIO_APPLY_PASS worker0_qpn=0x%06x worker1_qpn=0x%06x" \
      $worker0_qpn $worker1_qpn]
close_hw_target
disconnect_hw_server
close_hw_manager
