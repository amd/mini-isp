// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module xyz_to_rgb
  #(
    // Pixel per cycle. 1, 2 or 4
    parameter PIXEL_PER_CYCLE                     = 4,
    // Pixel bit width. 8, 10, 12, 14, 16, 18
    parameter PIXEL_BIT_WIDTH                     = 14,
    parameter DATA_WIDTH                          = 8*$rtoi($floor((3 * PIXEL_PER_CYCLE * PIXEL_BIT_WIDTH + 7)/8)),
    parameter TUSER_WIDTH                         = 1
  )
  (
    input  wire                     clk,
    input  wire                     rstn,

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

  function [PIXEL_BIT_WIDTH-1:0] shift_and_saturate( input [PIXEL_BIT_WIDTH+16-1:0] mult_result );
    begin
      shift_and_saturate = mult_result[PIXEL_BIT_WIDTH+16-1:PIXEL_BIT_WIDTH+7-1] == 'b0 ? mult_result[PIXEL_BIT_WIDTH+7-1:7] : '1;
    end
  endfunction

  reg [DATA_WIDTH-1:0]  pipe_0_tdata;
  reg                   pipe_0_tvalid = 'b0;
  wire                  pipe_0_tready;
  reg                   pipe_0_tlast;
  reg [TUSER_WIDTH-1:0] pipe_0_tuser;

  reg [DATA_WIDTH-1:0]  pipe_1_tdata;
  reg                   pipe_1_tvalid = 'b0;
  wire                  pipe_1_tready;
  reg                   pipe_1_tlast;
  reg [TUSER_WIDTH-1:0] pipe_1_tuser;

  // pipeline stage 0
  assign pipe_0_tready = pipe_1_tready | ~pipe_0_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_0_tready == 1'b1) begin
      // register everything
      pipe_0_tdata   <= s_axis_tdata;
      pipe_0_tvalid  <= s_axis_tvalid;
      pipe_0_tlast   <= s_axis_tlast;
      pipe_0_tuser   <= s_axis_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_0_tvalid   <= 1'b0;
    end
  end

  // pipeline stage 1
  assign pipe_1_tready = m_axis_tready | ~pipe_1_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_1_tready == 1'b1) begin
      pipe_1_tdata   <= pipe_0_tdata;
      pipe_1_tvalid  <= pipe_0_tvalid;
      pipe_1_tlast   <= pipe_0_tlast;
      pipe_1_tuser   <= pipe_0_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_1_tvalid   <= 1'b0;
    end
  end

  // assign outputs
  assign s_axis_tready  = pipe_0_tready;
  assign m_axis_tdata   = pipe_1_tdata;
  assign m_axis_tvalid  = pipe_1_tvalid;
  assign m_axis_tlast   = pipe_1_tlast;
  assign m_axis_tuser   = pipe_1_tuser;

endmodule
