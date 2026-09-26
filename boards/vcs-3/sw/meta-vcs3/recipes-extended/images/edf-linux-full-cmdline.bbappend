# SPDX-FileCopyrightText: Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

IMAGE_FSTYPES += " wic wic.xz"
WKS_FILES = "edf-disk-single-rootfs.wks"

IMAGE_INSTALL:append = " v4l-utils"
IMAGE_INSTALL:append = " libv4l"
IMAGE_INSTALL:append = " media-ctl"
IMAGE_INSTALL:append = " libdrm"
IMAGE_INSTALL:append = " libdrm-tests"
IMAGE_INSTALL:append = " libdrm-dev"
IMAGE_INSTALL:append = " packagegroup-xilinx-gstreamer"
IMAGE_INSTALL:append = " devmem2"
IMAGE_INSTALL:append = " u-boot-edf-scr"
IMAGE_INSTALL:append = " vcs3-files"
IMAGE_INSTALL:append = " openssh"
IMAGE_INSTALL:append = " i2c-tools"
IMAGE_INSTALL:append = " htop"
IMAGE_INSTALL:append = " nano"
