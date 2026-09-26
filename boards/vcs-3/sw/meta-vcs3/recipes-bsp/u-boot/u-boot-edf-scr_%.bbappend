# SPDX-FileCopyrightText: Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

SRC_URI:append = " file://edf-linux-full-cmdline-mmc-boot.cmd"
FILESEXTRAPATHS:append := ":${THISDIR}/files"

do_compile:append() {
    mkimage -A arm -T script -C none -n "Linux Boot script" -d "${WORKDIR}/edf-linux-full-cmdline-mmc-boot.cmd" boot.scr
}
