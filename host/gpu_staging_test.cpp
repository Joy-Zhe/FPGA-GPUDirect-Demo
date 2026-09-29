#include <cuda.h>

#include <fcntl.h>
#include <unistd.h>

#include <chrono>
#include <cinttypes>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#define CU_OK(expr)                                                            \
    do {                                                                       \
        CUresult result = (expr);                                              \
        if (result != CUDA_SUCCESS) {                                          \
            const char *message = nullptr;                                    \
            cuGetErrorString(result, &message);                               \
            std::fprintf(stderr, "%s: %s\n", #expr,                         \
                         message ? message : "CUDA error");                  \
            return 1;                                                          \
        }                                                                      \
    } while (0)

using Clock = std::chrono::steady_clock;

static double elapsed_seconds(Clock::time_point start, Clock::time_point end) {
    return std::chrono::duration<double>(end - start).count();
}

static double gib_per_second(uint64_t bytes, double seconds) {
    return static_cast<double>(bytes) / (1024.0 * 1024.0 * 1024.0) / seconds;
}

static int qdma_transfer(int fd, void *buffer, uint64_t bytes, uint64_t offset,
                         bool device_to_host) {
    auto *cursor = static_cast<unsigned char *>(buffer);
    uint64_t completed = 0;

    while (completed < bytes) {
        off_t position = static_cast<off_t>(offset + completed);
        if (lseek(fd, position, SEEK_SET) != position) {
            std::perror("lseek QDMA queue");
            return -1;
        }

        size_t remaining = static_cast<size_t>(bytes - completed);
        ssize_t result;
        do {
            result = device_to_host ? read(fd, cursor + completed, remaining)
                                    : write(fd, cursor + completed, remaining);
        } while (result < 0 && errno == EINTR);

        if (result < 0) {
            std::perror(device_to_host ? "read QDMA queue"
                                       : "write QDMA queue");
            return -1;
        }
        if (result == 0) {
            std::fprintf(stderr, "QDMA transfer stopped after %" PRIu64
                                 " of %" PRIu64 " bytes\n",
                         completed, bytes);
            return -1;
        }
        completed += static_cast<uint64_t>(result);
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        std::fprintf(stderr,
                     "usage: %s /dev/qdma*-MM-0 [MiB=64] [ddr_offset=0]\n",
                     argv[0]);
        return 2;
    }

    uint64_t mebibytes = argc > 2 ? std::strtoull(argv[2], nullptr, 0) : 64;
    uint64_t bytes = mebibytes * 1024 * 1024;
    uint64_t ddr_offset = argc > 3 ? std::strtoull(argv[3], nullptr, 0) : 0;
    if (bytes == 0 || bytes > static_cast<uint64_t>(SIZE_MAX)) {
        std::fprintf(stderr, "invalid transfer size\n");
        return 2;
    }

    int queue = open(argv[1], O_RDWR);
    if (queue < 0) {
        std::perror("open QDMA queue");
        return 1;
    }

    CU_OK(cuInit(0));
    CUdevice device;
    CU_OK(cuDeviceGet(&device, 0));
    char device_name[128] = {};
    CU_OK(cuDeviceGetName(device_name, sizeof(device_name), device));
    CUcontext context;
    CU_OK(cuDevicePrimaryCtxRetain(&context, device));
    CU_OK(cuCtxSetCurrent(context));

    CUdeviceptr gpu_buffer;
    CU_OK(cuMemAlloc(&gpu_buffer, static_cast<size_t>(bytes)));
    void *staging = nullptr;
    CU_OK(cuMemHostAlloc(&staging, static_cast<size_t>(bytes),
                         CU_MEMHOSTALLOC_PORTABLE));

    std::vector<unsigned char> expected(static_cast<size_t>(bytes));
    for (uint64_t i = 0; i < bytes; ++i) {
        expected[static_cast<size_t>(i)] =
            static_cast<unsigned char>((i * 131u + (i >> 8) * 17u + 0x5au) &
                                       0xffu);
    }

    CU_OK(cuMemcpyHtoD(gpu_buffer, expected.data(), static_cast<size_t>(bytes)));
    CU_OK(cuCtxSynchronize());

    auto gpu_to_host_start = Clock::now();
    CU_OK(cuMemcpyDtoH(staging, gpu_buffer, static_cast<size_t>(bytes)));
    CU_OK(cuCtxSynchronize());
    auto gpu_to_host_end = Clock::now();

    auto host_to_ddr_start = Clock::now();
    if (qdma_transfer(queue, staging, bytes, ddr_offset, false) != 0) {
        return 1;
    }
    auto host_to_ddr_end = Clock::now();

    std::memset(staging, 0, static_cast<size_t>(bytes));
    CU_OK(cuMemsetD8(gpu_buffer, 0, static_cast<size_t>(bytes)));
    CU_OK(cuCtxSynchronize());

    auto ddr_to_host_start = Clock::now();
    if (qdma_transfer(queue, staging, bytes, ddr_offset, true) != 0) {
        return 1;
    }
    auto ddr_to_host_end = Clock::now();

    auto host_to_gpu_start = Clock::now();
    CU_OK(cuMemcpyHtoD(gpu_buffer, staging, static_cast<size_t>(bytes)));
    CU_OK(cuCtxSynchronize());
    auto host_to_gpu_end = Clock::now();

    std::memset(staging, 0, static_cast<size_t>(bytes));
    CU_OK(cuMemcpyDtoH(staging, gpu_buffer, static_cast<size_t>(bytes)));
    CU_OK(cuCtxSynchronize());

    const auto *actual = static_cast<const unsigned char *>(staging);
    for (uint64_t i = 0; i < bytes; ++i) {
        if (actual[i] != expected[static_cast<size_t>(i)]) {
            std::fprintf(stderr,
                         "verify failed at byte %" PRIu64 ": %02x != %02x\n",
                         i, actual[i], expected[static_cast<size_t>(i)]);
            return 1;
        }
    }

    double gpu_to_host = elapsed_seconds(gpu_to_host_start, gpu_to_host_end);
    double host_to_ddr = elapsed_seconds(host_to_ddr_start, host_to_ddr_end);
    double ddr_to_host = elapsed_seconds(ddr_to_host_start, ddr_to_host_end);
    double host_to_gpu = elapsed_seconds(host_to_gpu_start, host_to_gpu_end);
    double round_trip = gpu_to_host + host_to_ddr + ddr_to_host + host_to_gpu;

    std::printf("PASS: GPU <-> pinned host memory <-> FPGA DDR\n");
    std::printf("GPU: %s\n", device_name);
    std::printf("Bytes: %" PRIu64 ", DDR offset: 0x%" PRIx64 "\n", bytes,
                ddr_offset);
    std::printf("GPU -> pinned host: %.3f GiB/s (%.3f ms)\n",
                gib_per_second(bytes, gpu_to_host), gpu_to_host * 1000.0);
    std::printf("Pinned host -> DDR: %.3f GiB/s (%.3f ms)\n",
                gib_per_second(bytes, host_to_ddr), host_to_ddr * 1000.0);
    std::printf("DDR -> pinned host: %.3f GiB/s (%.3f ms)\n",
                gib_per_second(bytes, ddr_to_host), ddr_to_host * 1000.0);
    std::printf("Pinned host -> GPU: %.3f GiB/s (%.3f ms)\n",
                gib_per_second(bytes, host_to_gpu), host_to_gpu * 1000.0);
    std::printf("Pipeline round trip: %.3f GiB/s effective (%.3f ms)\n",
                gib_per_second(bytes * 2, round_trip), round_trip * 1000.0);

    CU_OK(cuMemFreeHost(staging));
    CU_OK(cuMemFree(gpu_buffer));
    CU_OK(cuDevicePrimaryCtxRelease(device));
    close(queue);
    return 0;
}
