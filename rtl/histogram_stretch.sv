// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module histogram_stretch
  #(
    // Pixel per cycle. 1, 2 or 4
    parameter PIXEL_PER_CYCLE                     = 2,
    // Pixel bit width. 10, 12, 14, 16, 18, 20, 22, 24
    parameter INPUT_BIT_WIDTH                     = 24,
    parameter OUTPUT_BIT_WIDTH                    = 8,
    parameter S_AXIS_DATA_WIDTH                   = 8*$rtoi($floor((PIXEL_PER_CYCLE * 3 * INPUT_BIT_WIDTH + 7)/8)),
    parameter M_AXIS_DATA_WIDTH                   = 8*$rtoi($floor((PIXEL_PER_CYCLE * 3 * OUTPUT_BIT_WIDTH + 7)/8)),
    parameter TUSER_WIDTH                         = 1
  )
  (
    input  wire                           clk,
    input  wire                           rstn,

    input  wire  [31:0]                   force_tmin,
    input  wire  [31:0]                   force_tmax,

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

  wire [INPUT_BIT_WIDTH-1:0]        minmax_tmin;
  wire [INPUT_BIT_WIDTH-1:0]        minmax_tmax;
  wire                              minmax_tvalid;

  wire [INPUT_BIT_WIDTH-1:0]        offsetgain_toffset;
  wire [17:0]                       offsetgain_tgain;
  wire                              offsetgain_tvalid;

  wire [M_AXIS_DATA_WIDTH-1:0]      scale_tdata;
  wire                              scale_tvalid;
  wire                              scale_tready;
  wire                              scale_tlast;
  wire [TUSER_WIDTH-1:0]            scale_tuser;

  wire  [S_AXIS_DATA_WIDTH-1:0]     input_tdata;
  wire                              input_tvalid;
  wire                              input_tvalid_minmax;
  wire                              input_tready;
  wire                              input_tlast;
  wire  [TUSER_WIDTH-1:0]           input_tuser;

  assign s_axis_tready = input_tready;

  assign input_tdata  = s_axis_tdata;
  assign input_tvalid = s_axis_tvalid;
  assign input_tlast  = s_axis_tlast;
  assign input_tuser  = s_axis_tuser;

  // only valid if a transaction happens
  assign input_tvalid_minmax = input_tready & input_tvalid;

  histogram_minmax2 #(
    .PIXEL_PER_CYCLE                      (PIXEL_PER_CYCLE),
    .INPUT_BIT_WIDTH                      (INPUT_BIT_WIDTH)
  ) minmax_inst
  (
    .clk                                  (clk),
    .rstn                                 (rstn),

    .s_axis_tdata                         (input_tdata),
    .s_axis_tvalid                        (input_tvalid_minmax),
    .s_axis_tlast                         (input_tlast),
    .s_axis_tuser                         (input_tuser),

    .force_tmin                           (force_tmin),
    .force_tmax                           (force_tmax),

    .m_axis_tmin                          (minmax_tmin),
    .m_axis_tmax                          (minmax_tmax),
    .m_axis_tvalid                        (minmax_tvalid)
  );

  histogram_offsetgain #(
    .INPUT_BIT_WIDTH                      (INPUT_BIT_WIDTH)
  ) offsetgain_inst
  (
    .clk                                  (clk),
    .rstn                                 (rstn),

    .s_axis_tmin                          (minmax_tmin),
    .s_axis_tmax                          (minmax_tmax),
    .s_axis_tvalid                        (minmax_tvalid),

    .m_axis_toffset                       (offsetgain_toffset),
    .m_axis_tgain                         (offsetgain_tgain),
    .m_axis_tvalid                        (offsetgain_tvalid)
  );

  histogram_scale #(
    .PIXEL_PER_CYCLE                      (PIXEL_PER_CYCLE),
    .INPUT_BIT_WIDTH                      (INPUT_BIT_WIDTH),
    .OUTPUT_BIT_WIDTH                     (OUTPUT_BIT_WIDTH)
  ) scale_inst
  (
    .clk                                  (clk),
    .rstn                                 (rstn),

    .s_axis_tdata                         (input_tdata),
    .s_axis_tvalid                        (input_tvalid),
    .s_axis_tready                        (input_tready),
    .s_axis_tlast                         (input_tlast),
    .s_axis_tuser                         (input_tuser),

    .params_toffset                       (offsetgain_toffset),
    .params_tgain                         (offsetgain_tgain),
    .params_tvalid                        (offsetgain_tvalid),

    .m_axis_tdata                         (scale_tdata),
    .m_axis_tvalid                        (scale_tvalid),
    .m_axis_tready                        (scale_tready),
    .m_axis_tlast                         (scale_tlast),
    .m_axis_tuser                         (scale_tuser)
  );

  assign scale_tready   = m_axis_tready;

  // assign outputs
  assign m_axis_tdata   = scale_tdata;
  assign m_axis_tvalid  = scale_tvalid;
  assign m_axis_tlast   = scale_tlast;
  assign m_axis_tuser   = scale_tuser;

endmodule
