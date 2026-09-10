#!/usr/bin/env bash
set -euo pipefail
dev="${1:?usage: $0 qdmaDEVICE (for example qdma01000) [queue-index]}"
qid="${2:-0}"
dma-ctl "${dev}" q add idx "${qid}" mode mm dir bi
dma-ctl "${dev}" q start idx "${qid}" dir bi
dma-ctl "${dev}" q list
