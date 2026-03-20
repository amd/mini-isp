// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module isp_top #(

    // CFA orientation. CFA_BG=0, CFA_GB=1, CFA_GR=2, CFA_RG=3
    parameter CFA_ORIENTATION                     = 0,
    // Resolution. RES_2K=2048, RES_4K=4096, RES_8K=8192
    parameter MAX_RESOLUTION                      = 4096,
    // Pixel per cycle. 1, 2 or 4
    parameter PIXEL_PER_CYCLE                     = 4,
    // Pixel bit width. 8, 10, 12, 14, 16, 18
    parameter PIXEL_BIT_WIDTH                     = 12,
    // Output component bit width. 8
    parameter COMPONENT_BIT_WIDTH                 = 8,
    parameter S_AXI_DATA_WIDTH                    = 32,
    parameter S_AXI_ADDR_WIDTH                    = 5,
    parameter S_AXI_WSTRB_WIDTH                   = 4,
    parameter S_AXI_RRESP_WIDTH                   = 2,
    parameter S_AXI_BRESP_WIDTH                   = 2,
    parameter S_AXIS_DATA_WIDTH                   = 48,
    parameter M_AXIS_DATA_WIDTH                   = 96,
    parameter TUSER_WIDTH                         = 1,
    parameter DECOMPANDING_XLUT_FILE              = "decompanding_xlut.mem",
    parameter DECOMPANDING_YLUT_FILE              = "decompanding_ylut_12_bit.mem",
    parameter DECOMPANDING_FLUT_FILE              = "decompanding_flut_12_bit.mem",
    parameter DECOMPANDING_NUM_KNEE_POINTS        = 16,
    parameter GAMMA_LUT_FILE                      = "lut.mem"
  )
  (
    input  wire                           aclk,
    input  wire                           aresetn,

    // AXI Lite Register Interface
    input  wire [S_AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire                           s_axi_awvalid,
    output wire                           s_axi_awready,
    input  wire [S_AXI_DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [S_AXI_WSTRB_WIDTH-1:0]   s_axi_wstrb,
    input  wire                           s_axi_wvalid,
    output wire                           s_axi_wready,
    output wire [S_AXI_BRESP_WIDTH-1:0]   s_axi_bresp,
    output wire                           s_axi_bvalid,
    input  wire                           s_axi_bready,
    input  wire [S_AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire                           s_axi_arvalid,
    output wire                           s_axi_arready,
    output wire [S_AXI_DATA_WIDTH-1:0]    s_axi_rdata,
    output wire [S_AXI_RRESP_WIDTH-1:0]   s_axi_rresp,
    output wire                           s_axi_rvalid,
    input  wire                           s_axi_rready,

    input  wire  [S_AXIS_DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                           s_axis_tvalid,
    output wire                           s_axis_tready,
    input  wire                           s_axis_tlast,
    input  wire  [TUSER_WIDTH-1:0]        s_axis_tuser,

    output wire  [M_AXIS_DATA_WIDTH-1:0]  m_axis_tdata,
    output wire                           m_axis_tvalid,
    input  wire                           m_axis_tready,
    output wire                           m_axis_tlast,
    output wire  [TUSER_WIDTH-1:0]        m_axis_tuser
  );

  isp #(
      .CFA_ORIENTATION                (CFA_ORIENTATION),
      .MAX_RESOLUTION                 (MAX_RESOLUTION),
      .PIXEL_PER_CYCLE                (PIXEL_PER_CYCLE),
      .PIXEL_BIT_WIDTH                (PIXEL_BIT_WIDTH),
      .COMPONENT_BIT_WIDTH            (COMPONENT_BIT_WIDTH),
      .S_AXI_DATA_WIDTH               (S_AXI_DATA_WIDTH),
      .S_AXI_ADDR_WIDTH               (S_AXI_ADDR_WIDTH),
      .S_AXI_WSTRB_WIDTH              (S_AXI_WSTRB_WIDTH),
      .S_AXI_RRESP_WIDTH              (S_AXI_RRESP_WIDTH),
      .S_AXI_BRESP_WIDTH              (S_AXI_BRESP_WIDTH),
      .S_AXIS_DATA_WIDTH              (S_AXIS_DATA_WIDTH),
      .M_AXIS_DATA_WIDTH              (M_AXIS_DATA_WIDTH),
      .DECOMPANDING_XLUT_FILE         (DECOMPANDING_XLUT_FILE),
      .DECOMPANDING_YLUT_FILE         (DECOMPANDING_YLUT_FILE),
      .DECOMPANDING_FLUT_FILE         (DECOMPANDING_FLUT_FILE),
      .DECOMPANDING_NUM_KNEE_POINTS   (DECOMPANDING_NUM_KNEE_POINTS),
      .GAMMA_LUT_FILE                 (GAMMA_LUT_FILE)
  ) isp_int (
    .clk                      (aclk),
    .rstn                     (aresetn),

    .s_axi_awaddr             (s_axi_awaddr),
    .s_axi_awvalid            (s_axi_awvalid),
    .s_axi_awready            (s_axi_awready),
    .s_axi_wdata              (s_axi_wdata),
    .s_axi_wstrb              (s_axi_wstrb),
    .s_axi_wvalid             (s_axi_wvalid),
    .s_axi_wready             (s_axi_wready),
    .s_axi_bvalid             (s_axi_bvalid),
    .s_axi_bready             (s_axi_bready),
    .s_axi_araddr             (s_axi_araddr),
    .s_axi_arvalid            (s_axi_arvalid),
    .s_axi_arready            (s_axi_arready),
    .s_axi_rdata              (s_axi_rdata),
    .s_axi_rresp              (s_axi_rresp),
    .s_axi_rvalid             (s_axi_rvalid),
    .s_axi_rready             (s_axi_rready),
    .s_axi_bresp              (s_axi_bresp),

    .s_axis_tdata             (s_axis_tdata),
    .s_axis_tvalid            (s_axis_tvalid),
    .s_axis_tready            (s_axis_tready),
    .s_axis_tlast             (s_axis_tlast),
    .s_axis_tuser             (s_axis_tuser),

    .m_axis_tdata             (m_axis_tdata),
    .m_axis_tvalid            (m_axis_tvalid),
    .m_axis_tready            (m_axis_tready),
    .m_axis_tlast             (m_axis_tlast),
    .m_axis_tuser             (m_axis_tuser)
  );

endmodule
