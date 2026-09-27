# SPDX-FileCopyrightText: Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Brian Wiec (AMD)
# SPDX-FileCopyrightText: Copyright (c) 2026 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

PLATFORM ?= vcs3
VERSION ?= 2026_1
VER ?= 2026.1
BOARD ?= vcs3_camera
TOPOLOGY ?= baseline

ISP_DIR := ../../..
IP_DIR := ip
COMPONENT_XML := $(IP_DIR)/component.xml

VIVADO_PROJ_NAME ?= proj_$(BOARD)_$(TOPOLOGY)
PLATFORM_NAME := $(PLATFORM)_$(VERSION)
SYNTH_SRCS := tcl/$(BOARD)/bd.tcl \
		   xdc/

BUILD_DIR := build/$(VIVADO_PROJ_NAME)
PROJ_LOCKFILE=$(BUILD_DIR)/.lock
PROJ := $(BUILD_DIR)/$(VIVADO_PROJ_NAME).xpr
BITSTREAM := $(BUILD_DIR)/$(VIVADO_PROJ_NAME).runs/impl_1/design_1_wrapper.bit
XSA := $(BUILD_DIR)/$(VIVADO_PROJ_NAME).xsa

.SILENT:
.PHONY: all ip project bitstream xsa clean

all: ip project bitstream xsa

ip: $(COMPONENT_XML)
$(COMPONENT_XML): $(SYNTH_SRCS)
	cd $(ISP_DIR) && vivado -mode batch -notrace -source ./vivado/package.tcl -tclargs $(CURDIR)/$(IP_DIR)

project: ip $(PROJ_LOCKFILE)
$(PROJ_LOCKFILE): tcl/build_hardware.tcl $(SYNTH_SRCS)
	rm -rf $(BUILD_DIR); # If one of those files/directories changes, we need to re-build the vivado project since build_hardware.tcl isn't re-entrant
	mkdir -p $(BUILD_DIR)
	vivado -mode batch -notrace -source $< -tclargs $(VIVADO_PROJ_NAME) $(PLATFORM_NAME) $(VER) $(BOARD)
	touch $(PROJ_LOCKFILE)

bitstream: project $(BITSTREAM)
$(BITSTREAM): tcl/build_bitstream.tcl $(PROJ_LOCKFILE)
	vivado -mode batch -notrace -source $< -tclargs $(VIVADO_PROJ_NAME) $(PLATFORM_NAME) $(TOPOLOGY)

xsa: $(XSA) bitstream
$(XSA): tcl/export_hardware.tcl $(PDI)
	vivado -mode batch -notrace -source $< -tclargs $(VIVADO_PROJ_NAME)

clean:
	rm -rf vivado* build .Xil *dynamic* *.log *.xpe
	rm -rf $(IP_DIR)
