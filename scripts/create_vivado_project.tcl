# Creates the Vivado project in ./vivado
#   vivado -mode batch -source scripts/create_vivado_project.tcl
# (run from the project root)

set root [file normalize [file dirname [info script]]/..]
create_project csi2_rx_axis_bridge $root/vivado -part xc7z020clg484-1 -force

add_files -norecurse [concat [glob $root/rtl/cdc/*.v] [glob $root/rtl/*.v]]
add_files -fileset constrs_1 -norecurse $root/constraints/csi2_bridge.xdc
add_files -fileset sim_1 -norecurse $root/tb/tb_csi2_loopback.v

set_property top csi2_loopback_top [get_filesets sources_1]
set_property top tb_csi2_loopback  [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
close_project
