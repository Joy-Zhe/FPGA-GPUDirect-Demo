# FPGA QDMA、DDR4 与 GPU 数据通路

基于 Zynq UltraScale+ `XCZU19EG-FFVC1760-2-e` 的 PCIe QDMA 数据通路示例。设计使用 Vivado 2025.2 构建 PCIe Gen3 x16 QDMA、8 GiB PL DDR4，以及独立的 PS 状态监控控制面。

由于消费级显卡目前不支持 NVIDIA GPUDirect RDMA，本仓库默认采用并已完成实板验证的数据路径如下：

```text
NVIDIA GPU
    ↕ CUDA copy
CUDA pinned host memory（页锁定主机内存）
    ↕ QDMA MM
FPGA PL DDR4
```

仓库同时保留基于 NVIDIA `nv-p2p` 内核 API 的显存直通实现，供明确支持 GPUDirect RDMA 的 GPU 使用。

## 项目特性

- PCIe Gen3 x16 QDMA Memory-Mapped 数据通路；
- 8 GiB PL DDR4，支持 33-bit AXI 地址；
- GPU 与 FPGA DDR 间的 CUDA 页锁定主机内存 staging 路径；
- 可选的 NVIDIA GPUDirect RDMA 显存直通路径；
- QDMA BAR2 与 PS HPM0 共享的状态寄存器；
- RTL/XCI 数据面，PS Block Design 由 Tcl 构建时生成；
- 可复现的 Vivado、驱动和主机端构建流程。

## 验证状态

以下结果来自当前实板环境；PCI BDF 和 QDMA 设备名在其他主机上可能不同。

| 项目 | 版本或状态 |
| --- | --- |
| FPGA | XCZU19EG-FFVC1760-2-e |
| Vivado | 2025.2 build 6299465 |
| QDMA IP | 5.1，PCIe Gen3 x16，MM enabled |
| PL DDR | DDR4 IP 2.2，8 GiB，calibration passed |
| Linux | Ubuntu 22.04.5，6.8.0-138-generic |
| GPU | NVIDIA GeForce RTX 5070 Ti |
| NVIDIA 驱动 | 595.91.07 open kernel modules |
| CUDA | 13.2 headers，运行时使用系统 `libcuda.so.1` |
| FPGA PCI 地址 | `0000:08:00.0`，QDMA 设备名 `qdma08000` |

已完成的验证：

- FPGA startup status 为 `HIGH`；
- MIG `CALIBRATION_FAIL=FALSE`，所有 Rank0 calibration stage 均为 `PASS`；
- BAR2 状态为 design ID `0x51444d41`、DDR ready `1`、ABI version `0x00010000`；
- 64 MiB 主机内存→DDR→主机内存随机数据回环逐字节一致；
- 64 MiB GPU→pinned host→DDR→pinned host→GPU 在 DDR offset `0` 和 `0x40000000` 均逐字节一致；
- RTX 5070 Ti 报告 `CU_DEVICE_ATTRIBUTE_GPU_DIRECT_RDMA_SUPPORTED=0`，显存直通测试不作为该机器的验收项。

## 硬件架构

```text
PCIe ── QDMA AXI-MM ── AXI clock converter ── PL DDR4 MIG
          │
          └── BAR2 AXI-Lite ──┐
                              ├── AXI interconnect ── status registers
PS HPM0 AXI-Lite ─────────────┘
```

- QDMA、PL DDR 和主数据面使用 RTL 与独立 XCI 构建，不使用 Block Design。
- PS 监控控制面允许使用 Block Design，但由 `hw/scripts/create_ps_subsystem.tcl` 在构建时生成；仓库不提交 `.bd` 文件。
- PS 不经过 GPU/DDR 数据面，只用于读取状态和后续板级监控。
- PS 从 `0xA000_0000` 访问状态寄存器；QDMA BAR2 从相对地址 `0x0000` 访问同一组寄存器。
- QDMA 地址低 33 位映射到 8 GiB PL DDR。

| Offset | 状态寄存器 |
| --- | --- |
| `0x00` | Design ID，期望 `0x51444d41`（`QDMA`） |
| `0x04[0]` | DDR calibration done |
| `0x08` | Scratch register |
| `0x0c` | ABI version，当前 `0x00010000` |

## 仓库结构

```text
.
├── hw/
│   ├── constraints/       # PCIe 与板级管脚约束
│   ├── ddr/               # 自定义 DDR4 器件参数
│   ├── ip/                # QDMA、DDR4、AXI Clock Converter XCI
│   ├── rtl/               # 顶层 RTL 与状态寄存器
│   └── scripts/           # Vivado 构建与 PS 子系统生成脚本
├── host/
│   ├── gpu_staging_test.cpp
│   ├── gpu_p2p_test.cpp
│   ├── prepare_driver.sh
│   └── setup_queues.sh
├── docs/reproducibility.md
└── toolchain.lock
```

## 部署流程

完整部署按以下顺序进行：

1. 准备 Vivado、Linux、NVIDIA 和 CUDA headers；
2. 在后台生成 bitstream；
3. 通过 JTAG 配置 FPGA；
4. remove/rescan PCIe Endpoint；
5. 构建并加载 QDMA 驱动；
6. 创建双向 MM queue；
7. 先验证主机内存与 PL DDR，再验证 GPU staging 数据通路。

后续章节给出每一步的完整命令。

## 环境要求

### FPGA 构建机

- Vivado 2025.2 build 6299465；
- Digilent JTAG cable 驱动；
- 仓库根目录作为所有命令的当前目录。

### Linux/GPU 主机

```bash
sudo apt install build-essential git libaio-dev linux-headers-$(uname -r)
```

需要 NVIDIA 595.91.07 open kernel module 及其匹配的开发源码：

```bash
test -f /usr/src/nvidia-595.91.07/nvidia-peermem/nv-p2p.h
nvidia-smi
```

Host 测试只使用 CUDA Driver API，不需要 `nvcc`。编译时必须能找到以下任一位置的 CUDA headers：

```text
/usr/local/cuda/include/cuda.h
build/cuda-13.2-local/usr/local/cuda-13.2/targets/x86_64-linux/include/cuda.h
```

`host/Makefile` 会优先使用 `/usr/local/cuda`，否则使用 `build/` 下的本地 headers。CUDA Toolkit 版本不会改变 GPU 是否支持 GPUDirect RDMA。

如当前主机需要通过本地 `7897` 端口下载 Git 或 CUDA 资源，可在执行下载命令的同一 shell 中临时设置：

```bash
export http_proxy=http://127.0.0.1:7897
export https_proxy=http://127.0.0.1:7897
```

这些变量只影响当前 shell；不需要联网的构建和实板测试不依赖代理。

## 构建硬件

短时间的工程创建、IP 检查和 RTL syntax check 可以前台运行：

```bash
vivado -mode batch -source hw/scripts/build.tcl -tclargs project
vivado -mode batch -source hw/scripts/build.tcl -tclargs check
```

综合、实现和 bitstream 必须作为后台任务运行，日志和 PID 保存在 `build/logs/`。以下示例生成完整 bitstream；启动前会检查是否已有同类任务：

```bash
mkdir -p build/logs
ACTION=bitstream
if pgrep -af "[v]ivado.*hw/scripts/build.tcl.*${ACTION}" >/dev/null; then
    echo "Vivado ${ACTION} is already running"
else
    STAMP="$(date +%Y%m%d-%H%M%S)"
    LOG="build/logs/vivado-${ACTION}-${STAMP}.log"
    PID_FILE="build/logs/vivado-${ACTION}-${STAMP}.pid"
    nohup vivado -mode batch -source hw/scripts/build.tcl \
        -tclargs "${ACTION}" >"${LOG}" 2>&1 < /dev/null &
    VIVADO_PID=$!
    echo "${VIVADO_PID}" >"${PID_FILE}"
    disown "${VIVADO_PID}"
    echo "PID=${VIVADO_PID} log=${LOG}"
fi
```

后台任务启动后即可继续进行其他工作，无需持续轮询。任务结束后从日志确认 `write_bitstream` 成功，产物为：

```text
build/vivado/project/zynq_dma_ddr_demo.runs/impl_1/top.bit
```

仓库只提交 RTL、XDC、自定义 DDR part、XCI 和构建 Tcl；`.bit`、`.ltx`、`.xsa` 与 Vivado 派生工程不提交。详细规则见 [`docs/reproducibility.md`](docs/reproducibility.md)。

## 配置 FPGA 与枚举 PCIe

### JTAG 配置

在 Vivado Hardware Manager 中：

1. 打开 Hardware Manager 并连接 Digilent JTAG target；
2. 选择 `xczu19` 器件；
3. Program Device，选择本仓库生成的 `top.bit`；
4. 确认 startup status 为 `HIGH`，并检查 MIG calibration 没有错误。

JTAG 配置是易失的。本板冷启动后会恢复启动介质中的另一份 PCIe switch 镜像，通常表现为 `10ee:903f`、class `0604`。本仓库的正确 QDMA Endpoint 同样使用 device ID `10ee:903f`，但 class 应为 `0580`、subsystem 应为 `10ee:0007`，不能只按 device ID 判断。

### PCIe remove/rescan

JTAG 下载后不需要热重启。先确认旧设备 BDF；当前实板是 `0000:08:00.0`，换机器后必须重新确认：

```bash
lspci -nn -d 10ee:
```

对确认过的旧设备执行 remove/rescan：

```bash
FPGA_BDF=0000:08:00.0
echo 1 | sudo tee "/sys/bus/pci/devices/${FPGA_BDF}/remove"
echo 1 | sudo tee /sys/bus/pci/rescan
lspci -nn -s 08:00.0 -k
```

期望看到：

```text
08:00.0 Memory controller [0580]: Xilinx Corporation Device [10ee:903f]
Subsystem: Xilinx Corporation Device [10ee:0007]
```

如果仍为 class `0604`，说明当前仍是启动介质中的 switch 镜像或 PCIe 没有正确重新枚举；此时不要加载 QDMA 驱动到该 bridge。

## 构建并加载 QDMA 驱动

准备脚本会在 `build/dma_ip_drivers` 获取锁定的 AMD/Xilinx QDMA commit `3cf1905`，应用仓库补丁并复制 NVIDIA symbol CRC 文件：

```bash
bash host/prepare_driver.sh
```

驱动必须串行构建；上游 PF/VF Makefile 并行构建存在竞争，不要使用 `-j`：

```bash
NVIDIA_P2P_INCLUDE=/usr/src/nvidia-595.91.07/nvidia-peermem \
  make -C build/dma_ip_drivers/QDMA/linux-kernel/driver \
  modulesymfile=Module.symvers \
  extra_symb="$PWD/build/nvidia-p2p.symvers"

make -C build/dma_ip_drivers/QDMA/linux-kernel/apps
sudo make -C build/dma_ip_drivers/QDMA/linux-kernel/driver install-mods
sudo depmod -a
sudo modprobe qdma-pf
```

确认驱动只绑定到 class `0580` 的 QDMA Endpoint：

```bash
lspci -nn -s 08:00.0 -k
lsmod | grep qdma
```

`host/nvidia-p2p.symvers` 只匹配 NVIDIA 595.91.07。升级 NVIDIA 驱动后必须从新 `nvidia.ko` 重新生成 symbol CRC，并重新构建 QDMA 模块。

## 创建 QDMA MM 队列

```bash
export PATH="$PWD/build/dma_ip_drivers/QDMA/linux-kernel/bin:$PATH"
sudo --preserve-env=PATH dma-ctl dev list
```

根据输出选择设备名。当前实板 `0000:08:00.0` 对应 `qdma08000`：

```bash
QDMA_DEVICE=qdma08000
sudo --preserve-env=PATH ./host/setup_queues.sh "${QDMA_DEVICE}" 0
ls -l "/dev/${QDMA_DEVICE}-MM-0"
```

脚本会分配并启动 queue 0 的双向 MM queue pair。队列已经存在时不要重复执行 `q add`；可以检查当前状态：

```bash
sudo --preserve-env=PATH dma-ctl "${QDMA_DEVICE}" q list 0 1
```

队列和设备节点不跨重启保留，驱动重新加载或系统重启后需要重新建立。

## 验证数据通路

验证顺序固定为：PCIe/QDMA → Host/DDR → GPU staging。只有前一级通过后才继续下一级。

### 主机内存 ↔ PL DDR

执行 64 MiB 随机数据写入、读回和比较：

```bash
mkdir -p build/test
dd if=/dev/urandom of=build/test/host-ddr-input.bin \
    bs=1M count=64 status=progress

sudo --preserve-env=PATH dma-to-device \
    -d /dev/qdma08000-MM-0 \
    -a 0 \
    -s 67108864 \
    -f build/test/host-ddr-input.bin

sudo --preserve-env=PATH dma-from-device \
    -d /dev/qdma08000-MM-0 \
    -a 0 \
    -s 67108864 \
    -f build/test/host-ddr-output.bin

sha256sum build/test/host-ddr-input.bin build/test/host-ddr-output.bin
cmp build/test/host-ddr-input.bin build/test/host-ddr-output.bin
```

`cmp` 无输出且退出码为 0 表示数据一致。当前实板的单次参考结果为 H2C `2.31 GB/s`、C2H `1.37 GB/s`。

### 默认路径：GPU ↔ pinned host memory ↔ PL DDR

```bash
make -C host
sudo ./host/gpu_staging_test /dev/qdma08000-MM-0 64 0
sudo ./host/gpu_staging_test /dev/qdma08000-MM-0 64 0x40000000
```

最后两个参数分别是 MiB 和 DDR byte offset。程序执行完整往返并逐字节比较最终 GPU 数据：

```text
GPU -> CUDA pinned host -> QDMA H2C -> PL DDR
GPU <- CUDA pinned host <- QDMA C2H <- PL DDR
```

期望输出以 `PASS: GPU <-> pinned host memory <-> FPGA DDR` 开头。已验证结果：

| DDR offset | GPU→Host | Host→DDR | DDR→Host | Host→GPU | 四段往返 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `0` | 22.972 GiB/s | 2.183 GiB/s | 1.570 GiB/s | 24.432 GiB/s | 73.718 ms |
| `0x40000000` | 24.348 GiB/s | 2.355 GiB/s | 2.364 GiB/s | 25.021 GiB/s | 58.038 ms |

该路径不依赖 GPUDirect RDMA，但会多执行两次 PCIe CUDA copy，并占用一块与传输大小相同的锁页主机内存。

### 可选路径：GPU 显存直通 P2P

只有 GPU 报告 `CU_DEVICE_ATTRIBUTE_GPU_DIRECT_RDMA_SUPPORTED=1` 时才运行：

```bash
sudo ./host/gpu_p2p_test /dev/qdma08000-MM-0 64 0
```

该程序通过 `nvidia_p2p_get_pages_persistent()` 和 `nvidia_p2p_dma_map_pages()` 将 GPU pages 提交给 QDMA。RTX 5070 Ti 的能力位为 0，程序会退出；更换 CUDA headers、Toolkit 或驱动分支不会把 capability 0 改为 1。

显存直通还要求 GPU 与 FPGA 位于兼容的 PCIe topology，IOMMU 使用 identity/pass-through，且 ACS 不强制 redirect。诊断时保存：

```bash
lspci -t
lspci -vv -s 01:00.0
lspci -vv -s 08:00.0
nvidia-smi topo -m
cat /proc/cmdline
```

## PS 监控

当前 bitstream 已包含由 Tcl 生成的 PS Block Design 和 HPM0 监控通路，但仓库尚未提供 PS 端 bare-metal/Linux 应用，也尚未生成可从启动介质加载的 `BOOT.BIN`。

- Host 可通过 QDMA BAR2 查看状态；
- PS 硬件通路已经位于设计中；
- PS 软件后续应轮询 `0xA000_0000` 的 design ID、DDR ready、scratch 和 ABI version；
- 生成 XSA 后，可使用 Vitis 或 PetaLinux 创建 PS 程序和 `BOOT.BIN`；
- PS 仅作监控，不应搬运 QDMA/GPU 数据。

## 冷启动后的恢复流程

当前 JTAG bitstream 不持久化。每次冷启动后按以下顺序恢复：

1. 用 `lspci` 确认启动介质中的 class `0604` switch 镜像；
2. 通过 JTAG 下载本仓库 `top.bit`；
3. 对旧 BDF 执行 PCI remove/rescan；
4. 确认设备变成 class `0580`、subsystem `10ee:0007`；
5. 加载 `qdma-pf`；
6. 建立 `qdma08000` queue 0；
7. 先运行 Host/DDR 回环，再运行 `gpu_staging_test`。

JTAG 下载完成并执行 remove/rescan 后无需热重启。只有 PCIe link 无法通过 remove/rescan 恢复时，才考虑重启主机；重启前必须确保 FPGA 能在 PCIe 枚举窗口之前保持正确配置，否则仍会回到旧 switch 镜像。

## 常见问题

### `lspci` 显示 `10ee:903f`，但没有 QDMA 设备

同时检查 PCI class。`0604` 是旧 switch/bridge 镜像；本仓库 QDMA 应是 `0580`。重新 JTAG 下载并 remove/rescan。

### 没有 `/dev/qdma*-MM-0`

依次检查 `lspci -k`、`lsmod | grep qdma`、`dma-ctl dev list`，然后运行 `host/setup_queues.sh`。仅加载驱动不会自动建立 MM queue。

### `prepare_driver.sh` 报缺少 `nv-p2p.h`

安装与正在运行的 NVIDIA 驱动完全匹配的 open kernel module 开发源码。不要使用另一版本的 headers 或 `nvidia-p2p.symvers`。

### `gpu_p2p_test` 报 GPU 不支持 GPUDirect RDMA

RTX 5070 Ti 上属于预期结果。使用 `gpu_staging_test`；若必须显存直通，需要更换明确支持 GPUDirect RDMA 且 capability 为 1 的 GPU。

### MIG calibration 失败

停止 QDMA/GPU 测试，先检查 bitstream 是否属于本仓库，并在 Vivado Hardware Manager 中查看 calibration stage 和错误信息。DDR 参数基线来自相邻 `ZYNQ-KV-ACCEL` 仓库中已通过实板验证的 TwinDie/clamshell 配置。

## 使用限制

- DDR offset 必须位于 `0..8 GiB-1`，并保证 `offset + length` 不越界；
- 显存直通 ioctl 单次长度上限为 `UINT_MAX`；
- CUDA buffer 生命周期必须覆盖传输，直通测试会启用 `CU_POINTER_ATTRIBUTE_SYNC_MEMOPS`；
- 当前启动介质尚未烧录本仓库镜像，冷启动仍需 JTAG；
- 当前 PS 只有硬件监控通路，没有配套软件与持久启动镜像。

## 参考资料

- [AMD/Xilinx QDMA reference driver](https://github.com/Xilinx/dma_ip_drivers)
- [NVIDIA GPUDirect RDMA documentation](https://docs.nvidia.com/cuda/gpudirect-rdma/)
- [CUDA Driver API](https://docs.nvidia.com/cuda/cuda-driver-api/)
