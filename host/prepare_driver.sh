#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
dst="${1:-$root/build/dma_ip_drivers}"
if [[ ! -d "$dst/.git" ]]; then
  git clone https://github.com/Xilinx/dma_ip_drivers.git "$dst"
fi
git -C "$dst" fetch origin
git -C "$dst" checkout --detach 3cf1905
git -C "$dst" reset --hard 3cf1905
git -C "$dst" apply --recount "$root/host/qdma-gpudirect.patch"
if [[ ! -f /usr/src/nvidia-595.91.07/nvidia-peermem/nv-p2p.h ]]; then
  echo "Missing NVIDIA nvidia-peermem headers; install the matching NVIDIA driver development sources" >&2
  exit 1
fi
mkdir -p "$root/build"
cp "$root/host/nvidia-p2p.symvers" "$root/build/nvidia-p2p.symvers"
echo "Patched driver: $dst/QDMA/linux-kernel/driver"
echo "Build with: NVIDIA_P2P_INCLUDE=/usr/src/nvidia-595.91.07/nvidia-peermem make -C $dst/QDMA/linux-kernel/driver modulesymfile=Module.symvers extra_symb=$root/build/nvidia-p2p.symvers"
