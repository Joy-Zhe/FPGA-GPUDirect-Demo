set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
if {[info exists ::env(FPGA_GPUDIRECT_BUILD_ROOT)] &&
    $::env(FPGA_GPUDIRECT_BUILD_ROOT) ne ""} {
    set build_root [file normalize $::env(FPGA_GPUDIRECT_BUILD_ROOT)]
} else {
    set build_root [file join $repo_root build vivado]
}
set project_dir [file join $build_root project]
set project_name zynq_dma_ddr_demo
set part_name xczu19eg-ffvc1760-2-e

set required_vivado_version 2025.2
set running_vivado_version [version -short]
if {$running_vivado_version ne $required_vivado_version} {
    error "Vivado $required_vivado_version is required; running $running_vivado_version"
}

set action project
if {[llength $argv] > 0} {
    set action [lindex $argv 0]
}
set valid_actions [list project check synth impl bitstream]
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

proc find_block_design_sources {directory} {
    set block_designs [list]
    foreach path [glob -nocomplain -directory $directory *] {
        if {[file isdirectory $path]} {
            set block_designs [concat \
                $block_designs \
                [find_block_design_sources $path] \
            ]
        } elseif {[string equal -nocase [file extension $path] ".bd"]} {
            lappend block_designs $path
        }
    }
    return $block_designs
}

set tracked_block_design_files \
    [find_block_design_sources [file join $repo_root hw]]
if {[llength $tracked_block_design_files] > 0} {
    error "tracked Block Design files are forbidden; the PS monitor BD must be generated from Tcl: $tracked_block_design_files"
}

source [file join $script_dir create_ps_subsystem.tcl]
set ps_bd_file [create_ps_subsystem ps_subsystem]
generate_target all $ps_bd_file
set ps_wrapper_file [make_wrapper -files $ps_bd_file -top]
add_files -norecurse $ps_wrapper_file

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

set locked_ips [get_ips -quiet -filter {IS_LOCKED == 1}]
if {[llength $locked_ips] > 0} {
    error "locked IP detected; run hw/scripts/upgrade_ip.tcl with Vivado 2025.2: $locked_ips"
}

set ddr_part_file \
    [file join $repo_root hw ddr MT40A1G16KNR-075_REV_E_DIAG2400.csv]
set_property CONFIG.C0.DDR4_CustomParts $ddr_part_file [get_ips ddr4_0]

generate_target all [get_ips -quiet [list \
    qdma_0 \
    ddr4_0 \
    axi_clock_converter_0 \
]]
set_property top top [current_fileset]
update_compile_order -fileset sources_1

if {$action eq "check"} {
    check_syntax -fileset sources_1
}

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
