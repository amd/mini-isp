// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module histogram_offsetgain
  #(
    // Pixel bit width. 10, 12, 14, 16, 18, 20, 22, 24
    parameter INPUT_BIT_WIDTH                     = 24,
    parameter OUTPUT_BIT_WIDTH                    = 8
  )
  (
    input  wire                         clk,
    input  wire                         rstn,

    input  wire  [INPUT_BIT_WIDTH-1:0]  s_axis_tmin,
    input  wire  [INPUT_BIT_WIDTH-1:0]  s_axis_tmax,
    input  wire                         s_axis_tvalid,

    output wire  [17:0]                 m_axis_tgain,
    output wire  [INPUT_BIT_WIDTH-1:0]  m_axis_toffset,
    output wire                         m_axis_tvalid
  );

  localparam int MIN_DIFFERENCE = 2 ** OUTPUT_BIT_WIDTH;

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

  reg [INPUT_BIT_WIDTH-1:0]         pipe_0_tdiff;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_0_tmin;
  reg                               pipe_0_tvalid = 'b0;

  reg [INPUT_BIT_WIDTH-1:0]         pipe_1_tdiff;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_1_tmin;
  reg                               pipe_1_tvalid = 'b0;

  wire [INPUT_BIT_WIDTH:0]          divider_one;
  reg                               divider_done;
  reg [INPUT_BIT_WIDTH:0]           divider_out;
  reg [INPUT_BIT_WIDTH-1:0]         divider_rem;

  reg [17:0]                        pipe_2_tgain;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_2_toffset;
  reg                               pipe_2_tvalid = 'b0;

  // pipeline stage 0
  always_ff @ (posedge clk) begin
    if (s_axis_tvalid == 1'b1) begin
      // register everything else
      pipe_0_tdiff  <= subtract_and_clip(s_axis_tmax, s_axis_tmin);
      pipe_0_tmin   <= s_axis_tmin;
    end

    pipe_0_tvalid  <= s_axis_tvalid;

    if (rstn == 1'b0) begin
      pipe_0_tvalid <= '0;
    end
  end

  // pipeline stage 1
  always_ff @ (posedge clk) begin
    if (pipe_0_tvalid == 1'b1) begin
      pipe_1_tmin   <= pipe_0_tmin;
      pipe_1_tdiff  <= pipe_0_tdiff;

      if (pipe_0_tdiff < MIN_DIFFERENCE[INPUT_BIT_WIDTH-1:0]) begin
        pipe_1_tdiff  <= MIN_DIFFERENCE[INPUT_BIT_WIDTH-1:0];
      end
    end

    pipe_1_tvalid <= pipe_0_tvalid;

    if (rstn == 1'b0) begin
      pipe_1_tvalid <= '0;
    end
  end

  assign divider_one = {1'b1, {(INPUT_BIT_WIDTH){1'b0}}};

  non_restoring_unsigned_divider #(
    .NOM_DATA_WIDTH         (INPUT_BIT_WIDTH+1),
    .DEN_DATA_WIDTH         (INPUT_BIT_WIDTH)
  ) divider_inst
  (
    .clk                    (clk),
    .rstn                   (rstn),

    .nom                    (divider_one),
    .den                    (pipe_1_tdiff),
    .start                  (pipe_1_tvalid),

    .div                    (divider_out),
    .rem                    (divider_rem),
    .done                   (divider_done)
  );

  // output stage
  always_ff @ (posedge clk) begin
    // slightly sloppy, probably not critical...
    // in theory, need to ensure that gain and offset are both valid
    // but gain comes many many cycles after offset
    if (pipe_1_tvalid == 1'b1) begin
      pipe_2_toffset  <= pipe_1_tmin;
    end

    if (divider_done == 1'b1) begin
      pipe_2_tgain    <= divider_out[17:0];
    end

    pipe_2_tvalid   <= divider_done;

    if (rstn == 1'b0) begin
      pipe_2_tvalid <= '0;
    end
  end

  // assign outputs
  assign m_axis_tgain   = pipe_2_tgain;
  assign m_axis_toffset = pipe_2_toffset;
  assign m_axis_tvalid  = pipe_2_tvalid;

endmodule
