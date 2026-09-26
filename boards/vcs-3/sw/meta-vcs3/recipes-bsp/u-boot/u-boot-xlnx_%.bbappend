# SPDX-FileCopyrightText: Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

FILESEXTRAPATHS:append := "${THISDIR}/files"
SRC_URI:append = " file://user.cfg"
SRC_URI:remove = "${EDF_BOOTCMD_CFG}"
