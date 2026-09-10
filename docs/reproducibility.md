# Reproducible build policy

The repository stores design intent, not Vivado's generated project tree.

Tracked hardware inputs are RTL, constraints, the custom DDR4 part table, and
the three IP configuration (`.xci`) files. `hw/scripts/build.tcl` references
those inputs read-only from a disposable project under `build/vivado`.

## Hardware build

Use Vivado 2024.1 build 5076996:

```powershell
vivado -mode batch -source hw/scripts/build.tcl -tclargs project
vivado -mode batch -source hw/scripts/build.tcl -tclargs synth
vivado -mode batch -source hw/scripts/build.tcl -tclargs bitstream
```

The actions create the project, run synthesis, or run through bitstream
generation respectively. Removing `build/` must be sufficient to start a clean
build; no generated content under that directory is committed.

## Release artifacts

Publish `.bit`, `.ltx`, and `.xsa` files as GitHub Release assets and record the
Git commit plus the exact tool versions used. Do not commit them to the main
branch.

## Linux/GPU environment

The driver patch and host test are tracked under `host/`. Record the deployed
NVIDIA driver and CUDA versions in `toolchain.lock` after validating the target
machine. Keep captured `lspci`, `nvidia-smi topo -m`, and test logs as release or
CI artifacts rather than permanent source files.
