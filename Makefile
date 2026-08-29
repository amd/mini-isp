# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

.PHONY: all sim synth test docs lint clean help

BUILD_DIR := build
CACHE_DIR := .cache

# Can be default, simfast, full, minimal
SIM_SPEED ?= simfast

# Can be default, simfast, full, minimal
SYNTH_SPEED ?= simfast

# Default target
all: lint test synth sim

# Run Verilator RTL test benches
sim:
	uv run pytest python/tb -m sim --speed $(SIM_SPEED)

# Run Yosys synthesis and generate utilization reports
synth:
	uv run pytest python/tb -m synth --speed $(SYNTH_SPEED)

# Run Python tests
test:
	uv run pytest python/test

# Generate documentation (inluding utilization reports)
docs:
	cp -rf docs $(BUILD_DIR)
	uv run zensical build --clean

# Run lint on all files
lint:
	uv run prek run --all-files

# Clean all build artifacts
clean:
	rm -rf $(BUILD_DIR)
	rm -rf $(CACHE_DIR)
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete

# Display help information
help:
	@echo "Mini-ISP Makefile targets:"
	@echo "  make sim    - Run the Verilator test benches"
	@echo "  make synth  - Run the Yosys synthesis"
	@echo "  make test   - Run the Python tests"
	@echo "  make lint   - Run lint on all files"
	@echo "  make clean  - Clean all build artifacts"
	@echo "  make all    - Run lint, test, synth, and sim (default)"
	@echo "  make help   - Display this help message"
