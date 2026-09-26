# SPDX-FileCopyrightText: Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Brian Wiec (AMD)
# SPDX-FileCopyrightText: Copyright (c) 2026 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

########### User Options ############
export BOARD ?= vcs3_camera
export PLNX_TMPDIR ?=
#####################################

export VIVADO_PROJ_NAME = proj_$(BOARD)_$(TOPOLOGY)
PLATFORM = vcs3
VERSION  = 2026_1
VER      = 2026.1
TOPOLOGY := baseline

.PHONY: all
all: xsa ## Builds entire vision hub firmware package

.PHONY: check_env
check_env:
ifneq ($(TOPOLOGY), $(filter $(TOPOLOGY), baseline))
	$(error TOPOLOGY is $(TOPOLOGY) but must be one of: baseline)
endif

ifneq ($(BOARD), $(filter $(BOARD), vcs3_camera))
	$(error BOARD is $(BOARD) but must be one of: vcs3_camera)
endif

VIVADO_BUILD_DIR := $(CWD)/hw/build/$(VIVADO_PROJ_NAME)
VIVADO_LOCKFILE := $(VIVADO_BUILD_DIR)/.lock
.PHONY: hw
hw: $(VIVADO_LOCKFILE) check_env ## Generate Vivado project
$(VIVADO_LOCKFILE): $(MAKE_CONFIG_FILE)
	$(MAKE) -C hw project

BITSTREAM := $(VIVADO_BUILD_DIR)/$(VIVADO_PROJ_NAME).runs/impl_1/design_1_wrapper.bit
.PHONY: bitstream
bitstream: hw $(BITSTREAM) ## Run Vivado implementation to generate bitstream
$(BITSTREAM): $(VIVADO_LOCKFILE)
	$(MAKE) -C hw bitstream

XSA := $(VIVADO_BUILD_DIR)/$(VIVADO_PROJ_NAME).xsa
.PHONY: xsa
xsa: $(XSA) bitstream ## Export hardware to generate XSA file
$(XSA): $(VIVADO_LOCKFILE)
	$(MAKE) -C hw xsa

.PHONY: open_hw_gui
open_hw_gui: hw ## Open Vivado project GUI for debugging
	$(MAKE) -C hw open_proj_gui

.PHONY: clean_hw
clean_hw: ## Clean Vivado build
	$(MAKE) -C hw clean

.PHONY: clean
clean: clean_hw  ## Clean everything

DATE := $(shell date +%Y_%m_%d)
.PHONY: archive
archive: clean ## Create a .zip of this project
	$(eval HASH=$(shell git rev-parse --short=7 HEAD))
	cd ..
	zip -r $(DATE)_$(PLATFORM).$(HASH).zip $(PLATFORM) \
		-x $(shell basename $(CWD))/.vscode/\*

.PHONY: help
help: ## Print this message
	echo ""
	echo "vcs3_camera - Sundance VCS-3 reference platform enabling MIPI cameras"
	echo ""
	echo "Environment Variables"
	printf "\033[31m%44s\033[0m - %s\n" "baseline" "Baseline camera display"

	echo ""
	echo "Targets"
	grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
	echo ""
