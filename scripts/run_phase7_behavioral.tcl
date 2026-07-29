set project_dir /home/ubuntu/cyf/NSDI27/100G_4port_allreduce_proj
set project_xpr [file join $project_dir 100G_4port_allreduce_proj.xpr]

open_project $project_xpr
set simset [get_filesets sim_1]
set_property top tb_allreduce_switch_datapath $simset
update_compile_order -fileset $simset

puts "PHASE7_SIM_TOP=[get_property TOP $simset]"
launch_simulation -simset $simset -mode behavioral
run all
close_sim
close_project
