REPO_ROOT := $(abspath ..)
LOCAL_CUDA_HOME := $(REPO_ROOT)/build/cuda-13.2-local/usr/local/cuda-13.2/targets/x86_64-linux
CUDA_HOME ?= $(if $(wildcard /usr/local/cuda/include/cuda.h),/usr/local/cuda,$(LOCAL_CUDA_HOME))
CUDA_LIBDIR := $(if $(wildcard $(CUDA_HOME)/lib64),$(CUDA_HOME)/lib64,$(CUDA_HOME)/lib)
CXX ?= g++
CXXFLAGS += -O2 -std=c++17 -Wall -Wextra -I$(CUDA_HOME)/include
LDLIBS += -L$(CUDA_LIBDIR) -lcuda
all: gpu_p2p_test gpu_staging_test
gpu_p2p_test: gpu_p2p_test.cpp include/qdma_gpu_ioctl.h
	$(CXX) $(CXXFLAGS) -o $@ gpu_p2p_test.cpp $(LDLIBS)
gpu_staging_test: gpu_staging_test.cpp
	$(CXX) $(CXXFLAGS) -o $@ gpu_staging_test.cpp $(LDLIBS)
clean:
	rm -f gpu_p2p_test gpu_staging_test
