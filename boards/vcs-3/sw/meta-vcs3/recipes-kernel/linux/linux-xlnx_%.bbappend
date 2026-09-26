# SPDX-FileCopyrightText: Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://vcs3-kernel.cfg"

SRC_URI += "file://0001-Add-OV5647-1924x1084-mode.patch"
