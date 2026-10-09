# SPDX-FileCopyrightText: Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

SUMMARY = "VCS-3 demo files"
DESCRIPTION = "Installs VCS-3 camera ingress demo script."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://vcs3-demo \
    file://vcs3-cam \
    file://vcs3-demo.service \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_SERVICE:${PN} = "vcs3-demo.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${S}/vcs3-demo ${D}${bindir}/vcs3-demo
    install -m 0755 ${S}/vcs3-cam ${D}${bindir}/vcs3-cam
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/vcs3-demo.service ${D}${systemd_system_unitdir}/vcs3-demo.service
}

FILES:${PN} = " \
    ${bindir}/vcs3-demo \
    ${bindir}/vcs3-cam \
    ${systemd_system_unitdir}/vcs3-demo.service \
"
