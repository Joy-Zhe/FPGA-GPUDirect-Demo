set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
if {[info exists ::env(FPGA_GPUDIRECT_BUILD_ROOT)] &&
    $::env(FPGA_GPUDIRECT_BUILD_ROOT) ne ""} {
    set build_root [file normalize $::env(FPGA_GPUDIRECT_BUILD_ROOT)]
} else {
    set build_root [file join $repo_root build vivado]
}
set project_dir [file join $build_root ip_upgrade]
set project_name zynq_dma_ddr_demo_ip_upgrade
set part_name xczu19eg-ffvc1760-2-e

set required_vivado_version 2025.2
set running_vivado_version [version -short]
if {$running_vivado_version ne $required_vivado_version} {
    error "Vivado $required_vivado_version is required; running $running_vivado_version"
}

file mkdir $build_root
if {[file exists $project_dir]} {
    set normalized_project_dir [file normalize $project_dir]
    set normalized_build_root [file normalize $build_root]
    if {![string match "${normalized_build_root}/*" $normalized_project_dir]} {
        error "refusing to remove upgrade directory outside build root"
    }
    file delete -force $normalized_project_dir
}

create_project -force $project_name $project_dir -part $part_name

set ip_files [list \
    [file join $repo_root hw ip qdma_0 qdma_0.xci] \
    [file join $repo_root hw ip ddr4_0 ddr4_0.xci] \
    [file join $repo_root hw ip axi_clock_converter_0 axi_clock_converter_0.xci] \
]
read_ip $ip_files

set locked_ips [get_ips -quiet -filter {IS_LOCKED == 1}]
if {[llength $locked_ips] > 0} {
    upgrade_ip $locked_ips
}

set ddr_part_file \
    [file join $repo_root hw ddr MT40A1G16KNR-075_REV_E_DIAG2400.csv]
set_property CONFIG.C0.DDR4_CustomParts $ddr_part_file [get_ips ddr4_0]

set remaining_locked_ips [get_ips -quiet -filter {IS_LOCKED == 1}]
if {[llength $remaining_locked_ips] > 0} {
    error "IP upgrade incomplete; locked IP remains: $remaining_locked_ips"
}

close_project
