# Repository Agent Instructions

## RTL instance formatting

- When instantiating any Verilog or SystemVerilog module, place every named port connection on its own line.
- This rule applies to connected ports, constant-tied ports, and intentionally unconnected ports.
- Never place two or more port connections on the same line.
- Keep the opening parenthesis on the instance declaration line and place the closing `);` on a separate line.

Required style:

```verilog
module_name u_module_name (
    .clk        (clk),
    .reset_n    (reset_n),
    .status     (),
    .enable     (1'b1)
);
```

Disallowed style:

```verilog
module_name u_module_name (
    .clk(clk), .reset_n(reset_n), .status()
);
```

## RTL module port declaration formatting

- In every Verilog or SystemVerilog module declaration, place each port on its own line.
- Repeat the direction and net type for every port; never combine multiple port names into one declaration.
- Write the module name and opening parenthesis on one line, and write the closing `);` on a separate line.
- Place the comma after each port name. Do not place a comma after the final port.
- Align direction, net type, packed width, port name, and commas consistently, following the style below.

Required style:

```verilog
module top (
    input  wire                         i_pcie_ref_clk_n           ,
    input  wire                         i_pcie_ref_clk_p           ,
    input  wire                         i_pcie_rst_n               ,
    input  wire          [  15: 0]      pcie_rxn                   ,
    input  wire          [  15: 0]      pcie_rxp                   ,
    output wire          [  15: 0]      pcie_txn                   ,
    output wire          [  15: 0]      pcie_txp                   ,
    output wire                         DDR4_act_n                 ,
    output wire          [  16: 0]      DDR4_adr                   ,
    output wire          [   1: 0]      DDR4_ba                    ,
    output wire          [   1: 0]      DDR4_bg                    ,
    output wire          [   0: 0]      DDR4_ck_c                  ,
    output wire          [   0: 0]      DDR4_ck_t                  ,
    output wire          [   0: 0]      DDR4_cke                   ,
    output wire          [   1: 0]      DDR4_cs_n                  ,
    inout  wire          [   8: 0]      DDR4_dm_n                  ,
    inout  wire          [  71: 0]      DDR4_dq                    ,
    inout  wire          [   8: 0]      DDR4_dqs_c                 ,
    inout  wire          [   8: 0]      DDR4_dqs_t                 ,
    output wire          [   0: 0]      DDR4_odt                   ,
    output wire                         DDR4_reset_n               ,
    input  wire                         DDR_ref_clk_n              ,
    input  wire                         DDR_ref_clk_p
);
```

Disallowed style:

```verilog
module top (
    input wire clk, reset_n,
    output wire [15:0] data, status
);
```
