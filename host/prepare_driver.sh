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
echo "Patched driver: $dst/QDMA/linux-kernel/driver"
echo "Build with: make -C $dst/QDMA/linux-kernel/driver"
