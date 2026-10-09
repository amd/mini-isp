# SPDX-FileCopyrightText: Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

SUMMARY = "Mini-ISP V4L2 subdevice driver"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

inherit module

FILESEXTRAPATHS:prepend := "${THISDIR}/../../../../../../drivers/linux:"
SRC_URI = "file://mini-isp"

S = "${WORKDIR}/mini-isp"

RPROVIDES:${PN} += "kernel-module-mini-isp"
