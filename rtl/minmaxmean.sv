// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module minmaxmean
  #(
    // Pixel per cycle. 1, 2 or 4
    parameter PIXEL_PER_CYCLE                     = 1,
    // Pixel bit width. 8, 10, 12, 14, 16, 18, 20, 22, 24
    parameter PIXEL_BIT_WIDTH                     = 24,
    // log2 of maximum number of pixel in frame, e.g. 2**24 = 16777216
    parameter LOG_MAX_PIXEL_NUM                   = 24,
    parameter DATA_WIDTH                          = 8*$rtoi($floor((PIXEL_PER_CYCLE * PIXEL_BIT_WIDTH + 7)/8)),
    parameter TUSER_WIDTH                         = 1
  )
  (
    input  wire                         clk,
    input  wire                         rstn,

    input  wire  [DATA_WIDTH-1:0]       s_axis_tdata,
    input  wire                         s_axis_tvalid,
    output wire                         s_axis_tready,
    input  wire                         s_axis_tlast,
    input  wire  [TUSER_WIDTH-1:0]      s_axis_tuser,

    output wire  [PIXEL_BIT_WIDTH-1:0]  min,
    output wire  [PIXEL_BIT_WIDTH-1:0]  max,
    output wire  [PIXEL_BIT_WIDTH-1:0]  mean,
    output wire                         valid
  );

  localparam DIV_CYCLE_CNT_WIDTH              = $clog2(PIXEL_BIT_WIDTH + LOG_MAX_PIXEL_NUM);
  localparam DIV_CYCLE_CNT                    = PIXEL_BIT_WIDTH + LOG_MAX_PIXEL_NUM;

  reg [PIXEL_BIT_WIDTH-1:0]                   pipe_0_tdata_min;
  reg [PIXEL_BIT_WIDTH-1:0]                   pipe_0_tdata_max;
  reg [LOG_MAX_PIXEL_NUM + PIXEL_BIT_WIDTH-1:0]    pipe_0_tdata_accumulator;
  reg [LOG_MAX_PIXEL_NUM-1:0]                 pipe_0_tdata_count;
  reg                                         pipe_0_tvalid = 'b0;
  reg                                         pipe_0_tlast;
  reg [TUSER_WIDTH-1:0]                       pipe_0_tuser;

  reg [LOG_MAX_PIXEL_NUM + PIXEL_BIT_WIDTH-1:0]    accumulator;
  reg [LOG_MAX_PIXEL_NUM-1:0]                 count;
  reg                                         div_start;

  reg [PIXEL_BIT_WIDTH-1:0]                   min_out;
  reg [PIXEL_BIT_WIDTH-1:0]                   max_out;
  wire [LOG_MAX_PIXEL_NUM + PIXEL_BIT_WIDTH-1:0]   mean_out;
  wire                                        valid_out;


  // pipeline stage 0
  // ...always ready
  assign s_axis_tready  = 1'b1;

  // TODO: 1 PPC supported only at the moment!
  always_ff @ (posedge clk) begin
    // register everything else
    pipe_0_tvalid  <= s_axis_tvalid;
    pipe_0_tlast   <= s_axis_tlast;
    pipe_0_tuser   <= s_axis_tuser;

    if (s_axis_tvalid == 1'b1) begin
      // maximum finder; reset with start of frame
      if ((s_axis_tdata[PIXEL_BIT_WIDTH-1:0] > pipe_0_tdata_max) || (s_axis_tuser[0] == 1'b1)) begin
        pipe_0_tdata_max <= s_axis_tdata[PIXEL_BIT_WIDTH-1:0];
      end

      // minimum finder; reset with start of frame
      if ((s_axis_tdata[PIXEL_BIT_WIDTH-1:0] < pipe_0_tdata_min) || (s_axis_tuser[0] == 1'b1)) begin
        pipe_0_tdata_min <= s_axis_tdata[PIXEL_BIT_WIDTH-1:0];
      end

      // pixel count; reset with start of frame
      // TODO: needs to support more than 1 PPC
      pipe_0_tdata_count <= pipe_0_tdata_count + 1;
      if (s_axis_tuser[0] == 1'b1) begin
        // initialize to 1, so division by zero should never be a thing
        pipe_0_tdata_count <= 'b1;
      end

      // accumulator; reset with start of frame
      pipe_0_tdata_accumulator <= pipe_0_tdata_accumulator + {{LOG_MAX_PIXEL_NUM{1'b0}}, s_axis_tdata[PIXEL_BIT_WIDTH-1:0]};
      if (s_axis_tuser[0] == 1'b1) begin
        pipe_0_tdata_accumulator <= {{LOG_MAX_PIXEL_NUM{1'b0}}, s_axis_tdata[PIXEL_BIT_WIDTH-1:0]};
      end
    end

    if (rstn == 1'b0) begin
      pipe_0_tvalid   <= '0;
    end

  end

  // divider calculation and output
  always_ff @ (posedge clk) begin
    div_start     <= 1'b0;

    if ((pipe_0_tvalid == 1'b1) && (pipe_0_tlast == 1'b1)) begin
      min_out       <= pipe_0_tdata_min;
      max_out       <= pipe_0_tdata_max;
      accumulator   <= pipe_0_tdata_accumulator;
      count         <= pipe_0_tdata_count;
      div_start     <= 1'b1;
    end
  end

  non_restoring_unsigned_divider #(
    .NOM_DATA_WIDTH         (LOG_MAX_PIXEL_NUM+PIXEL_BIT_WIDTH),
    .DEN_DATA_WIDTH         (LOG_MAX_PIXEL_NUM)
  ) divider_inst
  (
    .clk                    (clk),
    .rstn                   (rstn),
    .nom                    (accumulator),
    .den                    (count),
    .start                  (div_start),
    .div                    (mean_out),
    .rem                    (),
    .done                   (valid_out)
  );

  // assign outputs
  assign min    = min_out;
  assign max    = max_out;
  assign mean   = mean_out[PIXEL_BIT_WIDTH-1:0];
  assign valid  = valid_out;

endmodule
