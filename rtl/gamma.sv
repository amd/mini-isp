// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module gamma
  #(
    // Pixel per cycle. 1, 2 or 4
    parameter PIXEL_PER_CYCLE             = 2,
    // Input component bit width. 8, 10, 12.
    parameter INPUT_COMPONENT_BIT_WIDTH   = 12,
    // Output component bit width. Must be equal or less than input component bit width.
    parameter OUTPUT_COMPONENT_BIT_WIDTH  = 8,
    parameter S_AXIS_DATA_WIDTH           = 8*$rtoi($floor((PIXEL_PER_CYCLE * 3 * INPUT_COMPONENT_BIT_WIDTH + 7)/8)),
    parameter M_AXIS_DATA_WIDTH           = 8*$rtoi($floor((PIXEL_PER_CYCLE * 3 * OUTPUT_COMPONENT_BIT_WIDTH + 7)/8)),
    parameter TUSER_WIDTH                 = 1,
    parameter LUT_FILE                    = "../../rtl/lut.mem"
  )
  (
    input  wire                           clk,
    input  wire                           rstn,

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

  localparam S_AXIS_COMPONENT_DATA_WIDTH  = 8*$rtoi($floor((PIXEL_PER_CYCLE * INPUT_COMPONENT_BIT_WIDTH + 7)/8));
  localparam M_AXIS_COMPONENT_DATA_WIDTH  = 8*$rtoi($floor((PIXEL_PER_CYCLE * OUTPUT_COMPONENT_BIT_WIDTH + 7)/8));

  reg  [S_AXIS_COMPONENT_DATA_WIDTH-1:0]  gamma_r_s_axis_tdata;
  reg                                     gamma_r_s_axis_tready;
  reg                                     gamma_r_s_axis_tvalid;
  reg  [M_AXIS_COMPONENT_DATA_WIDTH-1:0]  gamma_r_m_axis_tdata;
  reg                                     gamma_r_m_axis_tvalid;
  reg                                     gamma_r_m_axis_tlast;
  reg  [TUSER_WIDTH-1:0]                  gamma_r_m_axis_tuser;
  reg                                     gamma_r_m_axis_tready;

  reg  [S_AXIS_COMPONENT_DATA_WIDTH-1:0]  gamma_b_s_axis_tdata;
  reg                                     gamma_b_s_axis_tready;
  reg                                     gamma_b_s_axis_tvalid;
  reg  [M_AXIS_COMPONENT_DATA_WIDTH-1:0]  gamma_b_m_axis_tdata;
  reg                                     gamma_b_m_axis_tvalid;
  reg                                     gamma_b_m_axis_tready;

  reg  [S_AXIS_COMPONENT_DATA_WIDTH-1:0]  gamma_g_s_axis_tdata;
  reg                                     gamma_g_s_axis_tready;
  reg                                     gamma_g_s_axis_tvalid;
  reg  [M_AXIS_COMPONENT_DATA_WIDTH-1:0]  gamma_g_m_axis_tdata;
  reg                                     gamma_g_m_axis_tvalid;
  reg                                     gamma_g_m_axis_tready;

  reg  [M_AXIS_DATA_WIDTH-1:0]            pipe_0_tdata;
  reg  [M_AXIS_DATA_WIDTH-1:0]            pipe_0_tdata_wire;
  reg                                     pipe_0_tvalid;
  reg                                     pipe_0_tready;
  reg                                     pipe_0_tlast;
  reg  [TUSER_WIDTH-1:0]                  pipe_0_tuser;

  assign s_axis_tready = gamma_r_s_axis_tready & gamma_b_s_axis_tready & gamma_g_s_axis_tready;

  assign gamma_r_s_axis_tvalid = s_axis_tvalid;
  assign gamma_b_s_axis_tvalid = s_axis_tvalid;
  assign gamma_g_s_axis_tvalid = s_axis_tvalid;

  //assign gamma_r_s_axis_tvalid = s_axis_tvalid & gamma_b_s_axis_tready & gamma_g_s_axis_tready;
  //assign gamma_b_s_axis_tvalid = s_axis_tvalid & gamma_r_s_axis_tready & gamma_g_s_axis_tready;
  //assign gamma_g_s_axis_tvalid = s_axis_tvalid & gamma_r_s_axis_tready & gamma_b_s_axis_tready;

  generate
    for (genvar pixel = 0; pixel < PIXEL_PER_CYCLE; pixel = pixel + 1) begin

      assign gamma_r_s_axis_tdata[(pixel+1)*INPUT_COMPONENT_BIT_WIDTH-1:pixel*INPUT_COMPONENT_BIT_WIDTH] = s_axis_tdata[pixel*3*INPUT_COMPONENT_BIT_WIDTH+INPUT_COMPONENT_BIT_WIDTH-1:pixel*3*INPUT_COMPONENT_BIT_WIDTH];
      assign gamma_b_s_axis_tdata[(pixel+1)*INPUT_COMPONENT_BIT_WIDTH-1:pixel*INPUT_COMPONENT_BIT_WIDTH] = s_axis_tdata[pixel*3*INPUT_COMPONENT_BIT_WIDTH+2*INPUT_COMPONENT_BIT_WIDTH-1:pixel*3*INPUT_COMPONENT_BIT_WIDTH+INPUT_COMPONENT_BIT_WIDTH];
      assign gamma_g_s_axis_tdata[(pixel+1)*INPUT_COMPONENT_BIT_WIDTH-1:pixel*INPUT_COMPONENT_BIT_WIDTH] = s_axis_tdata[pixel*3*INPUT_COMPONENT_BIT_WIDTH+3*INPUT_COMPONENT_BIT_WIDTH-1:pixel*3*INPUT_COMPONENT_BIT_WIDTH+2*INPUT_COMPONENT_BIT_WIDTH];

    end
  endgenerate

  lut #(
    .PIXEL_PER_CYCLE        (PIXEL_PER_CYCLE),
    .INPUT_PIXEL_BIT_WIDTH  (INPUT_COMPONENT_BIT_WIDTH),
    .OUTPUT_PIXEL_BIT_WIDTH (OUTPUT_COMPONENT_BIT_WIDTH),
    .LUT_FILE               (LUT_FILE)
  ) gamma_r_inst
  (
    .clk                    (clk),
    .rstn                   (rstn),

    .s_axis_tdata           (gamma_r_s_axis_tdata),
    .s_axis_tvalid          (gamma_r_s_axis_tvalid),
    .s_axis_tready          (gamma_r_s_axis_tready),
    .s_axis_tlast           (s_axis_tlast),
    .s_axis_tuser           (s_axis_tuser),

    .m_axis_tdata           (gamma_r_m_axis_tdata),
    .m_axis_tvalid          (gamma_r_m_axis_tvalid),
    .m_axis_tready          (gamma_r_m_axis_tready),
    .m_axis_tlast           (gamma_r_m_axis_tlast),
    .m_axis_tuser           (gamma_r_m_axis_tuser)
  );

  lut #(
    .PIXEL_PER_CYCLE        (PIXEL_PER_CYCLE),
    .INPUT_PIXEL_BIT_WIDTH  (INPUT_COMPONENT_BIT_WIDTH),
    .OUTPUT_PIXEL_BIT_WIDTH (OUTPUT_COMPONENT_BIT_WIDTH),
    .LUT_FILE               (LUT_FILE)
  ) gamma_b_inst
  (
    .clk                    (clk),
    .rstn                   (rstn),

    .s_axis_tdata           (gamma_b_s_axis_tdata),
    .s_axis_tvalid          (gamma_b_s_axis_tvalid),
    .s_axis_tready          (gamma_b_s_axis_tready),
    .s_axis_tlast           (),
    .s_axis_tuser           (),

    .m_axis_tdata           (gamma_b_m_axis_tdata),
    .m_axis_tvalid          (gamma_b_m_axis_tvalid),
    .m_axis_tready          (gamma_b_m_axis_tready),
    .m_axis_tlast           (),
    .m_axis_tuser           ()
  );

  lut #(
    .PIXEL_PER_CYCLE        (PIXEL_PER_CYCLE),
    .INPUT_PIXEL_BIT_WIDTH  (INPUT_COMPONENT_BIT_WIDTH),
    .OUTPUT_PIXEL_BIT_WIDTH (OUTPUT_COMPONENT_BIT_WIDTH),
    .LUT_FILE               (LUT_FILE)
  ) gamma_g_inst
  (
    .clk                    (clk),
    .rstn                   (rstn),

    .s_axis_tdata           (gamma_g_s_axis_tdata),
    .s_axis_tvalid          (gamma_g_s_axis_tvalid),
    .s_axis_tready          (gamma_g_s_axis_tready),
    .s_axis_tlast           (),
    .s_axis_tuser           (),

    .m_axis_tdata           (gamma_g_m_axis_tdata),
    .m_axis_tvalid          (gamma_g_m_axis_tvalid),
    .m_axis_tready          (gamma_g_m_axis_tready),
    .m_axis_tlast           (),
    .m_axis_tuser           ()
  );

  assign gamma_r_m_axis_tready = gamma_r_m_axis_tvalid & gamma_b_m_axis_tvalid & gamma_g_m_axis_tvalid & pipe_0_tready;
  assign gamma_b_m_axis_tready = gamma_r_m_axis_tvalid & gamma_b_m_axis_tvalid & gamma_g_m_axis_tvalid & pipe_0_tready;
  assign gamma_g_m_axis_tready = gamma_r_m_axis_tvalid & gamma_b_m_axis_tvalid & gamma_g_m_axis_tvalid & pipe_0_tready;

  generate
  for (genvar pixel = 0; pixel < PIXEL_PER_CYCLE; pixel = pixel + 1) begin

    assign pipe_0_tdata_wire[pixel*3*OUTPUT_COMPONENT_BIT_WIDTH+3*OUTPUT_COMPONENT_BIT_WIDTH-1:pixel*3*OUTPUT_COMPONENT_BIT_WIDTH]  = {gamma_g_m_axis_tdata[(pixel+1)*OUTPUT_COMPONENT_BIT_WIDTH-1:pixel*OUTPUT_COMPONENT_BIT_WIDTH], gamma_b_m_axis_tdata[(pixel+1)*OUTPUT_COMPONENT_BIT_WIDTH-1:pixel*OUTPUT_COMPONENT_BIT_WIDTH], gamma_r_m_axis_tdata[(pixel+1)*OUTPUT_COMPONENT_BIT_WIDTH-1:pixel*OUTPUT_COMPONENT_BIT_WIDTH]};

  end
  endgenerate

  // pipeline stage 0
  assign pipe_0_tready = m_axis_tready | ~pipe_0_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_0_tready == 1'b1) begin
      pipe_0_tdata    <= pipe_0_tdata_wire;
      pipe_0_tvalid   <= gamma_r_m_axis_tvalid & gamma_b_m_axis_tvalid & gamma_g_m_axis_tvalid;
      pipe_0_tlast    <= gamma_r_m_axis_tlast;
      pipe_0_tuser    <= gamma_r_m_axis_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_0_tvalid <= '0;
    end
  end

  assign m_axis_tdata   = pipe_0_tdata;
  assign m_axis_tvalid  = pipe_0_tvalid;
  assign m_axis_tlast   = pipe_0_tlast;
  assign m_axis_tuser   = pipe_0_tuser;

endmodule
