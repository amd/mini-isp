// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module ccm
  #(
    // Pixel per cycle. 1, 2 or 4
    parameter PIXEL_PER_CYCLE             = 2,
    // Input component bit width. 8, 10, 12
    parameter COMPONENT_BIT_WIDTH         = 12,
    parameter S_AXIS_DATA_WIDTH           = 8*$rtoi($floor((PIXEL_PER_CYCLE * 3 * COMPONENT_BIT_WIDTH + 7)/8)),
    parameter M_AXIS_DATA_WIDTH           = 8*$rtoi($floor((PIXEL_PER_CYCLE * 3 * COMPONENT_BIT_WIDTH + 7)/8)),
    parameter TUSER_WIDTH                 = 1
  )
  (
    input  wire                           clk,
    input  wire                           rstn,

    input  wire [15:0]                    ccm_r_r,
    input  wire [15:0]                    ccm_r_g,
    input  wire [15:0]                    ccm_r_b,
    input  wire [15:0]                    ccm_g_r,
    input  wire [15:0]                    ccm_g_g,
    input  wire [15:0]                    ccm_g_b,
    input  wire [15:0]                    ccm_b_r,
    input  wire [15:0]                    ccm_b_g,
    input  wire [15:0]                    ccm_b_b,

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

  localparam MULT_BIT_WIDTH = COMPONENT_BIT_WIDTH + 1 + 16;
  localparam ADD_BIT_WIDTH = MULT_BIT_WIDTH + 3;
  localparam RIGHT_SHIFT_BITS = 12; // 4.12 fixed point format of coefficients

  function [COMPONENT_BIT_WIDTH-1:0] shift_and_saturate( input [ADD_BIT_WIDTH-1:0] data );
    begin
      if (data[ADD_BIT_WIDTH-1] == 1'b1) begin
        // negative number, set to zero
        shift_and_saturate = '0;
      end else if (data[ADD_BIT_WIDTH-2:COMPONENT_BIT_WIDTH+RIGHT_SHIFT_BITS] != '0) begin
        // overflow, set to maximum allowed value
        shift_and_saturate = '1;
      end else begin
        // all good, shift and output
        shift_and_saturate = data[COMPONENT_BIT_WIDTH+RIGHT_SHIFT_BITS-1:RIGHT_SHIFT_BITS];
      end
    end
  endfunction

  reg signed [15:0]                       ccm_r_r_int;
  reg signed [15:0]                       ccm_r_g_int;
  reg signed [15:0]                       ccm_r_b_int;
  reg signed [15:0]                       ccm_g_r_int;
  reg signed [15:0]                       ccm_g_g_int;
  reg signed [15:0]                       ccm_g_b_int;
  reg signed [15:0]                       ccm_b_r_int;
  reg signed [15:0]                       ccm_b_g_int;
  reg signed [15:0]                       ccm_b_b_int;

  // Pipe 0 signals
  reg signed  [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel0_r;
  reg signed  [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel0_g;
  reg signed  [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel0_b;
  reg signed  [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel1_r;
  reg signed  [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel1_g;
  reg signed  [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel1_b;
  reg signed  [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel2_r;
  reg signed  [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel2_g;
  reg signed  [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel2_b;
  reg signed  [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel3_r;
  reg signed  [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel3_g;
  reg signed  [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel3_b;
  wire signed [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel0_r_wire;
  wire signed [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel0_g_wire;
  wire signed [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel0_b_wire;
  wire signed [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel1_r_wire;
  wire signed [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel1_g_wire;
  wire signed [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel1_b_wire;
  wire signed [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel2_r_wire;
  wire signed [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel2_g_wire;
  wire signed [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel2_b_wire;
  wire signed [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel3_r_wire;
  wire signed [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel3_g_wire;
  wire signed [COMPONENT_BIT_WIDTH:0]     pipe_0_pixel3_b_wire;
  reg                                     pipe_0_tlast;
  reg  [TUSER_WIDTH-1:0]                  pipe_0_tuser;
  reg                                     pipe_0_tvalid = 'b0;
  wire                                    pipe_0_tready;

  // Pipe 1 signals
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel0_r_r;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel0_r_g;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel0_r_b;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel0_g_r;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel0_g_g;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel0_g_b;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel0_b_r;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel0_b_g;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel0_b_b;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel1_r_r;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel1_r_g;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel1_r_b;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel1_g_r;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel1_g_g;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel1_g_b;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel1_b_r;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel1_b_g;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel1_b_b;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel2_r_r;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel2_r_g;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel2_r_b;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel2_g_r;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel2_g_g;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel2_g_b;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel2_b_r;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel2_b_g;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel2_b_b;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel3_r_r;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel3_r_g;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel3_r_b;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel3_g_r;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel3_g_g;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel3_g_b;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel3_b_r;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel3_b_g;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_1_pixel3_b_b;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel0_r_r_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel0_r_g_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel0_r_b_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel0_g_r_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel0_g_g_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel0_g_b_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel0_b_r_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel0_b_g_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel0_b_b_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel1_r_r_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel1_r_g_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel1_r_b_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel1_g_r_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel1_g_g_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel1_g_b_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel1_b_r_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel1_b_g_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel1_b_b_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel2_r_r_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel2_r_g_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel2_r_b_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel2_g_r_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel2_g_g_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel2_g_b_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel2_b_r_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel2_b_g_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel2_b_b_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel3_r_r_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel3_r_g_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel3_r_b_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel3_g_r_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel3_g_g_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel3_g_b_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel3_b_r_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel3_b_g_wire;
  wire signed [MULT_BIT_WIDTH-1:0]        pipe_1_pixel3_b_b_wire;
  reg                                     pipe_1_tlast;
  reg [TUSER_WIDTH-1:0]                   pipe_1_tuser;
  reg                                     pipe_1_tvalid = 'b0;
  wire                                    pipe_1_tready;

  // pipe 2 signals
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_2_pixel0_r;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_2_pixel0_g;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_2_pixel0_b;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_2_pixel1_r;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_2_pixel1_g;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_2_pixel1_b;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_2_pixel2_r;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_2_pixel2_g;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_2_pixel2_b;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_2_pixel3_r;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_2_pixel3_g;
  reg signed  [ADD_BIT_WIDTH-1:0]         pipe_2_pixel3_b;
  wire signed [ADD_BIT_WIDTH-1:0]         pipe_2_pixel0_r_wire;
  wire signed [ADD_BIT_WIDTH-1:0]         pipe_2_pixel0_g_wire;
  wire signed [ADD_BIT_WIDTH-1:0]         pipe_2_pixel0_b_wire;
  wire signed [ADD_BIT_WIDTH-1:0]         pipe_2_pixel1_r_wire;
  wire signed [ADD_BIT_WIDTH-1:0]         pipe_2_pixel1_g_wire;
  wire signed [ADD_BIT_WIDTH-1:0]         pipe_2_pixel1_b_wire;
  wire signed [ADD_BIT_WIDTH-1:0]         pipe_2_pixel2_r_wire;
  wire signed [ADD_BIT_WIDTH-1:0]         pipe_2_pixel2_g_wire;
  wire signed [ADD_BIT_WIDTH-1:0]         pipe_2_pixel2_b_wire;
  wire signed [ADD_BIT_WIDTH-1:0]         pipe_2_pixel3_r_wire;
  wire signed [ADD_BIT_WIDTH-1:0]         pipe_2_pixel3_g_wire;
  wire signed [ADD_BIT_WIDTH-1:0]         pipe_2_pixel3_b_wire;
  reg                                     pipe_2_tlast;
  reg [TUSER_WIDTH-1:0]                   pipe_2_tuser;
  reg                                     pipe_2_tvalid = 'b0;
  wire                                    pipe_2_tready;

  // pipe 3 signals
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_3_pixel0_r;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_3_pixel0_g;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_3_pixel0_b;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_3_pixel1_r;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_3_pixel1_g;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_3_pixel1_b;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_3_pixel2_r;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_3_pixel2_g;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_3_pixel2_b;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_3_pixel3_r;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_3_pixel3_g;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_3_pixel3_b;
  reg                                     pipe_3_tlast;
  reg [TUSER_WIDTH-1:0]                   pipe_3_tuser;
  reg                                     pipe_3_tvalid = 'b0;
  wire                                    pipe_3_tready;

    // pipe 4 signals
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_4_pixel0_r;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_4_pixel0_g;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_4_pixel0_b;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_4_pixel1_r;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_4_pixel1_g;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_4_pixel1_b;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_4_pixel2_r;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_4_pixel2_g;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_4_pixel2_b;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_4_pixel3_r;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_4_pixel3_g;
  reg [COMPONENT_BIT_WIDTH-1:0]           pipe_4_pixel3_b;
  reg                                     pipe_4_tlast;
  reg [TUSER_WIDTH-1:0]                   pipe_4_tuser;
  reg                                     pipe_4_tvalid = 'b0;
  wire                                    pipe_4_tready;
  wire [M_AXIS_DATA_WIDTH-1:0]            pipe_4_tdata_wire;

  generate

    assign pipe_0_pixel0_g_wire = {1'b0, s_axis_tdata[1*COMPONENT_BIT_WIDTH-1:0*COMPONENT_BIT_WIDTH]};
    assign pipe_0_pixel0_b_wire = {1'b0, s_axis_tdata[2*COMPONENT_BIT_WIDTH-1:1*COMPONENT_BIT_WIDTH]};
    assign pipe_0_pixel0_r_wire = {1'b0, s_axis_tdata[3*COMPONENT_BIT_WIDTH-1:2*COMPONENT_BIT_WIDTH]};

    if (PIXEL_PER_CYCLE > 1) begin
      assign pipe_0_pixel1_g_wire = {1'b0, s_axis_tdata[3*COMPONENT_BIT_WIDTH+1*COMPONENT_BIT_WIDTH-1:3*COMPONENT_BIT_WIDTH+0*COMPONENT_BIT_WIDTH]};
      assign pipe_0_pixel1_b_wire = {1'b0, s_axis_tdata[3*COMPONENT_BIT_WIDTH+2*COMPONENT_BIT_WIDTH-1:3*COMPONENT_BIT_WIDTH+1*COMPONENT_BIT_WIDTH]};
      assign pipe_0_pixel1_r_wire = {1'b0, s_axis_tdata[3*COMPONENT_BIT_WIDTH+3*COMPONENT_BIT_WIDTH-1:3*COMPONENT_BIT_WIDTH+2*COMPONENT_BIT_WIDTH]};
    end

    if (PIXEL_PER_CYCLE > 2) begin
      assign pipe_0_pixel2_g_wire = {1'b0, s_axis_tdata[2*3*COMPONENT_BIT_WIDTH+1*COMPONENT_BIT_WIDTH-1:2*3*COMPONENT_BIT_WIDTH+0*COMPONENT_BIT_WIDTH]};
      assign pipe_0_pixel2_b_wire = {1'b0, s_axis_tdata[2*3*COMPONENT_BIT_WIDTH+2*COMPONENT_BIT_WIDTH-1:2*3*COMPONENT_BIT_WIDTH+1*COMPONENT_BIT_WIDTH]};
      assign pipe_0_pixel2_r_wire = {1'b0, s_axis_tdata[2*3*COMPONENT_BIT_WIDTH+3*COMPONENT_BIT_WIDTH-1:2*3*COMPONENT_BIT_WIDTH+2*COMPONENT_BIT_WIDTH]};
    end

    if (PIXEL_PER_CYCLE > 3) begin
      assign pipe_0_pixel3_g_wire = {1'b0, s_axis_tdata[3*3*COMPONENT_BIT_WIDTH+1*COMPONENT_BIT_WIDTH-1:3*3*COMPONENT_BIT_WIDTH+0*COMPONENT_BIT_WIDTH]};
      assign pipe_0_pixel3_b_wire = {1'b0, s_axis_tdata[3*3*COMPONENT_BIT_WIDTH+2*COMPONENT_BIT_WIDTH-1:3*3*COMPONENT_BIT_WIDTH+1*COMPONENT_BIT_WIDTH]};
      assign pipe_0_pixel3_r_wire = {1'b0, s_axis_tdata[3*3*COMPONENT_BIT_WIDTH+3*COMPONENT_BIT_WIDTH-1:3*3*COMPONENT_BIT_WIDTH+2*COMPONENT_BIT_WIDTH]};
    end

  endgenerate

  // pipeline stage 0
  assign pipe_0_tready = pipe_1_tready | ~pipe_0_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_0_tready == 1'b1) begin
      if (s_axis_tvalid == 1'b1) begin
        // initial register
        pipe_0_pixel0_r <= pipe_0_pixel0_r_wire;
        pipe_0_pixel0_g <= pipe_0_pixel0_g_wire;
        pipe_0_pixel0_b <= pipe_0_pixel0_b_wire;
        pipe_0_pixel1_r <= pipe_0_pixel1_r_wire;
        pipe_0_pixel1_g <= pipe_0_pixel1_g_wire;
        pipe_0_pixel1_b <= pipe_0_pixel1_b_wire;
        pipe_0_pixel2_r <= pipe_0_pixel2_r_wire;
        pipe_0_pixel2_g <= pipe_0_pixel2_g_wire;
        pipe_0_pixel2_b <= pipe_0_pixel2_b_wire;
        pipe_0_pixel3_r <= pipe_0_pixel3_r_wire;
        pipe_0_pixel3_g <= pipe_0_pixel3_g_wire;
        pipe_0_pixel3_b <= pipe_0_pixel3_b_wire;

        // capture new matrix coefficients only on start of frame
        if (s_axis_tuser[0] == 1'b1) begin
          ccm_r_r_int <= $signed(ccm_r_r);
          ccm_r_g_int <= $signed(ccm_r_g);
          ccm_r_b_int <= $signed(ccm_r_b);
          ccm_g_r_int <= $signed(ccm_g_r);
          ccm_g_g_int <= $signed(ccm_g_g);
          ccm_g_b_int <= $signed(ccm_g_b);
          ccm_b_r_int <= $signed(ccm_b_r);
          ccm_b_g_int <= $signed(ccm_b_g);
          ccm_b_b_int <= $signed(ccm_b_b);
        end
      end

      pipe_0_tvalid   <= s_axis_tvalid;
      pipe_0_tlast    <= s_axis_tlast;
      pipe_0_tuser    <= s_axis_tuser;

    end

    if (rstn == 1'b0) begin
      pipe_0_tvalid   <= '0;
    end
  end

  // multiplications
  generate

    assign pipe_1_pixel0_r_r_wire = pipe_0_pixel0_r * ccm_r_r_int;
    assign pipe_1_pixel0_r_g_wire = pipe_0_pixel0_g * ccm_r_g_int;
    assign pipe_1_pixel0_r_b_wire = pipe_0_pixel0_b * ccm_r_b_int;

    assign pipe_1_pixel0_g_r_wire = pipe_0_pixel0_r * ccm_g_r_int;
    assign pipe_1_pixel0_g_g_wire = pipe_0_pixel0_g * ccm_g_g_int;
    assign pipe_1_pixel0_g_b_wire = pipe_0_pixel0_b * ccm_g_b_int;

    assign pipe_1_pixel0_b_r_wire = pipe_0_pixel0_r * ccm_b_r_int;
    assign pipe_1_pixel0_b_g_wire = pipe_0_pixel0_g * ccm_b_g_int;
    assign pipe_1_pixel0_b_b_wire = pipe_0_pixel0_b * ccm_b_b_int;

    if (PIXEL_PER_CYCLE > 1) begin
      assign pipe_1_pixel1_r_r_wire = pipe_0_pixel1_r * ccm_r_r_int;
      assign pipe_1_pixel1_r_g_wire = pipe_0_pixel1_g * ccm_r_g_int;
      assign pipe_1_pixel1_r_b_wire = pipe_0_pixel1_b * ccm_r_b_int;

      assign pipe_1_pixel1_g_r_wire = pipe_0_pixel1_r * ccm_g_r_int;
      assign pipe_1_pixel1_g_g_wire = pipe_0_pixel1_g * ccm_g_g_int;
      assign pipe_1_pixel1_g_b_wire = pipe_0_pixel1_b * ccm_g_b_int;

      assign pipe_1_pixel1_b_r_wire = pipe_0_pixel1_r * ccm_b_r_int;
      assign pipe_1_pixel1_b_g_wire = pipe_0_pixel1_g * ccm_b_g_int;
      assign pipe_1_pixel1_b_b_wire = pipe_0_pixel1_b * ccm_b_b_int;
    end

    if (PIXEL_PER_CYCLE > 2) begin
      assign pipe_1_pixel2_r_r_wire = pipe_0_pixel2_r * ccm_r_r_int;
      assign pipe_1_pixel2_r_g_wire = pipe_0_pixel2_g * ccm_r_g_int;
      assign pipe_1_pixel2_r_b_wire = pipe_0_pixel2_b * ccm_r_b_int;

      assign pipe_1_pixel2_g_r_wire = pipe_0_pixel2_r * ccm_g_r_int;
      assign pipe_1_pixel2_g_g_wire = pipe_0_pixel2_g * ccm_g_g_int;
      assign pipe_1_pixel2_g_b_wire = pipe_0_pixel2_b * ccm_g_b_int;

      assign pipe_1_pixel2_b_r_wire = pipe_0_pixel2_r * ccm_b_r_int;
      assign pipe_1_pixel2_b_g_wire = pipe_0_pixel2_g * ccm_b_g_int;
      assign pipe_1_pixel2_b_b_wire = pipe_0_pixel2_b * ccm_b_b_int;
    end

    if (PIXEL_PER_CYCLE > 3) begin
      assign pipe_1_pixel3_r_r_wire = pipe_0_pixel3_r * ccm_r_r_int;
      assign pipe_1_pixel3_r_g_wire = pipe_0_pixel3_g * ccm_r_g_int;
      assign pipe_1_pixel3_r_b_wire = pipe_0_pixel3_b * ccm_r_b_int;

      assign pipe_1_pixel3_g_r_wire = pipe_0_pixel3_r * ccm_g_r_int;
      assign pipe_1_pixel3_g_g_wire = pipe_0_pixel3_g * ccm_g_g_int;
      assign pipe_1_pixel3_g_b_wire = pipe_0_pixel3_b * ccm_g_b_int;

      assign pipe_1_pixel3_b_r_wire = pipe_0_pixel3_r * ccm_b_r_int;
      assign pipe_1_pixel3_b_g_wire = pipe_0_pixel3_g * ccm_b_g_int;
      assign pipe_1_pixel3_b_b_wire = pipe_0_pixel3_b * ccm_b_b_int;
    end

  endgenerate

  // pipeline stage 1
  assign pipe_1_tready = pipe_2_tready | ~pipe_1_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_1_tready == 1'b1) begin
      if (pipe_0_tvalid == 1'b1) begin

        pipe_1_pixel0_r_r <= ADD_BIT_WIDTH'(pipe_1_pixel0_r_r_wire);
        pipe_1_pixel0_r_g <= ADD_BIT_WIDTH'(pipe_1_pixel0_r_g_wire);
        pipe_1_pixel0_r_b <= ADD_BIT_WIDTH'(pipe_1_pixel0_r_b_wire);
        pipe_1_pixel0_g_r <= ADD_BIT_WIDTH'(pipe_1_pixel0_g_r_wire);
        pipe_1_pixel0_g_g <= ADD_BIT_WIDTH'(pipe_1_pixel0_g_g_wire);
        pipe_1_pixel0_g_b <= ADD_BIT_WIDTH'(pipe_1_pixel0_g_b_wire);
        pipe_1_pixel0_b_r <= ADD_BIT_WIDTH'(pipe_1_pixel0_b_r_wire);
        pipe_1_pixel0_b_g <= ADD_BIT_WIDTH'(pipe_1_pixel0_b_g_wire);
        pipe_1_pixel0_b_b <= ADD_BIT_WIDTH'(pipe_1_pixel0_b_b_wire);

        pipe_1_pixel1_r_r <= ADD_BIT_WIDTH'(pipe_1_pixel1_r_r_wire);
        pipe_1_pixel1_r_g <= ADD_BIT_WIDTH'(pipe_1_pixel1_r_g_wire);
        pipe_1_pixel1_r_b <= ADD_BIT_WIDTH'(pipe_1_pixel1_r_b_wire);
        pipe_1_pixel1_g_r <= ADD_BIT_WIDTH'(pipe_1_pixel1_g_r_wire);
        pipe_1_pixel1_g_g <= ADD_BIT_WIDTH'(pipe_1_pixel1_g_g_wire);
        pipe_1_pixel1_g_b <= ADD_BIT_WIDTH'(pipe_1_pixel1_g_b_wire);
        pipe_1_pixel1_b_r <= ADD_BIT_WIDTH'(pipe_1_pixel1_b_r_wire);
        pipe_1_pixel1_b_g <= ADD_BIT_WIDTH'(pipe_1_pixel1_b_g_wire);
        pipe_1_pixel1_b_b <= ADD_BIT_WIDTH'(pipe_1_pixel1_b_b_wire);

        pipe_1_pixel2_r_r <= ADD_BIT_WIDTH'(pipe_1_pixel2_r_r_wire);
        pipe_1_pixel2_r_g <= ADD_BIT_WIDTH'(pipe_1_pixel2_r_g_wire);
        pipe_1_pixel2_r_b <= ADD_BIT_WIDTH'(pipe_1_pixel2_r_b_wire);
        pipe_1_pixel2_g_r <= ADD_BIT_WIDTH'(pipe_1_pixel2_g_r_wire);
        pipe_1_pixel2_g_g <= ADD_BIT_WIDTH'(pipe_1_pixel2_g_g_wire);
        pipe_1_pixel2_g_b <= ADD_BIT_WIDTH'(pipe_1_pixel2_g_b_wire);
        pipe_1_pixel2_b_r <= ADD_BIT_WIDTH'(pipe_1_pixel2_b_r_wire);
        pipe_1_pixel2_b_g <= ADD_BIT_WIDTH'(pipe_1_pixel2_b_g_wire);
        pipe_1_pixel2_b_b <= ADD_BIT_WIDTH'(pipe_1_pixel2_b_b_wire);

        pipe_1_pixel3_r_r <= ADD_BIT_WIDTH'(pipe_1_pixel3_r_r_wire);
        pipe_1_pixel3_r_g <= ADD_BIT_WIDTH'(pipe_1_pixel3_r_g_wire);
        pipe_1_pixel3_r_b <= ADD_BIT_WIDTH'(pipe_1_pixel3_r_b_wire);
        pipe_1_pixel3_g_r <= ADD_BIT_WIDTH'(pipe_1_pixel3_g_r_wire);
        pipe_1_pixel3_g_g <= ADD_BIT_WIDTH'(pipe_1_pixel3_g_g_wire);
        pipe_1_pixel3_g_b <= ADD_BIT_WIDTH'(pipe_1_pixel3_g_b_wire);
        pipe_1_pixel3_b_r <= ADD_BIT_WIDTH'(pipe_1_pixel3_b_r_wire);
        pipe_1_pixel3_b_g <= ADD_BIT_WIDTH'(pipe_1_pixel3_b_g_wire);
        pipe_1_pixel3_b_b <= ADD_BIT_WIDTH'(pipe_1_pixel3_b_b_wire);
      end

      pipe_1_tvalid   <= pipe_0_tvalid;
      pipe_1_tlast    <= pipe_0_tlast;
      pipe_1_tuser    <= pipe_0_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_1_tvalid   <= '0;
    end
  end

  // additions
  generate

    assign pipe_2_pixel0_r_wire = pipe_1_pixel0_r_r + pipe_1_pixel0_r_g + pipe_1_pixel0_r_b;
    assign pipe_2_pixel0_g_wire = pipe_1_pixel0_g_r + pipe_1_pixel0_g_g + pipe_1_pixel0_g_b;
    assign pipe_2_pixel0_b_wire = pipe_1_pixel0_b_r + pipe_1_pixel0_b_g + pipe_1_pixel0_b_b;

    if (PIXEL_PER_CYCLE > 1) begin
      assign pipe_2_pixel1_r_wire = pipe_1_pixel1_r_r + pipe_1_pixel1_r_g + pipe_1_pixel1_r_b;
      assign pipe_2_pixel1_g_wire = pipe_1_pixel1_g_r + pipe_1_pixel1_g_g + pipe_1_pixel1_g_b;
      assign pipe_2_pixel1_b_wire = pipe_1_pixel1_b_r + pipe_1_pixel1_b_g + pipe_1_pixel1_b_b;
    end

    if (PIXEL_PER_CYCLE > 2) begin
      assign pipe_2_pixel2_r_wire = pipe_1_pixel2_r_r + pipe_1_pixel2_r_g + pipe_1_pixel2_r_b;
      assign pipe_2_pixel2_g_wire = pipe_1_pixel2_g_r + pipe_1_pixel2_g_g + pipe_1_pixel2_g_b;
      assign pipe_2_pixel2_b_wire = pipe_1_pixel2_b_r + pipe_1_pixel2_b_g + pipe_1_pixel2_b_b;
    end

    if (PIXEL_PER_CYCLE > 3) begin
      assign pipe_2_pixel3_r_wire = pipe_1_pixel3_r_r + pipe_1_pixel3_r_g + pipe_1_pixel3_r_b;
      assign pipe_2_pixel3_g_wire = pipe_1_pixel3_g_r + pipe_1_pixel3_g_g + pipe_1_pixel3_g_b;
      assign pipe_2_pixel3_b_wire = pipe_1_pixel3_b_r + pipe_1_pixel3_b_g + pipe_1_pixel3_b_b;
    end

  endgenerate

  // TODO: maybe add another pipeline stage here?

  // pipeline stage 2
  assign pipe_2_tready = pipe_3_tready | ~pipe_2_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_2_tready == 1'b1) begin
      if (pipe_1_tvalid == 1'b1) begin
        pipe_2_pixel0_r <= pipe_2_pixel0_r_wire;
        pipe_2_pixel0_g <= pipe_2_pixel0_g_wire;
        pipe_2_pixel0_b <= pipe_2_pixel0_b_wire;
        pipe_2_pixel1_r <= pipe_2_pixel1_r_wire;
        pipe_2_pixel1_g <= pipe_2_pixel1_g_wire;
        pipe_2_pixel1_b <= pipe_2_pixel1_b_wire;
        pipe_2_pixel2_r <= pipe_2_pixel2_r_wire;
        pipe_2_pixel2_g <= pipe_2_pixel2_g_wire;
        pipe_2_pixel2_b <= pipe_2_pixel2_b_wire;
        pipe_2_pixel3_r <= pipe_2_pixel3_r_wire;
        pipe_2_pixel3_g <= pipe_2_pixel3_g_wire;
        pipe_2_pixel3_b <= pipe_2_pixel3_b_wire;

      end

      pipe_2_tvalid   <= pipe_1_tvalid;
      pipe_2_tlast    <= pipe_1_tlast;
      pipe_2_tuser    <= pipe_1_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_2_tvalid   <= '0;
    end
  end

  // pipeline stage 3
  assign pipe_3_tready = pipe_4_tready | ~pipe_3_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_3_tready == 1'b1) begin
      if (pipe_2_tvalid == 1'b1) begin
        // shift_and_saturate returns two leading bits that indicate if te full pixel should be clamped to 0 or max value.
        pipe_3_pixel0_r <= shift_and_saturate(pipe_2_pixel0_r);
        pipe_3_pixel0_g <= shift_and_saturate(pipe_2_pixel0_g);
        pipe_3_pixel0_b <= shift_and_saturate(pipe_2_pixel0_b);
        pipe_3_pixel1_r <= shift_and_saturate(pipe_2_pixel1_r);
        pipe_3_pixel1_g <= shift_and_saturate(pipe_2_pixel1_g);
        pipe_3_pixel1_b <= shift_and_saturate(pipe_2_pixel1_b);
        pipe_3_pixel2_r <= shift_and_saturate(pipe_2_pixel2_r);
        pipe_3_pixel2_g <= shift_and_saturate(pipe_2_pixel2_g);
        pipe_3_pixel2_b <= shift_and_saturate(pipe_2_pixel2_b);
        pipe_3_pixel3_r <= shift_and_saturate(pipe_2_pixel3_r);
        pipe_3_pixel3_g <= shift_and_saturate(pipe_2_pixel3_g);
        pipe_3_pixel3_b <= shift_and_saturate(pipe_2_pixel3_b);
      end

      pipe_3_tvalid   <= pipe_2_tvalid;
      pipe_3_tlast    <= pipe_2_tlast;
      pipe_3_tuser    <= pipe_2_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_3_tvalid   <= '0;
    end
  end

    // pipeline stage 4
  assign pipe_4_tready = m_axis_tready | ~pipe_4_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_4_tready == 1'b1) begin
      if (pipe_3_tvalid == 1'b1) begin
        // shift_and_saturate returns two leading bits that indicate if te full pixel should be clamped to 0 or max value.
        pipe_4_pixel0_r <= pipe_3_pixel0_r[COMPONENT_BIT_WIDTH-1:0];
        pipe_4_pixel0_g <= pipe_3_pixel0_g[COMPONENT_BIT_WIDTH-1:0];
        pipe_4_pixel0_b <= pipe_3_pixel0_b[COMPONENT_BIT_WIDTH-1:0];

        pipe_4_pixel1_r <= pipe_3_pixel1_r[COMPONENT_BIT_WIDTH-1:0];
        pipe_4_pixel1_g <= pipe_3_pixel1_g[COMPONENT_BIT_WIDTH-1:0];
        pipe_4_pixel1_b <= pipe_3_pixel1_b[COMPONENT_BIT_WIDTH-1:0];

        pipe_4_pixel2_r <= pipe_3_pixel2_r[COMPONENT_BIT_WIDTH-1:0];
        pipe_4_pixel2_g <= pipe_3_pixel2_g[COMPONENT_BIT_WIDTH-1:0];
        pipe_4_pixel2_b <= pipe_3_pixel2_b[COMPONENT_BIT_WIDTH-1:0];

        pipe_4_pixel3_r <= pipe_3_pixel3_r[COMPONENT_BIT_WIDTH-1:0];
        pipe_4_pixel3_g <= pipe_3_pixel3_g[COMPONENT_BIT_WIDTH-1:0];
        pipe_4_pixel3_b <= pipe_3_pixel3_b[COMPONENT_BIT_WIDTH-1:0];

      end

      pipe_4_tvalid   <= pipe_3_tvalid;
      pipe_4_tlast    <= pipe_3_tlast;
      pipe_4_tuser    <= pipe_3_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_4_tvalid   <= '0;
    end
  end

  // output
  generate
    //for (genvar pixel = 0; pixel < PIXEL_PER_CYCLE; pixel = pixel + 1) begin

      assign pipe_4_tdata_wire[3*COMPONENT_BIT_WIDTH-1:0] = {pipe_4_pixel0_r, pipe_4_pixel0_b, pipe_4_pixel0_g};

      if (PIXEL_PER_CYCLE > 1) begin
        assign pipe_4_tdata_wire[3*COMPONENT_BIT_WIDTH+3*COMPONENT_BIT_WIDTH-1:3*COMPONENT_BIT_WIDTH] = {pipe_4_pixel1_r, pipe_4_pixel1_b, pipe_4_pixel1_g};
      end

      if (PIXEL_PER_CYCLE > 2) begin
        assign pipe_4_tdata_wire[2*3*COMPONENT_BIT_WIDTH+3*COMPONENT_BIT_WIDTH-1:2*3*COMPONENT_BIT_WIDTH] = {pipe_4_pixel2_r, pipe_4_pixel2_b, pipe_4_pixel2_g};
      end

      if (PIXEL_PER_CYCLE > 3) begin
        assign pipe_4_tdata_wire[3*3*COMPONENT_BIT_WIDTH+3*COMPONENT_BIT_WIDTH-1:3*3*COMPONENT_BIT_WIDTH] = {pipe_4_pixel3_r, pipe_4_pixel3_b, pipe_4_pixel3_g};
      end

    //end
  endgenerate

  assign s_axis_tready  = pipe_0_tready;

  assign m_axis_tdata   = pipe_4_tdata_wire;
  assign m_axis_tvalid  = pipe_4_tvalid;
  assign m_axis_tlast   = pipe_4_tlast;
  assign m_axis_tuser   = pipe_4_tuser;

endmodule
