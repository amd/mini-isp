// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module isp
  #(
    // CFA orientation. CFA_BG=0, CFA_GB=1, CFA_GR=2, CFA_RG=3
    parameter CFA_ORIENTATION                     = 2,
    // Resolution. RES_2K=2048, RES_4K=4096, RES_8K=8192
    parameter MAX_RESOLUTION                      = 4096,
    // Pixel per cycle. 1, 2 or 4
    parameter PIXEL_PER_CYCLE                     = 2,
    // Pixel bit width. 8, 10, 12, 14, 16, 18
    parameter PIXEL_BIT_WIDTH                     = 12,
    // Output component bit width. 8
    parameter COMPONENT_BIT_WIDTH                 = 8,
    parameter S_AXI_DATA_WIDTH                    = 32,
    parameter S_AXI_ADDR_WIDTH                    = 5,
    parameter S_AXI_WSTRB_WIDTH                   = $rtoi($floor((S_AXI_DATA_WIDTH + 7)/8)),
    parameter S_AXI_RRESP_WIDTH                   = 2,
    parameter S_AXI_BRESP_WIDTH                   = 2,
    parameter S_AXIS_DATA_WIDTH                   = 8*$rtoi($floor((PIXEL_PER_CYCLE * PIXEL_BIT_WIDTH + 7)/8)),
    parameter M_AXIS_DATA_WIDTH                   = 8*$rtoi($floor((PIXEL_PER_CYCLE * 3 * COMPONENT_BIT_WIDTH + 7)/8)),
    parameter TUSER_WIDTH                         = 1,
    parameter DECOMPANDING_XLUT_FILE              = "../../rtl/decompanding_xlut.mem",
    parameter DECOMPANDING_YLUT_FILE              = "../../rtl/decompanding_ylut_12_bit.mem",
    parameter DECOMPANDING_FLUT_FILE              = "../../rtl/decompanding_flut_12_bit.mem",
    parameter DECOMPANDING_NUM_KNEE_POINTS        = 16,
    parameter GAMMA_LUT_FILE                      = "../../rtl/lut.mem"
  )
  (
    input  wire                           clk,
    input  wire                           rstn,

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

    // AXIS Video Sink
    input  wire  [S_AXIS_DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                           s_axis_tvalid,
    output wire                           s_axis_tready,
    input  wire                           s_axis_tlast,
    input  wire  [TUSER_WIDTH-1:0]        s_axis_tuser,

    // AXIS Video Source
    output wire  [M_AXIS_DATA_WIDTH-1:0]  m_axis_tdata,
    output wire                           m_axis_tvalid,
    input  wire                           m_axis_tready,
    output wire                           m_axis_tlast,
    output wire  [TUSER_WIDTH-1:0]        m_axis_tuser
  );

  wire [15:0]                     reg_black_level;
  wire [15:0]                     reg_rgain;
  wire [15:0]                     reg_bgain;
  wire [15:0]                     reg_g0gain;
  wire [15:0]                     reg_g1gain;
  wire [15:0]                     reg_ccm_r_r;
  wire [15:0]                     reg_ccm_r_g;
  wire [15:0]                     reg_ccm_r_b;
  wire [15:0]                     reg_ccm_g_r;
  wire [15:0]                     reg_ccm_g_g;
  wire [15:0]                     reg_ccm_g_b;
  wire [15:0]                     reg_ccm_b_r;
  wire [15:0]                     reg_ccm_b_g;
  wire [15:0]                     reg_ccm_b_b;

  axi_lite_register #(
    .S_AXI_DATA_WIDTH             (S_AXI_DATA_WIDTH),
    .S_AXI_ADDR_WIDTH             (S_AXI_ADDR_WIDTH),
    .S_AXI_WSTRB_WIDTH            (S_AXI_WSTRB_WIDTH),
    .S_AXI_RRESP_WIDTH            (S_AXI_RRESP_WIDTH),
    .S_AXI_BRESP_WIDTH            (S_AXI_BRESP_WIDTH)
  ) axi_lite_register_inst
  (
    .clk                          (clk),
    .rstn                         (rstn),

    .s_axi_awaddr                 (s_axi_awaddr),
    .s_axi_awvalid                (s_axi_awvalid),
    .s_axi_awready                (s_axi_awready),
    .s_axi_wdata                  (s_axi_wdata),
    .s_axi_wstrb                  (s_axi_wstrb),
    .s_axi_wvalid                 (s_axi_wvalid),
    .s_axi_wready                 (s_axi_wready),
    .s_axi_bresp                  (s_axi_bresp),
    .s_axi_bvalid                 (s_axi_bvalid),
    .s_axi_bready                 (s_axi_bready),
    .s_axi_araddr                 (s_axi_araddr),
    .s_axi_arvalid                (s_axi_arvalid),
    .s_axi_arready                (s_axi_arready),
    .s_axi_rdata                  (s_axi_rdata),
    .s_axi_rresp                  (s_axi_rresp),
    .s_axi_rvalid                 (s_axi_rvalid),
    .s_axi_rready                 (s_axi_rready),

    .black_level                  (reg_black_level),

    // format: UQ9.7
    .rgain                        (reg_rgain),
    .bgain                        (reg_bgain),
    .g0gain                       (reg_g0gain),
    .g1gain                       (reg_g1gain),

    // format: Q3.12
    .ccm_r_r                      (reg_ccm_r_r),
    .ccm_r_g                      (reg_ccm_r_g),
    .ccm_r_b                      (reg_ccm_r_b),
    .ccm_g_r                      (reg_ccm_g_r),
    .ccm_g_g                      (reg_ccm_g_g),
    .ccm_g_b                      (reg_ccm_g_b),
    .ccm_b_r                      (reg_ccm_b_r),
    .ccm_b_g                      (reg_ccm_b_g),
    .ccm_b_b                      (reg_ccm_b_b)
  );

  localparam BLC_PIXEL_BIT_WIDTH          = PIXEL_BIT_WIDTH;
  localparam BLC_DATA_WIDTH               = 8*$rtoi($floor((PIXEL_PER_CYCLE * BLC_PIXEL_BIT_WIDTH + 7)/8));

  wire [BLC_DATA_WIDTH-1:0]               blc_tdata;
  wire                                    blc_tvalid;
  wire                                    blc_tready;
  wire                                    blc_tlast;
  wire [TUSER_WIDTH-1:0]                  blc_tuser;

  blc #(
    .PIXEL_PER_CYCLE                      (PIXEL_PER_CYCLE),
    .PIXEL_BIT_WIDTH                      (BLC_PIXEL_BIT_WIDTH)
  ) blc_inst
  (
    .clk                                  (clk),
    .rstn                                 (rstn),

    .black_level                          (reg_black_level),

    .s_axis_tdata                         (s_axis_tdata),
    .s_axis_tvalid                        (s_axis_tvalid),
    .s_axis_tready                        (s_axis_tready),
    .s_axis_tlast                         (s_axis_tlast),
    .s_axis_tuser                         (s_axis_tuser),

    .m_axis_tdata                         (blc_tdata),
    .m_axis_tvalid                        (blc_tvalid),
    .m_axis_tready                        (blc_tready),
    .m_axis_tlast                         (blc_tlast),
    .m_axis_tuser                         (blc_tuser)
  );

  localparam COLORGAIN_PIXEL_BIT_WIDTH    = BLC_PIXEL_BIT_WIDTH;
  localparam COLORGAIN_DATA_WIDTH         = 8*$rtoi($floor((PIXEL_PER_CYCLE * COLORGAIN_PIXEL_BIT_WIDTH + 7)/8));

  wire [COLORGAIN_DATA_WIDTH-1:0]         colorgain_tdata;
  wire                                    colorgain_tvalid;
  wire                                    colorgain_tready;
  wire                                    colorgain_tlast;
  wire [TUSER_WIDTH-1:0]                  colorgain_tuser;

  colorgain #(
    .CFA_ORIENTATION                      (CFA_ORIENTATION),
    .PIXEL_PER_CYCLE                      (PIXEL_PER_CYCLE),
    .PIXEL_BIT_WIDTH                      (COLORGAIN_PIXEL_BIT_WIDTH)
  ) colorgain_inst
  (
    .clk                                  (clk),
    .rstn                                 (rstn),

    // format: Q9.7
    .rgain                                (reg_rgain),
    .bgain                                (reg_bgain),
    .g0gain                               (reg_g0gain),
    .g1gain                               (reg_g1gain),

    .s_axis_tdata                         (blc_tdata),
    .s_axis_tvalid                        (blc_tvalid),
    .s_axis_tready                        (blc_tready),
    .s_axis_tlast                         (blc_tlast),
    .s_axis_tuser                         (blc_tuser),

    .m_axis_tdata                         (colorgain_tdata),
    .m_axis_tvalid                        (colorgain_tvalid),
    .m_axis_tready                        (colorgain_tready),
    .m_axis_tlast                         (colorgain_tlast),
    .m_axis_tuser                         (colorgain_tuser)
  );

  wire [COLORGAIN_DATA_WIDTH-1:0]         skidbuffer1_tdata;
  wire                                    skidbuffer1_tvalid;
  wire                                    skidbuffer1_tready;
  wire                                    skidbuffer1_tlast;
  wire [TUSER_WIDTH-1:0]                  skidbuffer1_tuser;

  skidbuffer #(
    .DATA_WIDTH                           (COLORGAIN_DATA_WIDTH)
  ) skidbuffer1_inst
  (
    .clk                                  (clk),
    .rstn                                 (rstn),

    .s_axis_tdata                         (colorgain_tdata),
    .s_axis_tvalid                        (colorgain_tvalid),
    .s_axis_tready                        (colorgain_tready),
    .s_axis_tlast                         (colorgain_tlast),
    .s_axis_tuser                         (colorgain_tuser),

    .m_axis_tdata                         (skidbuffer1_tdata),
    .m_axis_tvalid                        (skidbuffer1_tvalid),
    .m_axis_tready                        (skidbuffer1_tready),
    .m_axis_tlast                         (skidbuffer1_tlast),
    .m_axis_tuser                         (skidbuffer1_tuser)
  );

  localparam DEMOSAIC_PIXEL_BIT_WIDTH     = COLORGAIN_PIXEL_BIT_WIDTH;
  localparam DEMOSAIC_DATA_BIT_WIDTH      = 8*$rtoi($floor((PIXEL_PER_CYCLE * 3 * DEMOSAIC_PIXEL_BIT_WIDTH + 7)/8));

  wire [DEMOSAIC_DATA_BIT_WIDTH-1:0]      demosaic_tdata;
  wire                                    demosaic_tvalid;
  wire                                    demosaic_tready;
  wire                                    demosaic_tlast;
  wire [TUSER_WIDTH-1:0]                  demosaic_tuser;

  demosaic #(
    .CFA_ORIENTATION                      (CFA_ORIENTATION),
    .MAX_RESOLUTION                       (MAX_RESOLUTION),
    .PIXEL_PER_CYCLE                      (PIXEL_PER_CYCLE),
    .PIXEL_BIT_WIDTH                      (DEMOSAIC_PIXEL_BIT_WIDTH)
  ) demosaic_inst
  (
    .clk                                  (clk),
    .rstn                                 (rstn),

    .s_axis_tdata                         (skidbuffer1_tdata),
    .s_axis_tvalid                        (skidbuffer1_tvalid),
    .s_axis_tready                        (skidbuffer1_tready),
    .s_axis_tlast                         (skidbuffer1_tlast),
    .s_axis_tuser                         (skidbuffer1_tuser),

    .m_axis_tdata                         (demosaic_tdata),
    .m_axis_tvalid                        (demosaic_tvalid),
    .m_axis_tready                        (demosaic_tready),
    .m_axis_tlast                         (demosaic_tlast),
    .m_axis_tuser                         (demosaic_tuser)
  );

  localparam CCM_COMPONENT_BIT_WIDTH      = DEMOSAIC_PIXEL_BIT_WIDTH;
  localparam CCM_S_AXIS_DATA_BIT_WIDTH    = 8*$rtoi($floor((PIXEL_PER_CYCLE * 3 * CCM_COMPONENT_BIT_WIDTH + 7)/8));
  localparam CCM_M_AXIS_DATA_BIT_WIDTH    = 8*$rtoi($floor((PIXEL_PER_CYCLE * 3 * CCM_COMPONENT_BIT_WIDTH + 7)/8));

  wire [CCM_M_AXIS_DATA_BIT_WIDTH-1:0]    ccm_tdata;
  wire                                    ccm_tvalid;
  wire                                    ccm_tready;
  wire                                    ccm_tlast;
  wire [TUSER_WIDTH-1:0]                  ccm_tuser;

  ccm #(
    .PIXEL_PER_CYCLE                      (PIXEL_PER_CYCLE),
    .COMPONENT_BIT_WIDTH                  (CCM_COMPONENT_BIT_WIDTH),
    .S_AXIS_DATA_WIDTH                    (CCM_S_AXIS_DATA_BIT_WIDTH),
    .M_AXIS_DATA_WIDTH                    (CCM_M_AXIS_DATA_BIT_WIDTH)
  ) ccm_inst
  (
    .clk                                  (clk),
    .rstn                                 (rstn),

    .ccm_r_r                              (reg_ccm_r_r),
    .ccm_r_g                              (reg_ccm_r_g),
    .ccm_r_b                              (reg_ccm_r_b),
    .ccm_g_r                              (reg_ccm_g_r),
    .ccm_g_g                              (reg_ccm_g_g),
    .ccm_g_b                              (reg_ccm_g_b),
    .ccm_b_r                              (reg_ccm_b_r),
    .ccm_b_g                              (reg_ccm_b_g),
    .ccm_b_b                              (reg_ccm_b_b),

    .s_axis_tdata                         (demosaic_tdata),
    .s_axis_tvalid                        (demosaic_tvalid),
    .s_axis_tready                        (demosaic_tready),
    .s_axis_tlast                         (demosaic_tlast),
    .s_axis_tuser                         (demosaic_tuser),

    .m_axis_tdata                         (ccm_tdata),
    .m_axis_tvalid                        (ccm_tvalid),
    .m_axis_tready                        (ccm_tready),
    .m_axis_tlast                         (ccm_tlast),
    .m_axis_tuser                         (ccm_tuser)
  );

  wire [CCM_M_AXIS_DATA_BIT_WIDTH-1:0]    skidbuffer2_tdata;
  wire                                    skidbuffer2_tvalid;
  wire                                    skidbuffer2_tready;
  wire                                    skidbuffer2_tlast;
  wire [TUSER_WIDTH-1:0]                  skidbuffer2_tuser;

  skidbuffer #(
    .DATA_WIDTH                           (CCM_M_AXIS_DATA_BIT_WIDTH)
  ) skidbuffer2_inst
  (
    .clk                                   (clk),
    .rstn                                  (rstn),

    .s_axis_tdata                          (ccm_tdata),
    .s_axis_tvalid                         (ccm_tvalid),
    .s_axis_tready                         (ccm_tready),
    .s_axis_tlast                          (ccm_tlast),
    .s_axis_tuser                          (ccm_tuser),

    .m_axis_tdata                          (skidbuffer2_tdata),
    .m_axis_tvalid                         (skidbuffer2_tvalid),
    .m_axis_tready                         (skidbuffer2_tready),
    .m_axis_tlast                          (skidbuffer2_tlast),
    .m_axis_tuser                          (skidbuffer2_tuser)
  );

  localparam GAMMA_INPUT_PIXEL_BIT_WIDTH  = CCM_COMPONENT_BIT_WIDTH;
  localparam GAMMA_OUTPUT_PIXEL_BIT_WIDTH = COMPONENT_BIT_WIDTH;
  localparam GAMMA_S_AXIS_DATA_BIT_WIDTH  = 8*$rtoi($floor((PIXEL_PER_CYCLE * 3 * GAMMA_INPUT_PIXEL_BIT_WIDTH + 7)/8));
  localparam GAMMA_M_AXIS_DATA_BIT_WIDTH  = 8*$rtoi($floor((PIXEL_PER_CYCLE * 3 * GAMMA_OUTPUT_PIXEL_BIT_WIDTH + 7)/8));

  wire [GAMMA_M_AXIS_DATA_BIT_WIDTH-1:0]  gamma_tdata;
  wire                                    gamma_tvalid;
  wire                                    gamma_tready;
  wire                                    gamma_tlast;
  wire [TUSER_WIDTH-1:0]                  gamma_tuser;

  gamma #(
    .PIXEL_PER_CYCLE                      (PIXEL_PER_CYCLE),
    .INPUT_COMPONENT_BIT_WIDTH            (GAMMA_INPUT_PIXEL_BIT_WIDTH),
    .OUTPUT_COMPONENT_BIT_WIDTH           (GAMMA_OUTPUT_PIXEL_BIT_WIDTH),
    .LUT_FILE                             (GAMMA_LUT_FILE)
  ) gamma_inst
  (
    .clk                                  (clk),
    .rstn                                 (rstn),

    .s_axis_tdata                         (skidbuffer2_tdata),
    .s_axis_tvalid                        (skidbuffer2_tvalid),
    .s_axis_tready                        (skidbuffer2_tready),
    .s_axis_tlast                         (skidbuffer2_tlast),
    .s_axis_tuser                         (skidbuffer2_tuser),

    .m_axis_tdata                         (gamma_tdata),
    .m_axis_tvalid                        (gamma_tvalid),
    .m_axis_tready                        (gamma_tready),
    .m_axis_tlast                         (gamma_tlast),
    .m_axis_tuser                         (gamma_tuser)
  );

  wire [GAMMA_M_AXIS_DATA_BIT_WIDTH-1:0]  skidbuffer3_tdata;
  wire                                    skidbuffer3_tvalid;
  wire                                    skidbuffer3_tready;
  wire                                    skidbuffer3_tlast;
  wire [TUSER_WIDTH-1:0]                  skidbuffer3_tuser;

  skidbuffer #(
    .DATA_WIDTH                           (GAMMA_M_AXIS_DATA_BIT_WIDTH)
  ) skidbuffer3_inst
  (
    .clk                                   (clk),
    .rstn                                  (rstn),

    .s_axis_tdata                          (gamma_tdata),
    .s_axis_tvalid                         (gamma_tvalid),
    .s_axis_tready                         (gamma_tready),
    .s_axis_tlast                          (gamma_tlast),
    .s_axis_tuser                          (gamma_tuser),

    .m_axis_tdata                          (skidbuffer3_tdata),
    .m_axis_tvalid                         (skidbuffer3_tvalid),
    .m_axis_tready                         (skidbuffer3_tready),
    .m_axis_tlast                          (skidbuffer3_tlast),
    .m_axis_tuser                          (skidbuffer3_tuser)
  );

  assign skidbuffer3_tready = m_axis_tready;

  assign m_axis_tdata       = skidbuffer3_tdata;
  assign m_axis_tvalid      = skidbuffer3_tvalid;
  assign m_axis_tlast       = skidbuffer3_tlast;
  assign m_axis_tuser       = skidbuffer3_tuser;

endmodule
