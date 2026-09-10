CUDA_HOME ?= /usr/local/cuda
CXX ?= g++
CXXFLAGS += -O2 -std=c++17 -Wall -Wextra -I$(CUDA_HOME)/include
LDLIBS += -L$(CUDA_HOME)/lib64 -lcuda
all: gpu_p2p_test
gpu_p2p_test: gpu_p2p_test.cpp include/qdma_gpu_ioctl.h
	$(CXX) $(CXXFLAGS) -o $@ gpu_p2p_test.cpp $(LDLIBS)
clean:
	rm -f gpu_p2p_test
