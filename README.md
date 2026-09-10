# QDMA + DDR4 + NVIDIA GPUDirect DMA demo

目标平台为 `XCZU19EG-FFVC1760-2-e`、PCIe Gen3 x16、Vivado 2024.1。设计提供：

- Host RAM 与 FPGA DDR4 间的双向 QDMA MM 传输；
- NVIDIA GPU DMA-BUF 与 FPGA DDR4 间的双向 PCIe P2P 传输；
- BAR2 状态寄存器（`0x00="QDMA"`、`0x04[0]=DDR calibration done`、`0x08=scratch`、`0x0c=version`）。

数据面不经过 Zynq PS。PS 适合板级管理，但加入 PCIe/DDR 数据面会增加跨域与仲裁开销；后续可把 PS 作为第二个 AXI master 接入 SmartConnect。

## 1. 构建 FPGA

在已加载 Vivado 2024.1 环境变量的 Windows 命令行中执行：

```tcl
cd E:/code/zynq_dma_ddr_demo
vivado -mode batch -source hw/scripts/build.tcl -tclargs synth
```

脚本从 `hw/ip` 中的三份 XCI 配置重建工程，并在 `build/vivado` 下生成全部派生文件。`axi_clock_converter_0` 负责 QDMA 250 MHz 与 MIG UI 300 MHz 的异步跨域。QDMA 地址的低 33 位映射到 8 GiB DDR 地址空间。当前约束已启用 x16；上板前必须按实际原理图复核高 8 lane、PCIe refclk、PERST# 和 DDR 全部管脚。

仓库只提交 RTL、XDC、自定义 DDR 器件表、XCI 和构建脚本；Vivado 工程、日志及 bitstream 均不提交。完整的复现与发布规则见 [`docs/reproducibility.md`](docs/reproducibility.md)。

## 2. Linux 驱动与队列

要求 Ubuntu 22.04.5、Linux 6.8 headers、CUDA Toolkit/driver，并建议 NVIDIA open kernel modules。准备与 Vivado 2024.1 对应的 QDMA 驱动：

```bash
sudo apt install build-essential git linux-headers-$(uname -r)
./host/prepare_driver.sh
make -C build/dma_ip_drivers/QDMA/linux-kernel/driver
make -C build/dma_ip_drivers/QDMA/linux-kernel/apps
sudo make -C build/dma_ip_drivers/QDMA/linux-kernel/driver install-mods
sudo modprobe qdma-pf
```

用 `dma-ctl dev list` 找到 FPGA 的 QDMA 设备名（例如 BDF `01:00.0` 对应常见名称 `qdma01000`），建立一对 MM 队列：

```bash
export PATH="$PWD/build/dma_ip_drivers/QDMA/linux-kernel/apps/dma-ctl:$PATH"
sudo --preserve-env=PATH ./host/setup_queues.sh qdma01000 0
ls -l /dev/qdma*-MM-0
```

普通 Host↾FPGA 测试可使用上游 `dma-to-device` / `dma-from-device` 应用，对同一 DDR offset 写入、读回并比较。

## 3. GPU P2P 测试

```bash
make -C host
sudo ./host/gpu_p2p_test /dev/qdma01000-MM-0 64 0
```

程序通过 CUDA Driver API 分配显存并导出 DMA-BUF FD；驱动补丁把 DMA-BUF attachment 的 DMA SG 地址直接提交给 QDMA，依次完成 GPU→DDR 和 DDR→GPU，再校验数据。ioctl 是阻塞式的，同一队列上的并发由调用方串行化。

## 4. P2P 平台检查

上板后保存以下输出：

```bash
lspci -t
lspci -vv -s <GPU-BDF>
lspci -vv -s <FPGA-BDF>
nvidia-smi topo -m
cat /proc/cmdline
```

GPU 与 FPGA 必须位于同一 PCIe root complex；仅经过同一 PCIe switch 最理想。IOMMU 必须关闭或使用 identity/pass-through，路径上的 ACS redirect 不能把 P2P 流量强制送回 Root Complex。BIOS 需启用 Above 4G Decoding。若程序报告不支持 DMA-BUF export，先检查 NVIDIA 驱动分支与 open kernel module，而不是回退到已进入弃用周期的 `nvidia_p2p_get_pages()` 路线。

参考资料：[AMD QDMA reference driver](https://github.com/Xilinx/dma_ip_drivers)、[NVIDIA GPUDirect RDMA documentation](https://docs.nvidia.com/cuda/gpudirect-rdma/)、[CUDA Driver API](https://docs.nvidia.com/cuda/cuda-driver-api/)。

## 已知边界

- 已在 Windows 上使用 Vivado 2024.1 完成综合；实现、时序收敛及真实 P2P 仍须在目标板卡和 Linux/GPU 环境验证。
- DDR offset 必须落在 `0..8 GiB-1`，单次 ioctl 最大 `UINT_MAX` 字节。
- CUDA buffer 生命周期必须覆盖 ioctl；测试程序已设置 `CU_POINTER_ATTRIBUTE_SYNC_MEMOPS` 并在传输前后同步 context。
