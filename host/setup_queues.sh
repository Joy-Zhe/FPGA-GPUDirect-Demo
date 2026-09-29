#!/usr/bin/env bash
set -euo pipefail
dev="${1:?usage: $0 qdmaDEVICE (for example qdma01000) [queue-index]}"
qid="${2:-0}"
dev_line="$(dma-ctl dev list 2>/dev/null || true)"
pci_bdf="$(awk -v dev="$dev" '$1 == dev { print $2 }' <<<"$dev_line")"
if [[ -z "$pci_bdf" ]]; then
    echo "QDMA device not found: $dev" >&2
    exit 1
fi
qmax_file="/sys/bus/pci/devices/$pci_bdf/qdma/qmax"
if [[ "$(<"$qmax_file")" == 0 ]]; then
    if (( EUID != 0 )); then
        echo "run as root to allocate a QDMA queue pair" >&2
        exit 1
    fi
    echo 1 >"$qmax_file"
fi
dma-ctl "${dev}" q add idx "${qid}" mode mm dir bi
dma-ctl "${dev}" q start idx "${qid}" dir bi
dma-ctl "${dev}" q list "${qid}" 1
