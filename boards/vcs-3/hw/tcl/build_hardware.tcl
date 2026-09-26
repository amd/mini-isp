# SPDX-FileCopyrightText: Copyright (c) 2026 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2026 Brian Wiec (AMD)
# SPDX-FileCopyrightText: Copyright (c) 2026 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

set proj_name [lindex $argv 0]
set PLATFORM_NAME [lindex $argv 1]
set VER [lindex $argv 2]
set BOARD [lindex $argv 3]

#-----------------------------------------------------------
# Abort if design already exists
#-----------------------------------------------------------
if { [file exists ${proj_name}] == 1 } {
	puts "Aborting. Project already exists"
	exit -1
}

#-----------------------------------------------------------
# Create project
#-----------------------------------------------------------
if { ${BOARD} == "vcs3_camera" } {
	create_project ${proj_name} "build/${proj_name}" -part xczu3eg-ubva530-2L-e
} else {
	puts "ERROR! Unsupported board"
	exit -1
}

#-----------------------------------------------------------
# Add HDL source to design
#-----------------------------------------------------------
import_files -quiet -fileset sources_1 "rtl"

#-----------------------------------------------------------
# Add xdc constraints to design
#-----------------------------------------------------------
import_files -quiet -norecurse -fileset constrs_1 "xdc"

#-----------------------------------------------------------
# Add IP to design
#-----------------------------------------------------------
set_property  ip_repo_paths  {ip ./ip} [current_project]
update_ip_catalog

#-----------------------------------------------------------
# Create BD source
#-----------------------------------------------------------
source "tcl/${BOARD}/bd.tcl"

#-----------------------------------------------------------
# Update some platform properties
#-----------------------------------------------------------
set_property PFM_NAME "xilinx:${BOARD}:${PLATFORM_NAME}:${VER}" [get_files [current_bd_design].bd]
validate_bd_design
save_bd_design

#-----------------------------------------------------------
# Generate BD output products
#-----------------------------------------------------------
generate_target all [get_files "build/${proj_name}/${proj_name}.srcs/sources_1/bd/design_1/design_1.bd"]
make_wrapper -files [get_files "build/${proj_name}/${proj_name}.srcs/sources_1/bd/design_1/design_1.bd"] -top
import_files -force -norecurse "build/${proj_name}/${proj_name}.srcs/sources_1/bd/design_1/hdl/design_1_wrapper.v"
set_property top "top" [current_fileset]

exit
