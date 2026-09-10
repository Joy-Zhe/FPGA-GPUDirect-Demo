#ifndef QDMA_GPU_IOCTL_H
#define QDMA_GPU_IOCTL_H
#include <linux/ioctl.h>
#include <linux/types.h>

#define QDMA_GPU_F_DDR_TO_GPU (1U << 0)
struct qdma_gpu_xfer {
    __s32 dma_buf_fd;
    __u32 flags;
    __u64 dma_buf_offset;
    __u64 ddr_offset;
    __u64 length;
    __u64 transferred;
};
#define QDMA_IOCTL_GPU_XFER _IOWR('q', 0xf0, struct qdma_gpu_xfer)
#endif
