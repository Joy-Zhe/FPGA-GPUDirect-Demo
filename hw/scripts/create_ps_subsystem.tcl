# Create the Zynq UltraScale+ processing-system control-plane block design.
#
# This script is sourced from an open Vivado 2025.2 project.  The MIO and PS
# DDR settings are intentionally derived from example/SIC_code/1_4_Prj/bd/
# pcie_ps.tcl.  Only the interfaces used by this accelerator are exposed:
# HPM0 shares the accelerator AXI-Lite register bank with the QDMA BAR master,
# and one PL interrupt is routed to the PS GIC.

proc create_ps_subsystem {{design_name ps_subsystem}} {
    if {[llength [get_projects -quiet]] == 0} {
        error "create_ps_subsystem requires an open Vivado project"
    }

    if {[get_property PART [current_project]] ne "xczu19eg-ffvc1760-2-e"} {
        error "PS reference configuration is for xczu19eg-ffvc1760-2-e"
    }

    set old_design [current_bd_design -quiet]
    set existing_bd [get_files -quiet "*/${design_name}.bd"]
    if {[llength $existing_bd] != 0} {
        open_bd_design [lindex $existing_bd 0]
        return [lindex $existing_bd 0]
    }

    create_bd_design $design_name

    set ddr_enable_2t 0
    if {[info exists ::env(PS_DDR_ENABLE_2T)]} {
        set ddr_enable_2t $::env(PS_DDR_ENABLE_2T)
        if {$ddr_enable_2t ni {0 1}} {
            error "PS_DDR_ENABLE_2T must be 0 or 1"
        }
    }

    # The D9WFR package is exposed by the working PL MIG custom part as a
    # 16-Gbit x16 device made from 8-Gbit x8 components (Row16/BG2).  The
    # matching SIC 1_4 PS configuration uses that internal component geometry
    # on a 64-bit interface with ECC enabled.  Diagnostics can still override
    # ECC through PS_DDR_ECC without changing the component geometry.
    set ddr_ecc Enabled
    if {[info exists ::env(PS_DDR_ECC)]} {
        set ddr_ecc $::env(PS_DDR_ECC)
        if {$ddr_ecc ni {Enabled Disabled}} {
            error "PS_DDR_ECC must be Enabled or Disabled"
        }
    }

    # A two-rank setting is useful only as a hardware diagnostic for checking
    # whether CS1 has a populated device.  Keep the reference single-rank
    # configuration as the default.
    set ddr_rank_addr_count 0
    if {[info exists ::env(PS_DDR_RANK_ADDR_COUNT)]} {
        set ddr_rank_addr_count $::env(PS_DDR_RANK_ADDR_COUNT)
        if {$ddr_rank_addr_count ni {0 1}} {
            error "PS_DDR_RANK_ADDR_COUNT must be 0 or 1"
        }
    }

    # Vivado 2025.2 upgrades the 3.3 PS IP used by the 2019.2 reference to 3.5.
    set ps [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0]

    # Board-level settings copied from the SIC reference design.  Unused PS
    # peripherals remain disabled so they do not claim MIO pins.
    set_property -dict [list \
        CONFIG.PSU_BANK_0_IO_STANDARD {LVCMOS18} \
        CONFIG.PSU_BANK_1_IO_STANDARD {LVCMOS18} \
        CONFIG.PSU_BANK_2_IO_STANDARD {LVCMOS33} \
        CONFIG.PSU_BANK_3_IO_STANDARD {LVCMOS33} \
        CONFIG.PSU__PSS_REF_CLK__FREQMHZ {50} \
        CONFIG.PSU__QSPI__PERIPHERAL__ENABLE {1} \
        CONFIG.PSU__QSPI__PERIPHERAL__IO {MIO 0 .. 5} \
        CONFIG.PSU__QSPI__PERIPHERAL__DATA_MODE {x4} \
        CONFIG.PSU__QSPI__PERIPHERAL__MODE {Single} \
        CONFIG.PSU__QSPI__GRP_FBCLK__ENABLE {1} \
        CONFIG.PSU__QSPI__GRP_FBCLK__IO {MIO 6} \
        CONFIG.PSU__CRL_APB__QSPI_REF_CTRL__FREQMHZ {125} \
        CONFIG.PSU__CRL_APB__QSPI_REF_CTRL__SRCSEL {IOPLL} \
        CONFIG.PSU__SD0__PERIPHERAL__ENABLE {1} \
        CONFIG.PSU__SD0__PERIPHERAL__IO {MIO 13 .. 22} \
        CONFIG.PSU__SD0__DATA_TRANSFER_MODE {8Bit} \
        CONFIG.PSU__SD0__SLOT_TYPE {eMMC} \
        CONFIG.PSU__SD0__RESET__ENABLE {1} \
        CONFIG.PSU__SD0__GRP_POW__ENABLE {1} \
        CONFIG.PSU__SD0__GRP_POW__IO {MIO 23} \
        CONFIG.PSU__CRL_APB__SDIO0_REF_CTRL__FREQMHZ {100} \
        CONFIG.PSU__CRL_APB__SDIO0_REF_CTRL__SRCSEL {IOPLL} \
        CONFIG.PSU__UART0__PERIPHERAL__ENABLE {1} \
        CONFIG.PSU__UART0__PERIPHERAL__IO {MIO 54 .. 55} \
        CONFIG.PSU__UART0__BAUD_RATE {115200} \
        CONFIG.PSU__ENET0__PERIPHERAL__ENABLE {0} \
        CONFIG.PSU__ENET1__PERIPHERAL__ENABLE {0} \
        CONFIG.PSU__ENET2__PERIPHERAL__ENABLE {0} \
        CONFIG.PSU__ENET3__PERIPHERAL__ENABLE {0} \
        CONFIG.PSU__USB0__PERIPHERAL__ENABLE {0} \
        CONFIG.PSU__USB1__PERIPHERAL__ENABLE {0} \
        CONFIG.PSU__SATA__PERIPHERAL__ENABLE {0} \
        CONFIG.PSU__PCIE__PERIPHERAL__ENABLE {0} \
        CONFIG.PSU__DDRC__ENABLE {1} \
        CONFIG.PSU__DDRC__MEMORY_TYPE {DDR 4} \
        CONFIG.PSU__DDRC__BUS_WIDTH {64 Bit} \
        CONFIG.PSU__DDRC__ECC $ddr_ecc \
        CONFIG.PSU__DDRC__ENABLE_2T_TIMING $ddr_enable_2t \
        CONFIG.PSU__DDRC__COMPONENTS {Components} \
        CONFIG.PSU__DDRC__DRAM_WIDTH {8 Bits} \
        CONFIG.PSU__DDRC__DEVICE_CAPACITY {8192 MBits} \
        CONFIG.PSU__DDRC__RANK_ADDR_COUNT $ddr_rank_addr_count \
        CONFIG.PSU__DDRC__SPEED_BIN {DDR4_2400U} \
        CONFIG.PSU__DDRC__SB_TARGET {18-18-18} \
        CONFIG.PSU__DDRC__BRC_MAPPING {ROW_BANK_COL} \
        CONFIG.PSU__DDRC__DM_DBI {DM_NO_DBI} \
        CONFIG.PSU__DDRC__DDR4_ADDR_MAPPING {1} \
        CONFIG.PSU__DDRC__DQMAP_0_3 {0} \
        CONFIG.PSU__DDRC__DQMAP_4_7 {0} \
        CONFIG.PSU__DDRC__DQMAP_8_11 {0} \
        CONFIG.PSU__DDRC__DQMAP_12_15 {0} \
        CONFIG.PSU__DDRC__DQMAP_16_19 {0} \
        CONFIG.PSU__DDRC__DQMAP_20_23 {0} \
        CONFIG.PSU__DDRC__DQMAP_24_27 {0} \
        CONFIG.PSU__DDRC__DQMAP_28_31 {0} \
        CONFIG.PSU__DDRC__DQMAP_32_35 {0} \
        CONFIG.PSU__DDRC__DQMAP_36_39 {0} \
        CONFIG.PSU__DDRC__DQMAP_40_43 {0} \
        CONFIG.PSU__DDRC__DQMAP_44_47 {0} \
        CONFIG.PSU__DDRC__DQMAP_48_51 {0} \
        CONFIG.PSU__DDRC__DQMAP_52_55 {0} \
        CONFIG.PSU__DDRC__DQMAP_56_59 {0} \
        CONFIG.PSU__DDRC__DQMAP_60_63 {0} \
        CONFIG.PSU__DDRC__DQMAP_64_67 {0} \
        CONFIG.PSU__DDRC__DQMAP_68_71 {0} \
        CONFIG.PSU__DDRC__CL {18} \
        CONFIG.PSU__DDRC__CWL {16} \
        CONFIG.PSU__DDRC__ROW_ADDR_COUNT {16} \
        CONFIG.PSU__DDRC__COL_ADDR_COUNT {10} \
        CONFIG.PSU__DDRC__BANK_ADDR_COUNT {2} \
        CONFIG.PSU__DDRC__BG_ADDR_COUNT {2} \
        CONFIG.PSU__DDRC__T_RCD {18} \
        CONFIG.PSU__DDRC__T_RP {18} \
        CONFIG.PSU__DDRC__T_RC {47} \
        CONFIG.PSU__DDRC__T_RAS_MIN {32.0} \
        CONFIG.PSU__DDRC__T_FAW {30.0} \
        CONFIG.PSU__DDR__INTERFACE__FREQMHZ {600.000} \
        CONFIG.PSU__ACT_DDR_FREQ_MHZ {1200.000000} \
        CONFIG.PSU_DDR_RAM_LOWADDR_OFFSET {0x80000000} \
        CONFIG.PSU_DDR_RAM_HIGHADDR_OFFSET {0x800000000} \
        CONFIG.PSU_DDR_RAM_HIGHADDR {0x1FFFFFFFF} \
        CONFIG.PSU__HIGH_ADDRESS__ENABLE {1} \
        CONFIG.PSU__USE__M_AXI_GP0 {1} \
        CONFIG.PSU__MAXIGP0__DATA_WIDTH {32} \
        CONFIG.PSU__USE__M_AXI_GP1 {0} \
        CONFIG.PSU__USE__M_AXI_GP2 {0} \
        CONFIG.PSU__USE__S_AXI_GP0 {0} \
        CONFIG.PSU__USE__S_AXI_GP1 {0} \
        CONFIG.PSU__USE__S_AXI_GP2 {0} \
        CONFIG.PSU__USE__S_AXI_GP3 {0} \
        CONFIG.PSU__USE__S_AXI_GP4 {0} \
        CONFIG.PSU__USE__S_AXI_GP5 {0} \
        CONFIG.PSU__USE__IRQ0 {1} \
        CONFIG.PSU__USE__IRQ1 {0} \
        CONFIG.PSU__NUM_FABRIC_RESETS {1} \
        CONFIG.PSU__FPGA_PL0_ENABLE {1} \
        CONFIG.PSU__FPGA_PL1_ENABLE {1} \
        CONFIG.PSU__FPGA_PL2_ENABLE {1} \
        CONFIG.PSU__FPGA_PL3_ENABLE {0} \
        CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {12.5} \
        CONFIG.PSU__CRL_APB__PL1_REF_CTRL__FREQMHZ {200} \
        CONFIG.PSU__CRL_APB__PL2_REF_CTRL__FREQMHZ {250} \
    ] $ps

    # Export the dedicated PS DDR and MIO/fixed-I/O pin groups.  Vivado 2025.2
    # materializes these through the PS block-design automation rule.
    apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
        -config [list apply_board_preset 0 make_external {FIXED_IO, DDR}] $ps

    # Two masters (PS HPM0 and QDMA BAR AXI-Lite) arbitrate onto the single
    # attention-control register bank.  All paths run in the QDMA AXI clock
    # domain, avoiding an additional register-bank CDC.
    set axi_ic [create_bd_cell -type ip \
        -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_ctrl_interconnect]
    set_property -dict [list \
        CONFIG.NUM_SI {2} \
        CONFIG.NUM_MI {1} \
    ] $axi_ic

    set host_axi [create_bd_intf_port -mode Slave \
        -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI_HOST]
    set_property -dict [list \
        CONFIG.PROTOCOL {AXI4LITE} \
        CONFIG.ADDR_WIDTH {32} \
        CONFIG.DATA_WIDTH {32} \
        CONFIG.HAS_BURST {0} \
        CONFIG.HAS_LOCK {0} \
        CONFIG.HAS_CACHE {0} \
        CONFIG.HAS_QOS {0} \
        CONFIG.HAS_REGION {0} \
    ] $host_axi

    set ctrl_axi [create_bd_intf_port -mode Master \
        -vlnv xilinx.com:interface:aximm_rtl:1.0 M_AXI_CTRL]
    set_property -dict [list \
        CONFIG.PROTOCOL {AXI4LITE} \
        CONFIG.ADDR_WIDTH {32} \
        CONFIG.DATA_WIDTH {32} \
        CONFIG.HAS_BURST {0} \
        CONFIG.HAS_LOCK {0} \
        CONFIG.HAS_CACHE {0} \
        CONFIG.HAS_QOS {0} \
        CONFIG.HAS_REGION {0} \
    ] $ctrl_axi

    connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_HPM0_FPD] \
        [get_bd_intf_pins $axi_ic/S00_AXI]
    connect_bd_intf_net $host_axi [get_bd_intf_pins $axi_ic/S01_AXI]
    connect_bd_intf_net [get_bd_intf_pins $axi_ic/M00_AXI] $ctrl_axi

    set ctrl_aclk [create_bd_port -dir I -type clk \
        -freq_hz 250000000 ctrl_aclk]
    set_property -dict [list \
        CONFIG.ASSOCIATED_BUSIF {S_AXI_HOST:M_AXI_CTRL} \
        CONFIG.ASSOCIATED_RESET {ctrl_aresetn} \
    ] $ctrl_aclk
    set ctrl_aresetn [create_bd_port -dir I -type rst ctrl_aresetn]
    set_property CONFIG.POLARITY ACTIVE_LOW $ctrl_aresetn

    foreach pin [list \
        ACLK \
        S00_ACLK \
        S01_ACLK \
        M00_ACLK \
    ] {
        connect_bd_net $ctrl_aclk [get_bd_pins $axi_ic/$pin]
    }
    connect_bd_net $ctrl_aclk [get_bd_pins $ps/maxihpm0_fpd_aclk]

    foreach pin [list \
        ARESETN \
        S00_ARESETN \
        S01_ARESETN \
        M00_ARESETN \
    ] {
        connect_bd_net $ctrl_aresetn [get_bd_pins $axi_ic/$pin]
    }

    set ps_irq [create_bd_port -dir I -from 0 -to 0 ps_irq]
    connect_bd_net $ps_irq [get_bd_pins $ps/pl_ps_irq0]

    foreach clock_index [list 0 1 2] {
        set clock_port [create_bd_port -dir O -type clk ps_pl_clk${clock_index}]
        connect_bd_net $clock_port [get_bd_pins $ps/pl_clk${clock_index}]
    }
    set ps_pl_resetn [create_bd_port -dir O -type rst ps_pl_resetn]
    set_property CONFIG.POLARITY ACTIVE_LOW $ps_pl_resetn
    connect_bd_net $ps_pl_resetn [get_bd_pins $ps/pl_resetn0]

    # The downstream RTL register bank occupies 4 KiB at 0xA000_0000 from
    # the PS view.  QDMA BAR accesses retain their BAR-relative low address.
    assign_bd_address
    set ps_space [get_bd_addr_spaces -quiet $ps/Data]
    set ctrl_seg [get_bd_addr_segs -quiet M_AXI_CTRL/Reg]
    if {[llength $ps_space] != 0 && [llength $ctrl_seg] != 0} {
        set ps_mapping [get_bd_addr_segs -quiet \
            -of_objects $ps_space -filter {NAME =~ "*M_AXI_CTRL*"}]
        if {[llength $ps_mapping] != 0} {
            set_property offset 0xA0000000 $ps_mapping
            set_property range 4K $ps_mapping
        }
    }
    set host_space [get_bd_addr_spaces -quiet S_AXI_HOST]
    if {[llength $host_space] != 0} {
        set host_mapping [get_bd_addr_segs -quiet \
            -of_objects $host_space -filter {NAME =~ "*M_AXI_CTRL*"}]
        if {[llength $host_mapping] != 0} {
            set_property offset 0x00000000 $host_mapping
            set_property range 4K $host_mapping
        }
    }

    validate_bd_design
    save_bd_design
    set bd_file [get_files -quiet "*/${design_name}.bd"]

    if {$old_design ne "" && $old_design ne $design_name} {
        current_bd_design $old_design
    }
    return $bd_file
}
