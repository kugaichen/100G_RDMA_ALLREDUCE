set project_dir /home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj
set project_xpr [file join $project_dir 100G_4port_allreduce_proj.xpr]
set log_dir [file join $project_dir logs]

file mkdir $log_dir
open_project $project_xpr
set srcset [get_filesets sources_1]
set_property top qsfp28_100g_switch_4port_top $srcset
update_compile_order -fileset $srcset

set_property STRATEGY Flow_RuntimeOptimized [get_runs synth_1]
set_property STRATEGY Flow_RuntimeOptimized [get_runs impl_1]

reset_run synth_1
reset_run impl_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "synth_1 failed: [get_property STATUS [get_runs synth_1]]"
}

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "impl_1 failed: [get_property STATUS [get_runs impl_1]]"
}

open_run impl_1
report_utilization -file [file join $log_dir minimal_utilization.rpt]
report_timing_summary -file [file join $log_dir minimal_timing_summary.rpt]
write_checkpoint -force [file join $log_dir minimal_impl.dcp]
puts "MINIMAL_BUILD_PASS"
close_project
