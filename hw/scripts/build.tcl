set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set build_root [file join $repo_root build vivado]
set project_dir [file join $build_root project]
set project_name zynq_dma_ddr_demo
set part_name xczu19eg-ffvc1760-2-e

set action project
if {[llength $argv] > 0} {
    set action [lindex $argv 0]
}
set valid_actions [list project synth impl bitstream]
if {[lsearch -exact $valid_actions $action] < 0} {
    error "unknown action '$action'; expected one of: $valid_actions"
}

file mkdir $build_root
if {[file exists $project_dir]} {
    set normalized_project_dir [file normalize $project_dir]
    set normalized_build_root [file normalize $build_root]
    if {![string match "${normalized_build_root}/*" $normalized_project_dir]} {
        error "refusing to remove project directory outside build root"
    }
    file delete -force $normalized_project_dir
}
create_project -force $project_name $project_dir -part $part_name
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_files [list \
    [file join $repo_root hw rtl top.v] \
    [file join $repo_root hw rtl axi_lite_status.v] \
]
add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse \
    [file join $repo_root hw constraints pcie.xdc]

set ip_files [list \
    [file join $repo_root hw ip qdma_0 qdma_0.xci] \
    [file join $repo_root hw ip ddr4_0 ddr4_0.xci] \
    [file join $repo_root hw ip axi_clock_converter_0 axi_clock_converter_0.xci] \
]
import_ip -files $ip_files

set ddr_part_file \
    [file join $repo_root hw ddr MT40A1G16KNR-075_REV_E_DIAG2400.csv]
set_property CONFIG.C0.DDR4_CustomParts $ddr_part_file [get_ips ddr4_0]

generate_target all [get_ips]
set_property top top [current_fileset]
update_compile_order -fileset sources_1

proc require_complete {run_name} {
    set run_status [get_property STATUS [get_runs $run_name]]
    if {![string match "*Complete*" $run_status]} {
        error "$run_name failed with status: $run_status"
    }
}

if {[lsearch -exact [list synth impl bitstream] $action] >= 0} {
    launch_runs synth_1 -jobs 8
    wait_on_run synth_1
    require_complete synth_1
}

if {$action eq "impl"} {
    launch_runs impl_1 -to_step route_design -jobs 8
    wait_on_run impl_1
    require_complete impl_1
}

if {$action eq "bitstream"} {
    launch_runs impl_1 -to_step write_bitstream -jobs 8
    wait_on_run impl_1
    require_complete impl_1
}

close_project
