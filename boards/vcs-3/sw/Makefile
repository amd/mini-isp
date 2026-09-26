# SPDX-FileCopyrightText: Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Timor Knudsen (AMD)
#
# SPDX-License-Identifier: MIT

SHELL := /bin/bash
.SHELLFLAGS := -e -o pipefail -c
.SILENT:
.NOTPARALLEL:

########################### User options ############################
BOARD               ?= vcs3_camera
TOPOLOGY            ?= baseline
VIVADO_PROJ_NAME    ?= proj_$(BOARD)_$(TOPOLOGY)
XSA                 ?= $(CURDIR)/../hw/build/$(VIVADO_PROJ_NAME)/$(VIVADO_PROJ_NAME).xsa
RELEASE             ?= rel-v2026.1
MANIFEST_URL        ?= https://github.com/Xilinx/yocto-manifests.git
SOC_FAMILY          ?= zynqmp
MACHINE_NAME        ?= $(SOC_FAMILY)-vcs3-sdt-$(TOPOLOGY)
IMAGE               ?= edf-linux-full-cmdline
VIVADO_SETTINGS     ?=
REPO_SYNC_JOBS      ?= 8
BB_TMPDIR           ?= /scratch/$(shell id -un)/yocto/$(BOARD)-$(TOPOLOGY)/tmp
#####################################################################

TOP          := $(CURDIR)
WORKDIR      := $(TOP)/yocto
BUILD_DIR    := $(WORKDIR)/build
SDT_DIR      := $(WORKDIR)/sdt
SETUPSDK     := $(WORKDIR)/edf-init-build-env
SDT_TOP      := $(SDT_DIR)/system-top.dts
MACHINE_CONF := $(BUILD_DIR)/conf/machine/$(MACHINE_NAME).conf
REPO         := $(WORKDIR)/.bin/repo
VCS3_LAYER   := $(TOP)/meta-vcs3

.PHONY: all help init repo sdt prepare machine build shell clean mrproper

all: build

repo: $(REPO)

$(REPO):
	mkdir -p "$(dir $(REPO))"
	curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$(REPO)"
	chmod a+x "$(REPO)"

init: $(SETUPSDK)

$(SETUPSDK): repo
	cd "$(WORKDIR)" && "$(REPO)" init -u $(MANIFEST_URL) -b $(RELEASE) -m default-edf.xml && "$(REPO)" sync -c -j$(REPO_SYNC_JOBS)

sdt: $(SDT_TOP)

$(SDT_TOP): $(XSA)
	mkdir -p "$(SDT_DIR)"
	$(if $(VIVADO_SETTINGS),source "$(VIVADO_SETTINGS)" && )sdtgen -xsa "$(XSA)" -dir "$(SDT_DIR)"

$(XSA):
	echo "ERROR: XSA not found: $@ (run: make -C ../hw xsa)" >&2 && exit 1

prepare: | init
	cd "$(WORKDIR)" && source ./edf-init-build-env 1>/dev/null && printf 'TMPDIR = "%s"\n' "$(BB_TMPDIR)" > "$(BUILD_DIR)/conf/auto.conf" && bitbake-layers add-layer "$(VCS3_LAYER)"

machine: $(MACHINE_CONF)

$(MACHINE_CONF): $(SDT_TOP) | prepare
	cd "$(WORKDIR)" && source ./edf-init-build-env 1>/dev/null && gen-machineconf parse-sdt --hw-description "$(SDT_DIR)" -c "$(BUILD_DIR)/conf" -l "$(BUILD_DIR)/conf/local.conf" --machine-name "$(MACHINE_NAME)"

build: machine
	cd "$(WORKDIR)" && source ./edf-init-build-env 1>/dev/null && bitbake $(IMAGE)
	echo "Images created in $(BB_TMPDIR)/deploy/images/$(MACHINE_NAME)"

shell: init
	cd "$(WORKDIR)" && source ./edf-init-build-env 1>/dev/null && exec "$${SHELL:-bash}"

clean: init
	cd "$(WORKDIR)" && source ./edf-init-build-env 1>/dev/null && bitbake -c cleansstate $(IMAGE)

mrproper:
	rm -rf "$(WORKDIR)"
	rm -rf "$(BB_TMPDIR)"

help:
	echo ""
	echo "Sundance VCS-3 Yocto build"
	echo ""
	echo "Targets:"
	grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'
	echo ""
