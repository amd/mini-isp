# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

set VLNV_VENDOR {AMD.COM}
set VLNV_LIBRARY {ip}
set VLNV_NAME {mini_isp}
set VLNV_VERSION {0.1}

set REVISION {1}

set TOP_LEVEL_NAME {isp_top}

set TOP_LEVEL_CLOCK {aclk}

# Set sources, top level first
set SOURCES_LIST {
    ./rtl/isp_top.v
    ./rtl/isp.sv
    ./rtl/histogram_stretch.sv
    ./rtl/histogram_scale.sv
    ./rtl/histogram_offsetgain.sv
    ./rtl/histogram_minmax2.sv
    ./rtl/non_restoring_unsigned_divider.sv
    ./rtl/gamma.sv
    ./rtl/gamma_gain.mem
    ./rtl/gamma_offset.mem
    ./rtl/lut.sv
    ./rtl/lut.mem
    ./rtl/axi_lite_register.sv
    ./rtl/ccm.sv
    ./rtl/pwl.sv
    ./rtl/bitsqrt.sv
    ./rtl/bitsqrt.mem
    ./rtl/bitlog.sv
    ./rtl/bitlog.mem
    ./rtl/simple_dual_ported_rom.mem
    ./rtl/simple_dual_ported_rom.sv
    ./rtl/demosaic.sv
    ./rtl/linebuffer.sv
    ./rtl/simple_dual_ported_ram.sv
    ./rtl/colorgain.sv
    ./rtl/blc.sv
    ./rtl/decompanding_xlut.mem
    ./rtl/decompanding_xlut_short.mem
    ./rtl/decompanding_ylut_12_bit.mem
    ./rtl/decompanding_flut.mem
    ./rtl/decompanding_flut_12_bit.mem
    ./rtl/decompanding_flut_short.mem
    ./rtl/decompanding.sv
    ./rtl/skidbuffer.sv
}

create_project -ip -in_memory

ipx::create_core $VLNV_VENDOR $VLNV_LIBRARY $VLNV_NAME $VLNV_VERSION

set_property display_name "Mini ISP" [ipx::current_core]
set_property description "The Minimal Image Signal Processor (ISP)" [ipx::current_core]
set_property supported_families {spartanuplus Pre-Production artix7 Pre-Production artix7l Pre-Production artixuplus Pre-Production qartix7 Pre-Production qkintex7 Pre-Production qkintex7l Pre-Production kintexu Pre-Production kintexuplus Pre-Production versal Pre-Production qvirtex7 Pre-Production virtexuplus Pre-Production virtexuplusHBM Pre-Production qzynq Pre-Production zynquplus Pre-Production kintex7 Pre-Production kintex7l Pre-Production spartan7 Pre-Production virtex7 Pre-Production virtexu Pre-Production virtexuplus58g Pre-Production aartix7 Pre-Production akintex7 Pre-Production aspartan7 Pre-Production azynq Pre-Production zynq Pre-Production} [ipx::current_core]
set_property taxonomy $VLNV_LIBRARY [ipx::current_core]

set_property core_revision $REVISION [ipx::current_core]

set_property ipi_drc {ignore_freq_hz true} [ipx::current_core]

# Add file groups
set sources [ipx::add_file_group -type synthesis "sources" [ipx::current_core]]
set_property model_name $TOP_LEVEL_NAME $sources

# Set top level
ipx::import_top_level_hdl -top_level_hdl_file [lindex $SOURCES_LIST 0] -verbose [ipx::current_core]

# add all files from sources list
foreach file $SOURCES_LIST {
    ipx::add_file $file $sources
}

# Infer bus interfaces. TODO: maybe do this manually!
ipx::infer_bus_interfaces

# manually assign the correct clock to all AXI interfaces
ipx::associate_bus_interfaces -busif s_axi -clock $TOP_LEVEL_CLOCK [ipx::current_core]
ipx::associate_bus_interfaces -busif s_axis -clock $TOP_LEVEL_CLOCK [ipx::current_core]
ipx::associate_bus_interfaces -busif m_axis -clock $TOP_LEVEL_CLOCK [ipx::current_core]

# TODO: Proper address map
ipx::infer_memory_address_block [ipx::get_bus_interfaces s_axi]
set_property name Reg [ipx::get_address_blocks reg0 -of_objects [ipx::get_memory_maps s_axi -of_objects [ipx::current_core]]]
set_property display_name Reg [ipx::get_address_blocks Reg -of_objects [ipx::get_memory_maps s_axi -of_objects [ipx::current_core]]]

# Set CLK bus parameter
#ipx::add_bus_parameter FREQ_HZ [ipx::get_bus_interfaces clk -of_objects [ipx::current_core]]
#set_property description 250 [ipx::get_bus_parameters FREQ_HZ -of_objects [ipx::get_bus_interfaces clk -of_objects [ipx::current_core]]]

# import generics and parameters
ipx::add_model_parameters_from_hdl -ordered_files [lindex $SOURCES_LIST 0] -top_module_name $TOP_LEVEL_NAME [ipx::current_core]
ipx::infer_user_parameters [ipx::current_core]

# COMPONENT_BIT_WIDTH
ipgui::add_param -name {COMPONENT_BIT_WIDTH} -component [ipx::current_core] -display_name {Output Component Bit Width} -show_label {true} -show_range {true} -widget {comboBox}
set_property tooltip {Bits per output component} [ipgui::get_guiparamspec -name "COMPONENT_BIT_WIDTH" -component [ipx::current_core] ]
set_property value 8 [ipx::get_user_parameters COMPONENT_BIT_WIDTH -of_objects [ipx::current_core]]
set_property value 8 [ipx::get_hdl_parameters COMPONENT_BIT_WIDTH -of_objects [ipx::current_core]]
set_property value_validation_type list [ipx::get_user_parameters COMPONENT_BIT_WIDTH -of_objects [ipx::current_core]]
set_property value_validation_list {8 10 12 14} [ipx::get_user_parameters COMPONENT_BIT_WIDTH -of_objects [ipx::current_core]]

# CFA_ORIENTATION
ipgui::add_param -name {CFA_ORIENTATION} -component [ipx::current_core] -display_name {CFA Orientation} -show_label {true} -show_range {true} -widget {comboBox}
set_property tooltip {Color filter array ordering} [ipgui::get_guiparamspec -name "CFA_ORIENTATION" -component [ipx::current_core] ]
set_property value 0 [ipx::get_user_parameters CFA_ORIENTATION -of_objects [ipx::current_core]]
set_property value 0 [ipx::get_hdl_parameters CFA_ORIENTATION -of_objects [ipx::current_core]]
set_property value_validation_type pairs [ipx::get_user_parameters CFA_ORIENTATION -of_objects [ipx::current_core]]
set_property value_validation_pairs {BG-GR 0 GB-RG 1 GR-BG 2 RG-GB 3} [ipx::get_user_parameters CFA_ORIENTATION -of_objects [ipx::current_core]]

# PIXEL_PER_CYCLE
ipgui::add_param -name {PIXEL_PER_CYCLE} -component [ipx::current_core] -display_name {Pixel Per Cycle} -show_label {true} -show_range {true} -widget {comboBox}
set_property tooltip {Number of pixels that are processed per cycle} [ipgui::get_guiparamspec -name "PIXEL_PER_CYCLE" -component [ipx::current_core] ]
set_property value 4 [ipx::get_user_parameters PIXEL_PER_CYCLE -of_objects [ipx::current_core]]
set_property value 4 [ipx::get_hdl_parameters PIXEL_PER_CYCLE -of_objects [ipx::current_core]]
set_property value_validation_type list [ipx::get_user_parameters PIXEL_PER_CYCLE -of_objects [ipx::current_core]]
set_property value_validation_list {1 2 4} [ipx::get_user_parameters PIXEL_PER_CYCLE -of_objects [ipx::current_core]]

# PIXEL_BIT_WIDTH
ipgui::add_param -name {PIXEL_BIT_WIDTH} -component [ipx::current_core] -display_name {Pixel Bit Width} -show_label {true} -show_range {true} -widget {comboBox}
set_property tooltip {Input pixel bit width} [ipgui::get_guiparamspec -name "PIXEL_BIT_WIDTH" -component [ipx::current_core] ]
set_property widget {comboBox} [ipgui::get_guiparamspec -name "PIXEL_BIT_WIDTH" -component [ipx::current_core] ]
set_property value 12 [ipx::get_user_parameters PIXEL_BIT_WIDTH -of_objects [ipx::current_core]]
set_property value 12 [ipx::get_hdl_parameters PIXEL_BIT_WIDTH -of_objects [ipx::current_core]]
set_property value_validation_type list [ipx::get_user_parameters PIXEL_BIT_WIDTH -of_objects [ipx::current_core]]
set_property value_validation_list {12 14 16 18 20 22 24} [ipx::get_user_parameters PIXEL_BIT_WIDTH -of_objects [ipx::current_core]]

# MAX_RESOLUTION
ipgui::add_param -name {MAX_RESOLUTION} -component [ipx::current_core] -display_name {Max Horizontal Resolution} -show_label {true} -show_range {true} -widget {comboBox}
set_property tooltip {Maximum line length for line buffers} [ipgui::get_guiparamspec -name "MAX_RESOLUTION" -component [ipx::current_core] ]
set_property value 4096 [ipx::get_user_parameters MAX_RESOLUTION -of_objects [ipx::current_core]]
set_property value 4096 [ipx::get_hdl_parameters MAX_RESOLUTION -of_objects [ipx::current_core]]
set_property value_validation_type list [ipx::get_user_parameters MAX_RESOLUTION -of_objects [ipx::current_core]]
set_property value_validation_list {1024 2048 4096} [ipx::get_user_parameters MAX_RESOLUTION -of_objects [ipx::current_core]]

# DECOMPANDING_XLUT_FILE (hidden)
set_property value decompanding_xlut.mem [ipx::get_user_parameters DECOMPANDING_XLUT_FILE -of_objects [ipx::current_core]]
set_property value decompanding_xlut.mem [ipx::get_hdl_parameters DECOMPANDING_XLUT_FILE -of_objects [ipx::current_core]]
set_property enablement_value false [ipx::get_user_parameters DECOMPANDING_XLUT_FILE -of_objects [ipx::current_core]]

# DECOMPANDING_YLUT_FILE (hidden)
set_property value decompanding_ylut_12_bit.mem [ipx::get_user_parameters DECOMPANDING_YLUT_FILE -of_objects [ipx::current_core]]
set_property value decompanding_ylut_12_bit.mem [ipx::get_hdl_parameters DECOMPANDING_YLUT_FILE -of_objects [ipx::current_core]]
set_property enablement_value false [ipx::get_user_parameters DECOMPANDING_YLUT_FILE -of_objects [ipx::current_core]]

# DECOMPANDING_FLUT_FILE (hidden)
set_property value decompanding_flut_12_bit.mem [ipx::get_user_parameters DECOMPANDING_FLUT_FILE -of_objects [ipx::current_core]]
set_property value decompanding_flut_12_bit.mem [ipx::get_hdl_parameters DECOMPANDING_FLUT_FILE -of_objects [ipx::current_core]]
set_property enablement_value false [ipx::get_user_parameters DECOMPANDING_FLUT_FILE -of_objects [ipx::current_core]]

# DECOMPANDING_NUM_KNEE_POINTS (hidden)
set_property value 16 [ipx::get_user_parameters DECOMPANDING_NUM_KNEE_POINTS -of_objects [ipx::current_core]]
set_property value 16 [ipx::get_hdl_parameters DECOMPANDING_NUM_KNEE_POINTS -of_objects [ipx::current_core]]
set_property enablement_value false [ipx::get_user_parameters DECOMPANDING_NUM_KNEE_POINTS -of_objects [ipx::current_core]]

# GAMMA_LUT_FILE (hidden)
set_property value lut.mem [ipx::get_user_parameters GAMMA_LUT_FILE -of_objects [ipx::current_core]]
set_property value lut.mem [ipx::get_hdl_parameters GAMMA_LUT_FILE -of_objects [ipx::current_core]]
set_property enablement_value false [ipx::get_user_parameters GAMMA_LUT_FILE -of_objects [ipx::current_core]]

# S_AXI_RRESP_WIDTH (hidden)
set_property value 2 [ipx::get_user_parameters S_AXI_RRESP_WIDTH -of_objects [ipx::current_core]]
set_property value 2 [ipx::get_hdl_parameters S_AXI_RRESP_WIDTH -of_objects [ipx::current_core]]
set_property enablement_value false [ipx::get_user_parameters S_AXI_RRESP_WIDTH -of_objects [ipx::current_core]]

# S_AXI_BRESP_WIDTH (hidden)
set_property value 2 [ipx::get_user_parameters S_AXI_BRESP_WIDTH -of_objects [ipx::current_core]]
set_property value 2 [ipx::get_hdl_parameters S_AXI_BRESP_WIDTH -of_objects [ipx::current_core]]
set_property enablement_value false [ipx::get_user_parameters S_AXI_BRESP_WIDTH -of_objects [ipx::current_core]]

# S_AXI_DATA_WIDTH (hidden)
set_property value 32 [ipx::get_user_parameters S_AXI_DATA_WIDTH -of_objects [ipx::current_core]]
set_property value 32 [ipx::get_hdl_parameters S_AXI_DATA_WIDTH -of_objects [ipx::current_core]]
set_property enablement_value false [ipx::get_user_parameters S_AXI_DATA_WIDTH -of_objects [ipx::current_core]]

# S_AXI_ADDR_WIDTH (hidden)
set_property value 5 [ipx::get_user_parameters S_AXI_ADDR_WIDTH -of_objects [ipx::current_core]]
set_property value 5 [ipx::get_hdl_parameters S_AXI_ADDR_WIDTH -of_objects [ipx::current_core]]
set_property enablement_value false [ipx::get_user_parameters S_AXI_ADDR_WIDTH -of_objects [ipx::current_core]]

# S_AXI_WSTRB_WIDTH (auto-derived, hidden from GUI)
set_property value 4 [ipx::get_user_parameters S_AXI_WSTRB_WIDTH -of_objects [ipx::current_core]]
set_property value 4 [ipx::get_hdl_parameters S_AXI_WSTRB_WIDTH -of_objects [ipx::current_core]]
set_property enablement_value false [ipx::get_user_parameters S_AXI_WSTRB_WIDTH -of_objects [ipx::current_core]]
set_property value_tcl_expr {$S_AXI_DATA_WIDTH / 8} [ipx::get_user_parameters S_AXI_WSTRB_WIDTH -of_objects [ipx::current_core]]

# TUSER_WIDTH (hidden)
set_property value 1 [ipx::get_user_parameters TUSER_WIDTH -of_objects [ipx::current_core]]
set_property value 1 [ipx::get_hdl_parameters TUSER_WIDTH -of_objects [ipx::current_core]]
set_property enablement_value false [ipx::get_user_parameters TUSER_WIDTH -of_objects [ipx::current_core]]

# M_AXIS_DATA_WIDTH (auto-derived, hidden from GUI)
set_property value 96 [ipx::get_user_parameters M_AXIS_DATA_WIDTH -of_objects [ipx::current_core]]
set_property value 96 [ipx::get_hdl_parameters M_AXIS_DATA_WIDTH -of_objects [ipx::current_core]]
set_property enablement_value false [ipx::get_user_parameters M_AXIS_DATA_WIDTH -of_objects [ipx::current_core]]
set_property value_tcl_expr {8*floor(($PIXEL_PER_CYCLE * 3 * $COMPONENT_BIT_WIDTH + 7) / 8)} [ipx::get_user_parameters M_AXIS_DATA_WIDTH -of_objects [ipx::current_core]]

# S_AXIS_DATA_WIDTH (auto-derived, hidden from GUI)
set_property value 48 [ipx::get_user_parameters S_AXIS_DATA_WIDTH -of_objects [ipx::current_core]]
set_property value 48 [ipx::get_hdl_parameters S_AXIS_DATA_WIDTH -of_objects [ipx::current_core]]
set_property enablement_value false [ipx::get_user_parameters S_AXIS_DATA_WIDTH -of_objects [ipx::current_core]]
set_property value_tcl_expr {8*floor(($PIXEL_PER_CYCLE * $PIXEL_BIT_WIDTH + 7) / 8)} [ipx::get_user_parameters S_AXIS_DATA_WIDTH -of_objects [ipx::current_core]]

# Update dependencies
ipx::update_dependency [ipx::get_user_parameters CFA_ORIENTATION -of_objects [ipx::current_core]]
ipx::update_dependency [ipx::get_user_parameters MAX_RESOLUTION -of_objects [ipx::current_core]]
ipx::update_dependency [ipx::get_user_parameters PIXEL_PER_CYCLE -of_objects [ipx::current_core]]
ipx::update_dependency [ipx::get_user_parameters PIXEL_BIT_WIDTH -of_objects [ipx::current_core]]
ipx::update_dependency [ipx::get_user_parameters COMPONENT_BIT_WIDTH -of_objects [ipx::current_core]]
ipx::update_dependency [ipx::get_user_parameters S_AXI_DATA_WIDTH -of_objects [ipx::current_core]]
ipx::update_dependency [ipx::get_user_parameters S_AXI_ADDR_WIDTH -of_objects [ipx::current_core]]
ipx::update_dependency [ipx::get_user_parameters S_AXI_WSTRB_WIDTH -of_objects [ipx::current_core]]
ipx::update_dependency [ipx::get_user_parameters S_AXI_RRESP_WIDTH -of_objects [ipx::current_core]]
ipx::update_dependency [ipx::get_user_parameters S_AXI_BRESP_WIDTH -of_objects [ipx::current_core]]
ipx::update_dependency [ipx::get_user_parameters S_AXIS_DATA_WIDTH -of_objects [ipx::current_core]]
ipx::update_dependency [ipx::get_user_parameters M_AXIS_DATA_WIDTH -of_objects [ipx::current_core]]
ipx::update_dependency [ipx::get_user_parameters TUSER_WIDTH -of_objects [ipx::current_core]]

# Create GUI structure
ipgui::add_group -name {input} -component [ipx::current_core] -parent [ipgui::get_pagespec -name "Page 0" -component [ipx::current_core] ] -display_name {Input}
ipgui::add_static_text -name {input_text} -component [ipx::current_core] -parent [ipgui::get_groupspec -name "input" -component [ipx::current_core] ] -text {Please select the raw data input configuration.}
ipgui::move_param -component [ipx::current_core] -order 1 [ipgui::get_guiparamspec -name "PIXEL_BIT_WIDTH" -component [ipx::current_core]] -parent [ipgui::get_groupspec -name "input" -component [ipx::current_core]]
ipgui::move_param -component [ipx::current_core] -order 2 [ipgui::get_guiparamspec -name "CFA_ORIENTATION" -component [ipx::current_core]] -parent [ipgui::get_groupspec -name "input" -component [ipx::current_core]]

ipgui::add_group -name {performance} -component [ipx::current_core] -parent [ipgui::get_pagespec -name "Page 0" -component [ipx::current_core] ] -display_name {Performance}
ipgui::add_static_text -name {performance_text} -component [ipx::current_core] -parent [ipgui::get_groupspec -name "performance" -component [ipx::current_core] ] -text {Performance parameters such as pixel per cycle and horizontal resolution.}
ipgui::move_param -component [ipx::current_core] -order 1 [ipgui::get_guiparamspec -name "PIXEL_PER_CYCLE" -component [ipx::current_core]] -parent [ipgui::get_groupspec -name "performance" -component [ipx::current_core]]
ipgui::move_param -component [ipx::current_core] -order 2 [ipgui::get_guiparamspec -name "MAX_RESOLUTION" -component [ipx::current_core]] -parent [ipgui::get_groupspec -name "performance" -component [ipx::current_core]]

ipgui::add_group -name {output} -component [ipx::current_core] -parent [ipgui::get_pagespec -name "Page 0" -component [ipx::current_core] ] -display_name {Output}
ipgui::add_static_text -name {output_text} -component [ipx::current_core] -parent [ipgui::get_groupspec -name "output" -component [ipx::current_core] ] -text {Output configuration. For RGB888, select 8 bit component bit width.}
ipgui::move_param -component [ipx::current_core] -order 1 [ipgui::get_guiparamspec -name "COMPONENT_BIT_WIDTH" -component [ipx::current_core]] -parent [ipgui::get_groupspec -name "output" -component [ipx::current_core]]

# Set names
set_property display_name {Configuration} [ipgui::get_pagespec -name "Page 0" -component [ipx::current_core] ]
set_property tooltip {Mini-ISP User Configuration} [ipgui::get_pagespec -name "Page 0" -component [ipx::current_core] ]

# GUI
ipx::create_xgui_files [ipx::current_core]
ipx::create_default_gui_files [ipx::current_core ]

ipx::check_integrity [ipx::current_core]
ipx::update_checksums [ipx::current_core]
ipx::save_core [ipx::current_core]

close_project
