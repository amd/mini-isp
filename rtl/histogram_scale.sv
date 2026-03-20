// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module histogram_scale
  #(
    // Pixel per cycle. 1, 2 or 4
    parameter PIXEL_PER_CYCLE                     = 4,
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

    input  wire  [S_AXIS_DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                           s_axis_tvalid,
    output wire                           s_axis_tready,
    input  wire                           s_axis_tlast,
    input  wire  [TUSER_WIDTH-1:0]        s_axis_tuser,

    input  wire  [INPUT_BIT_WIDTH-1:0]    params_toffset,
    input  wire  [17:0]                   params_tgain,
    input  wire                           params_tvalid,

    output wire  [M_AXIS_DATA_WIDTH-1:0]  m_axis_tdata,
    output wire                           m_axis_tvalid,
    input  wire                           m_axis_tready,
    output wire                           m_axis_tlast,
    output wire  [TUSER_WIDTH-1:0]        m_axis_tuser
  );

  localparam int MULT_SHIFT = INPUT_BIT_WIDTH-OUTPUT_BIT_WIDTH;

  function [INPUT_BIT_WIDTH-1:0] subtract_and_clip(input [INPUT_BIT_WIDTH-1:0] x, y);
    reg [INPUT_BIT_WIDTH:0] tmp;
    begin
      tmp = {1'b0, x} - {1'b0, y};

      if (tmp[INPUT_BIT_WIDTH] == 1'b1) begin
        // negative number, set to zero
        subtract_and_clip = '0;
      end else begin
        subtract_and_clip = tmp[INPUT_BIT_WIDTH-1:0];
      end
    end
  endfunction

  function [INPUT_BIT_WIDTH-1:0] mult_and_shift(input [INPUT_BIT_WIDTH-1:0] x, input [17:0] y);
    reg [INPUT_BIT_WIDTH + 18-1:0] tmp;
    begin
      tmp = x * y;

      mult_and_shift = tmp[INPUT_BIT_WIDTH+MULT_SHIFT-1:MULT_SHIFT];
    end
  endfunction

  function [OUTPUT_BIT_WIDTH-1:0] saturate(input [INPUT_BIT_WIDTH-1:0] x);
    begin
      if (x[INPUT_BIT_WIDTH-1:OUTPUT_BIT_WIDTH] == '0) begin
        saturate = x[OUTPUT_BIT_WIDTH-1:0];
      end else begin
        saturate = '1;
      end
    end
  endfunction

  reg [17:0]                        param_gain;
  reg [INPUT_BIT_WIDTH-1:0]         param_offset;

  wire [INPUT_BIT_WIDTH-1:0]        pipe_0_r_wire[PIXEL_PER_CYCLE-1:0];
  wire [INPUT_BIT_WIDTH-1:0]        pipe_0_g_wire[PIXEL_PER_CYCLE-1:0];
  wire [INPUT_BIT_WIDTH-1:0]        pipe_0_b_wire[PIXEL_PER_CYCLE-1:0];
  reg [INPUT_BIT_WIDTH-1:0]         pipe_0_r[PIXEL_PER_CYCLE-1:0];
  reg [INPUT_BIT_WIDTH-1:0]         pipe_0_g[PIXEL_PER_CYCLE-1:0];
  reg [INPUT_BIT_WIDTH-1:0]         pipe_0_b[PIXEL_PER_CYCLE-1:0];
  reg                               pipe_0_tvalid = 'b0;
  wire                              pipe_0_tready;
  reg                               pipe_0_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_0_tuser;
  reg [17:0]                        pipe_0_gain;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_0_offset;


  wire [INPUT_BIT_WIDTH-1:0]        pipe_1_r_wire[PIXEL_PER_CYCLE-1:0];
  wire [INPUT_BIT_WIDTH-1:0]        pipe_1_g_wire[PIXEL_PER_CYCLE-1:0];
  wire [INPUT_BIT_WIDTH-1:0]        pipe_1_b_wire[PIXEL_PER_CYCLE-1:0];
  reg [INPUT_BIT_WIDTH-1:0]         pipe_1_r[PIXEL_PER_CYCLE-1:0];
  reg [INPUT_BIT_WIDTH-1:0]         pipe_1_g[PIXEL_PER_CYCLE-1:0];
  reg [INPUT_BIT_WIDTH-1:0]         pipe_1_b[PIXEL_PER_CYCLE-1:0];
  reg                               pipe_1_tvalid = 'b0;
  wire                              pipe_1_tready;
  reg                               pipe_1_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_1_tuser;
  reg [17:0]                        pipe_1_gain;

  wire [INPUT_BIT_WIDTH-1:0]        pipe_2_r_wire[PIXEL_PER_CYCLE-1:0];
  wire [INPUT_BIT_WIDTH-1:0]        pipe_2_g_wire[PIXEL_PER_CYCLE-1:0];
  wire [INPUT_BIT_WIDTH-1:0]        pipe_2_b_wire[PIXEL_PER_CYCLE-1:0];
  reg [INPUT_BIT_WIDTH-1:0]         pipe_2_r[PIXEL_PER_CYCLE-1:0];
  reg [INPUT_BIT_WIDTH-1:0]         pipe_2_g[PIXEL_PER_CYCLE-1:0];
  reg [INPUT_BIT_WIDTH-1:0]         pipe_2_b[PIXEL_PER_CYCLE-1:0];
  reg                               pipe_2_tvalid = 'b0;
  wire                              pipe_2_tready;
  reg                               pipe_2_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_2_tuser;

  wire [OUTPUT_BIT_WIDTH-1:0]       pipe_3_r_wire[PIXEL_PER_CYCLE-1:0];
  wire [OUTPUT_BIT_WIDTH-1:0]       pipe_3_g_wire[PIXEL_PER_CYCLE-1:0];
  wire [OUTPUT_BIT_WIDTH-1:0]       pipe_3_b_wire[PIXEL_PER_CYCLE-1:0];
  reg [OUTPUT_BIT_WIDTH-1:0]        pipe_3_r[PIXEL_PER_CYCLE-1:0];
  reg [OUTPUT_BIT_WIDTH-1:0]        pipe_3_g[PIXEL_PER_CYCLE-1:0];
  reg [OUTPUT_BIT_WIDTH-1:0]        pipe_3_b[PIXEL_PER_CYCLE-1:0];
  reg                               pipe_3_tvalid = 'b0;
  wire                              pipe_3_tready;
  reg                               pipe_3_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_3_tuser;

  // 1. capture params whenever they are valid (should be shortly after tlast)
  always_ff @ (posedge clk) begin
    if (params_tvalid == 1'b1) begin
      param_gain    <= params_tgain;
      param_offset  <= params_toffset;
    end
  end

  // 2. when tuser = 1 (start of frame), use the latest params
  // 3. subtract offset from every pixel component
  // 4. multiply every pixel component with gain and shift according to output bit width

  assign s_axis_tready = pipe_0_tready;

  // pipeline stage 0
  assign pipe_0_tready = pipe_1_tready | ~pipe_0_tvalid;

  generate

    for (genvar px = 0; px < PIXEL_PER_CYCLE; px = px + 1) begin
      localparam OFFSET = px * 3 * INPUT_BIT_WIDTH;

      assign pipe_0_g_wire[px] = s_axis_tdata[OFFSET + 1*INPUT_BIT_WIDTH-1: OFFSET + 0*INPUT_BIT_WIDTH];
      assign pipe_0_r_wire[px] = s_axis_tdata[OFFSET + 2*INPUT_BIT_WIDTH-1: OFFSET + 1*INPUT_BIT_WIDTH];
      assign pipe_0_b_wire[px] = s_axis_tdata[OFFSET + 3*INPUT_BIT_WIDTH-1: OFFSET + 2*INPUT_BIT_WIDTH];
    end

  endgenerate

  always_ff @ (posedge clk) begin
    if (pipe_0_tready == 1'b1) begin
      // register everything else
      for (integer px = 0; px < PIXEL_PER_CYCLE; px = px + 1) begin
        pipe_0_r[px]       <= pipe_0_r_wire[px];
        pipe_0_g[px]       <= pipe_0_g_wire[px];
        pipe_0_b[px]       <= pipe_0_b_wire[px];
      end

      pipe_0_tvalid  <= s_axis_tvalid;
      pipe_0_tlast   <= s_axis_tlast;
      pipe_0_tuser   <= s_axis_tuser;

      // at start of frame, capture last offset and gain values
      if (s_axis_tuser[0] == 1'b1 && s_axis_tvalid == 1'b1) begin
        pipe_0_gain   <= param_gain;
        pipe_0_offset <= param_offset;
      end
    end

    if (rstn == 1'b0) begin
      pipe_0_tvalid <= '0;
    end
  end

  // pipeline stage 1
  assign pipe_1_tready = pipe_2_tready | ~pipe_1_tvalid;

  generate

    for (genvar px = 0; px < PIXEL_PER_CYCLE; px = px + 1) begin
      assign pipe_1_g_wire[px] = subtract_and_clip(pipe_0_g[px], pipe_0_offset);
      assign pipe_1_r_wire[px] = subtract_and_clip(pipe_0_r[px], pipe_0_offset);
      assign pipe_1_b_wire[px] = subtract_and_clip(pipe_0_b[px], pipe_0_offset);
    end

  endgenerate

  always_ff @ (posedge clk) begin
    if (pipe_1_tready == 1'b1) begin
      for (integer px = 0; px < PIXEL_PER_CYCLE; px = px + 1) begin
        pipe_1_r[px]        <= pipe_1_r_wire[px];
        pipe_1_g[px]        <= pipe_1_g_wire[px];
        pipe_1_b[px]        <= pipe_1_b_wire[px];
      end
      pipe_1_tvalid   <= pipe_0_tvalid;
      pipe_1_tlast    <= pipe_0_tlast;
      pipe_1_tuser    <= pipe_0_tuser;
      pipe_1_gain     <= pipe_0_gain;
    end

    if (rstn == 1'b0) begin
      pipe_1_tvalid <= '0;
    end
  end

  // pipeline stage 2
  assign pipe_2_tready = pipe_3_tready | ~pipe_2_tvalid;

  generate

    for (genvar px = 0; px < PIXEL_PER_CYCLE; px = px + 1) begin
      assign pipe_2_g_wire[px] = mult_and_shift(pipe_1_g[px], pipe_1_gain);
      assign pipe_2_r_wire[px] = mult_and_shift(pipe_1_r[px], pipe_1_gain);
      assign pipe_2_b_wire[px] = mult_and_shift(pipe_1_b[px], pipe_1_gain);
    end

  endgenerate

  always_ff @ (posedge clk) begin
    if (pipe_2_tready == 1'b1) begin
      for (integer px = 0; px < PIXEL_PER_CYCLE; px = px + 1) begin
        pipe_2_r[px]        <= pipe_2_r_wire[px];
        pipe_2_g[px]        <= pipe_2_g_wire[px];
        pipe_2_b[px]        <= pipe_2_b_wire[px];
      end
      pipe_2_tvalid   <= pipe_1_tvalid;
      pipe_2_tlast    <= pipe_1_tlast;
      pipe_2_tuser    <= pipe_1_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_2_tvalid <= '0;
    end
  end

  // pipeline stage 3
  assign pipe_3_tready = m_axis_tready | ~pipe_3_tvalid;

  generate

    for (genvar px = 0; px < PIXEL_PER_CYCLE; px = px + 1) begin
      assign pipe_3_g_wire[px] = saturate(pipe_2_g[px]);
      assign pipe_3_r_wire[px] = saturate(pipe_2_r[px]);
      assign pipe_3_b_wire[px] = saturate(pipe_2_b[px]);
    end

  endgenerate

  always_ff @ (posedge clk) begin
    if (pipe_3_tready == 1'b1) begin
      for (integer px = 0; px < PIXEL_PER_CYCLE; px = px + 1) begin
        pipe_3_r[px]        <= pipe_3_r_wire[px];
        pipe_3_g[px]        <= pipe_3_g_wire[px];
        pipe_3_b[px]        <= pipe_3_b_wire[px];
      end
      pipe_3_tvalid   <= pipe_2_tvalid;
      pipe_3_tlast    <= pipe_2_tlast;
      pipe_3_tuser    <= pipe_2_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_3_tvalid <= '0;
    end
  end

  // assign outputs
  generate

    for (genvar px = 0; px < PIXEL_PER_CYCLE; px = px + 1) begin
      localparam OFFSET = 3 * OUTPUT_BIT_WIDTH;

      //assign m_axis_tdata[OFFSET + 1*OUTPUT_BIT_WIDTH-1: OFFSET + 0*OUTPUT_BIT_WIDTH] = pipe_3_g[px];
      //assign m_axis_tdata[OFFSET + 2*OUTPUT_BIT_WIDTH-1: OFFSET + 1*OUTPUT_BIT_WIDTH] = pipe_3_r[px];
      //assign m_axis_tdata[OFFSET + 3*OUTPUT_BIT_WIDTH-1: OFFSET + 2*OUTPUT_BIT_WIDTH] = pipe_3_b[px];

      assign m_axis_tdata[(px+1)*OFFSET-1: px*OFFSET] = {pipe_3_b[px], pipe_3_r[px], pipe_3_g[px]};
    end

  endgenerate

  assign m_axis_tvalid  = pipe_3_tvalid;
  assign m_axis_tlast   = pipe_3_tlast;
  assign m_axis_tuser   = pipe_3_tuser;

endmodule
