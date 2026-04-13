# Use NVIDIA CUDA 11.8 devel base image on Ubuntu 22.04
FROM nvidia/cuda:12.8.0-devel-ubuntu24.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-dev \
    python3-pip \
    git \
    build-essential \
    cmake \
    libegl-dev \
    libopengl-dev \
    libgmp-dev \
    libcgal-dev \
    libgl1 \
    libgles2-mesa-dev \
    ninja-build \
    libglib2.0-0 \
    libegl1-mesa-dev \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create symlink for python
RUN ln -s /usr/bin/python3 /usr/bin/python

# Set CUDA environment variables
ENV NVDIFRAST_BACKEND=cuda
ENV TORCH_CUDA_ARCH_LIST="12.0+PTX"
ENV PYTORCH_CUDA_ALLOC_CONF="expandable_segments:True,max_split_size_mb:32,garbage_collection_threshold:0.6"
ENV CUDA_DEVICE_MAX_CONNECTIONS=1
# Mesh regularization grid resolution scaling, smaller value saves VRAM
ENV MILO_MESH_RES_SCALE=0.3
# (Optional) Triangle chunk size to mitigate nvdiffrast CUDA backend VRAM peaks
ENV MILO_RAST_TRI_CHUNK=150000

# Set working directory
WORKDIR /workspace

# Install PyTorch 2.7.1 with CUDA 12.8 support
RUN pip install --break-system-packages torch==2.7.1 torchvision==0.22.1 torchaudio==2.7.1 --index-url https://download.pytorch.org/whl/cu128

# Install build dependencies
RUN pip install --break-system-packages ninja wheel packaging

# Copy requirements.txt and install
COPY requirements.txt .
RUN pip install --break-system-packages -r requirements.txt

# Additional dependencies
RUN pip install --break-system-packages \
    gradio==4.29.0 \
    gradio_imageslider \
    matplotlib \
    wandb \
    tensorboard \
    scipy \
    h5py \
    requests \
    torch_geometric \
    torch_cluster

ENV CPATH=/usr/local/cuda-12.8/targets/x86_64-linux/include:$CPATH
ENV LD_LIBRARY_PATH=/usr/local/cuda-12.8/targets/x86_64-linux/lib:$LD_LIBRARY_PATH
ENV PATH=/usr/local/cuda-12.8/bin:$PATH

# Copy the entire project
COPY . .

# Install submodules
RUN pip install --break-system-packages submodules/diff-gaussian-rasterization_ms
RUN pip install --break-system-packages submodules/diff-gaussian-rasterization
RUN pip install --break-system-packages submodules/diff-gaussian-rasterization_gof
RUN pip install --break-system-packages submodules/simple-knn
RUN pip install --break-system-packages submodules/fused-ssim

# Install C/C++ dependencies via apt (Ubuntu 24.04)
RUN apt update
RUN apt install -y \
    build-essential \
    cmake ninja-build \
    libgmp-dev libmpfr-dev libcgal-dev \
    libboost-all-dev

# Tetra-Nerf Triangulation
WORKDIR /workspace/submodules/tetra_triangulation
RUN rm -rf build CMakeCache.txt CMakeFiles tetranerf/utils/extension/tetranerf_cpp_extension*.so

# Point to current PyTorch's CMake prefix/dynamic library path
ENV CMAKE_PREFIX_PATH="$(python - <<'PY'import torch; print(torch.utils.cmake_prefix_path)PY)"
ENV TORCH_LIB_DIR="$(python - <<'PY'import os, torch; print(os.path.join(os.path.dirname(torch.__file__), 'lib'))PY)"
ENV LD_LIBRARY_PATH="$TORCH_LIB_DIR:$LD_LIBRARY_PATH"

RUN cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH" .
RUN cmake --build . -j"$(nproc)"
RUN pip install --break-system-packages -e .

WORKDIR /workspace

# Nvdiffrast
RUN pip install --break-system-packages -e submodules/nvdiffrast

# Set the default command to bash
CMD ["/bin/bash"]
