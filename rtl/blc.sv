// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module blc
  #(
    // Pixel per cycle. 1, 2 or 4
    parameter PIXEL_PER_CYCLE                     = 4,
    // Pixel bit width. 8, 10, 12, 14, 16, 18
    parameter PIXEL_BIT_WIDTH                     = 14,
    parameter DATA_WIDTH                          = 8*$rtoi($floor((PIXEL_PER_CYCLE * PIXEL_BIT_WIDTH + 7)/8)),
    parameter TUSER_WIDTH                         = 1
  )
  (
    input  wire                     clk,
    input  wire                     rstn,

    input  wire  [15:0]             black_level,

    input  wire  [DATA_WIDTH-1:0]   s_axis_tdata,
    input  wire                     s_axis_tvalid,
    output wire                     s_axis_tready,
    input  wire                     s_axis_tlast,
    input  wire  [TUSER_WIDTH-1:0]  s_axis_tuser,

    output wire  [DATA_WIDTH-1:0]   m_axis_tdata,
    output wire                     m_axis_tvalid,
    input  wire                     m_axis_tready,
    output wire                     m_axis_tlast,
    output wire  [TUSER_WIDTH-1:0]  m_axis_tuser
  );

  parameter INT_DATA_WIDTH = (PIXEL_BIT_WIDTH > 16) ? PIXEL_BIT_WIDTH + 1 : 17;

  function [PIXEL_BIT_WIDTH-1:0] subtract_and_saturate( input [INT_DATA_WIDTH-1:0] subtract_result );
    begin
      subtract_and_saturate = subtract_result[INT_DATA_WIDTH-1] == 'b0 ? subtract_result[PIXEL_BIT_WIDTH-1:0] : '0;
    end
  endfunction

  reg [INT_DATA_WIDTH-1:0]    int_black_level = 'b0;

  wire [INT_DATA_WIDTH-1:0]   pipe_0_pixel_0_wire;
  wire [INT_DATA_WIDTH-1:0]   pipe_0_pixel_1_wire;
  wire [INT_DATA_WIDTH-1:0]   pipe_0_pixel_2_wire;
  wire [INT_DATA_WIDTH-1:0]   pipe_0_pixel_3_wire;
  reg  [INT_DATA_WIDTH-1:0]   pipe_0_pixel_0;
  reg  [INT_DATA_WIDTH-1:0]   pipe_0_pixel_1;
  reg  [INT_DATA_WIDTH-1:0]   pipe_0_pixel_2;
  reg  [INT_DATA_WIDTH-1:0]   pipe_0_pixel_3;
  reg                         pipe_0_tvalid = 'b0;
  wire                        pipe_0_tready;
  reg                         pipe_0_tlast;
  reg [TUSER_WIDTH-1:0]       pipe_0_tuser;

  wire [DATA_WIDTH-1:0]       pipe_1_tdata_wire;
  wire [PIXEL_BIT_WIDTH-1:0]  pipe_1_pixel_0_wire;
  wire [PIXEL_BIT_WIDTH-1:0]  pipe_1_pixel_1_wire;
  wire [PIXEL_BIT_WIDTH-1:0]  pipe_1_pixel_2_wire;
  wire [PIXEL_BIT_WIDTH-1:0]  pipe_1_pixel_3_wire;
  reg  [PIXEL_BIT_WIDTH-1:0]  pipe_1_pixel_0;
  reg  [PIXEL_BIT_WIDTH-1:0]  pipe_1_pixel_1;
  reg  [PIXEL_BIT_WIDTH-1:0]  pipe_1_pixel_2;
  reg  [PIXEL_BIT_WIDTH-1:0]  pipe_1_pixel_3;
  reg                         pipe_1_tvalid = 'b0;
  wire                        pipe_1_tready;
  reg                         pipe_1_tlast;
  reg [TUSER_WIDTH-1:0]       pipe_1_tuser;

  reg [DATA_WIDTH-1:0]        pipe_2_tdata;
  reg                         pipe_2_tvalid = 'b0;
  wire                        pipe_2_tready;
  reg                         pipe_2_tlast;
  reg [TUSER_WIDTH-1:0]       pipe_2_tuser;

  // pipeline stage 0
  assign pipe_0_tready = pipe_1_tready | ~pipe_0_tvalid;

  generate

    assign pipe_0_pixel_0_wire[PIXEL_BIT_WIDTH-1:0] = s_axis_tdata[PIXEL_BIT_WIDTH-1:0];

    if (PIXEL_PER_CYCLE > 1) begin
      assign pipe_0_pixel_1_wire[PIXEL_BIT_WIDTH-1:0] = s_axis_tdata[2*PIXEL_BIT_WIDTH-1:PIXEL_BIT_WIDTH];
    end

    if (PIXEL_PER_CYCLE > 2) begin
      assign pipe_0_pixel_2_wire[PIXEL_BIT_WIDTH-1:0] = s_axis_tdata[3*PIXEL_BIT_WIDTH-1:2*PIXEL_BIT_WIDTH];
    end

    if (PIXEL_PER_CYCLE > 3) begin
      assign pipe_0_pixel_3_wire[PIXEL_BIT_WIDTH-1:0] = s_axis_tdata[4*PIXEL_BIT_WIDTH-1:3*PIXEL_BIT_WIDTH];
    end

  endgenerate

  always_ff @ (posedge clk) begin
    if (pipe_0_tready == 1'b1) begin
      if (s_axis_tvalid == 1'b1) begin
        if (s_axis_tuser[0] == 1'b1) begin
          // capture black level at start of frame
          int_black_level[15:0] <= black_level;
        end
      end

      // register everything else
      pipe_0_pixel_0 <= pipe_0_pixel_0_wire;
      pipe_0_pixel_1 <= pipe_0_pixel_1_wire;
      pipe_0_pixel_2 <= pipe_0_pixel_2_wire;
      pipe_0_pixel_3 <= pipe_0_pixel_3_wire;
      pipe_0_tvalid  <= s_axis_tvalid;
      pipe_0_tlast   <= s_axis_tlast;
      pipe_0_tuser   <= s_axis_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_0_tvalid   <= '0;
    end
  end

  // pipeline stage 1
  assign pipe_1_tready = pipe_2_tready | ~pipe_1_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_1_tready == 1'b1) begin
      pipe_1_pixel_0 <= subtract_and_saturate(pipe_0_pixel_0 - int_black_level);
      pipe_1_pixel_1 <= subtract_and_saturate(pipe_0_pixel_1 - int_black_level);
      pipe_1_pixel_2 <= subtract_and_saturate(pipe_0_pixel_2 - int_black_level);
      pipe_1_pixel_3 <= subtract_and_saturate(pipe_0_pixel_3 - int_black_level);
      pipe_1_tvalid  <= pipe_0_tvalid;
      pipe_1_tlast   <= pipe_0_tlast;
      pipe_1_tuser   <= pipe_0_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_1_tvalid   <= '0;
    end
  end

  // pipeline stage 1
  assign pipe_2_tready = m_axis_tready | ~pipe_2_tvalid;

  // output generation
  generate

    assign pipe_1_tdata_wire[PIXEL_BIT_WIDTH-1:0] = pipe_1_pixel_0[PIXEL_BIT_WIDTH-1:0];

    if (PIXEL_PER_CYCLE > 1) begin
      assign pipe_1_tdata_wire[2*PIXEL_BIT_WIDTH-1:PIXEL_BIT_WIDTH] = pipe_1_pixel_1[PIXEL_BIT_WIDTH-1:0];
    end

    if (PIXEL_PER_CYCLE > 2) begin
      assign pipe_1_tdata_wire[3*PIXEL_BIT_WIDTH-1:2*PIXEL_BIT_WIDTH] = pipe_1_pixel_2[PIXEL_BIT_WIDTH-1:0];
    end

    if (PIXEL_PER_CYCLE > 3) begin
      assign pipe_1_tdata_wire[4*PIXEL_BIT_WIDTH-1:3*PIXEL_BIT_WIDTH] = pipe_1_pixel_3[PIXEL_BIT_WIDTH-1:0];
    end

  endgenerate

  always_ff @ (posedge clk) begin
    if (pipe_2_tready == 1'b1) begin
      pipe_2_tdata   <= pipe_1_tdata_wire;
      pipe_2_tvalid  <= pipe_1_tvalid;
      pipe_2_tlast   <= pipe_1_tlast;
      pipe_2_tuser   <= pipe_1_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_2_tvalid   <= '0;
    end
  end

  // assign outputs
  assign s_axis_tready  = pipe_0_tready;
  assign m_axis_tdata   = pipe_2_tdata;
  assign m_axis_tvalid  = pipe_2_tvalid;
  assign m_axis_tlast   = pipe_2_tlast;
  assign m_axis_tuser   = pipe_2_tuser;

endmodule
