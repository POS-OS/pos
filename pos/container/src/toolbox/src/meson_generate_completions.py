#!/usr/bin/env python3
#
# Copyright © 2022 Ondřej Míchal
# Copyright © 2022 – 2026 Red Hat Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

import os
import subprocess
import sys

if len(sys.argv) != 3:
    print('{}: wrong arguments'.format(sys.argv[0]), file=sys.stderr)
    print('Usage: {} [SOURCE DIR] [COMPLETION TYPE]'.format(sys.argv[0]), file=sys.stderr)
    sys.exit(1)

source_dir = sys.argv[1]
completion_type = sys.argv[2]

os.chdir(source_dir)

# Note for distributors:
#
# The '-z now' flag, which is the opposite of '-z lazy', is unsupported as an
# external linker flag [1], because of how the NVIDIA Container Toolkit stack
# uses dlopen(3) to load libcuda.so.1 and libnvidia-ml.so.1 at runtime [2,3].
#
# The NVIDIA Container Toolkit stack doesn't use dlsym(3) to obtain the address
# of a symbol at runtime before using it.  It links against undefined symbols
# at build-time available through a CUDA API definition embedded directly in
# the CGO code or a copy of nvml.h.  It relies upon lazily deferring function
# call resolution to the point when dlopen(3) is able to load the shared
# libraries at runtime, instead of doing it when toolbox(1) is started.
#
# This is unlike how Toolbx itself uses dlopen(3) and dlsym(3) to load
# libsubid.so at runtime.
#
# Compare the output of:
#   $ nm /path/to/toolbox | grep ' subid_init'
#
# ... with those from:
#   $ nm /path/to/toolbox | grep ' nvmlGpuInstanceGetComputeInstanceProfileInfoV'
#           U nvmlGpuInstanceGetComputeInstanceProfileInfoV
#   $ nm /path/to/toolbox | grep ' nvmlDeviceGetAccountingPids'
#           U nvmlDeviceGetAccountingPids
#
# Using '-z now' as an external linker flag forces the dynamic linker to
# resolve all symbols when toolbox(1) is started, and leads to:
#   $ toolbox
#   toolbox: symbol lookup error: toolbox: undefined symbol:
#       nvmlGpuInstanceGetComputeInstanceProfileInfoV
#
# [1] NVIDIA Container Toolkit commit 1407ace94ab7c150
#     https://github.com/NVIDIA/nvidia-container-toolkit/commit/1407ace94ab7c150
#     https://github.com/NVIDIA/go-nvml/issues/18
#     https://github.com/NVIDIA/nvidia-container-toolkit/issues/49
#
# [2] https://github.com/NVIDIA/nvidia-container-toolkit/tree/main/internal/cuda
#
# [3] https://github.com/NVIDIA/go-nvml/blob/main/README.md
#     https://github.com/NVIDIA/go-nvml/tree/main/pkg/dl
#     https://github.com/NVIDIA/go-nvml/tree/main/pkg/nvml

output = subprocess.run(['go', 'run', '-ldflags', '-extldflags "-Wl,-z,lazy"', '.', 'completion', completion_type],
                        check=True)

sys.exit(0)
