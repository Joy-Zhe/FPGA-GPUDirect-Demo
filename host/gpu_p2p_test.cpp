#include <cuda.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <cerrno>
#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "include/qdma_gpu_ioctl.h"

#define CU_OK(expr) do { CUresult r=(expr); if(r!=CUDA_SUCCESS){const char *s=nullptr;cuGetErrorString(r,&s);std::fprintf(stderr,"%s: %s\n",#expr,s?s:"CUDA error");return 1;}}while(0)

static int transfer(int fd, uint64_t gpu_address, uint64_t bytes, uint64_t ddr,
                    bool ddr_to_gpu) {
    qdma_gpu_xfer x{};
    x.gpu_address=gpu_address;
    x.flags=ddr_to_gpu?QDMA_GPU_F_DDR_TO_GPU:0;
    x.ddr_offset=ddr;
    x.length=bytes;
    if(ioctl(fd,QDMA_IOCTL_GPU_P2P_XFER,&x)<0){
        std::fprintf(stderr,"QDMA GPU ioctl: %s\n",std::strerror(errno));
        return -1;
    }
    if(x.transferred!=bytes){
        std::fprintf(stderr,"short QDMA transfer: %" PRIu64 "/%" PRIu64 "\n",
                     static_cast<uint64_t>(x.transferred),bytes);
        return -1;
    }
    return 0;
}

int main(int argc,char **argv){
    if(argc<2){std::fprintf(stderr,"usage: %s /dev/qdma*-MM-0 [MiB=64] [ddr_offset=0]\n",argv[0]);return 2;}
    uint64_t bytes=(argc>2?std::strtoull(argv[2],nullptr,0):64)*1024*1024;
    uint64_t ddr=argc>3?std::strtoull(argv[3],nullptr,0):0;
    constexpr uint64_t gpu_page=64*1024;
    bytes=(bytes+gpu_page-1)&~uint64_t(gpu_page-1);
    int qfd=open(argv[1],O_RDWR); if(qfd<0){std::perror("open queue");return 1;}
    CU_OK(cuInit(0)); CUdevice dev; CU_OK(cuDeviceGet(&dev,0));
    int gpudirect_rdma=0;
    CU_OK(cuDeviceGetAttribute(&gpudirect_rdma,
                               CU_DEVICE_ATTRIBUTE_GPU_DIRECT_RDMA_SUPPORTED,
                               dev));
    if(!gpudirect_rdma){
        std::fprintf(stderr,
                     "GPU does not report GPUDirect RDMA support; "
                     "nvidia_p2p_get_pages() cannot pin this allocation\n");
        close(qfd);
        return 3;
    }
    CUcontext ctx; CU_OK(cuDevicePrimaryCtxRetain(&ctx,dev)); CU_OK(cuCtxSetCurrent(ctx));
    CUdeviceptr allocation;
    CU_OK(cuMemAlloc(&allocation,bytes+gpu_page-1));
    CUdeviceptr gpu=(allocation+gpu_page-1)&~CUdeviceptr(gpu_page-1);
    std::fprintf(stderr,"CUDA allocation=0x%" PRIx64
                        ", aligned transfer address=0x%" PRIx64 "\n",
                 static_cast<uint64_t>(allocation),
                 static_cast<uint64_t>(gpu));
    unsigned sync=1;
    CU_OK(cuPointerSetAttribute(&sync,CU_POINTER_ATTRIBUTE_SYNC_MEMOPS,allocation));
    const unsigned pattern=0xa55a3cc3;
    CU_OK(cuMemsetD32(gpu,pattern,bytes/4)); CU_OK(cuCtxSynchronize());
    if(transfer(qfd,static_cast<uint64_t>(gpu),bytes,ddr,false)) return 1;
    CU_OK(cuMemsetD32(gpu,0,bytes/4)); CU_OK(cuCtxSynchronize());
    if(transfer(qfd,static_cast<uint64_t>(gpu),bytes,ddr,true)) return 1;
    CU_OK(cuCtxSynchronize());
    std::vector<unsigned> sample(bytes/sizeof(unsigned));
    CU_OK(cuMemcpyDtoH(sample.data(),gpu,sample.size()*sizeof(unsigned)));
    for(size_t i=0;i<sample.size();++i) if(sample[i]!=pattern){
        std::fprintf(stderr,"verify failed at word %zu: %08x != %08x\n",i,sample[i],pattern);return 1;
    }
    std::printf("PASS: GPU -> FPGA DDR -> GPU, %" PRIu64 " bytes at DDR 0x%" PRIx64 "\n",bytes,ddr);
    CU_OK(cuMemFree(allocation)); CU_OK(cuDevicePrimaryCtxRelease(dev)); close(qfd); return 0;
}
