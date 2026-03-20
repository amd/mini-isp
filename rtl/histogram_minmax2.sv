// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module histogram_minmax2
  #(
    // Pixel per cycle. 1, 2 or 4
    parameter PIXEL_PER_CYCLE                     = 2,
    // Pixel bit width. 10, 12, 14, 16, 18, 20, 22, 24
    parameter INPUT_BIT_WIDTH                     = 24,
    // log2 of maximum number of pixel in frame, e.g. 2**24 = 16777216
    parameter LOG_MAX_PIXEL_NUM                   = 23,
    parameter DATA_WIDTH                          = 8*$rtoi($floor((PIXEL_PER_CYCLE * 3 * INPUT_BIT_WIDTH + 7)/8)),
    parameter TUSER_WIDTH                         = 1
  )
  (
    input  wire                         clk,
    input  wire                         rstn,

    input  wire  [31:0]                 force_tmin,
    input  wire  [31:0]                 force_tmax,

    input  wire  [DATA_WIDTH-1:0]       s_axis_tdata,
    input  wire                         s_axis_tvalid,
    input  wire                         s_axis_tlast,
    input  wire  [TUSER_WIDTH-1:0]      s_axis_tuser,

    output wire  [INPUT_BIT_WIDTH-1:0]  m_axis_tmin,
    output wire  [INPUT_BIT_WIDTH-1:0]  m_axis_tmax,
    output wire                         m_axis_tvalid
  );

  localparam int ADDER_WIDTH      = INPUT_BIT_WIDTH + $clog2(PIXEL_PER_CYCLE);
  localparam int DIV_CYCLE_CNT    = INPUT_BIT_WIDTH + LOG_MAX_PIXEL_NUM;

  wire [INPUT_BIT_WIDTH-1:0]        pipe_0_r_wire[PIXEL_PER_CYCLE-1:0];
  wire [INPUT_BIT_WIDTH-1:0]        pipe_0_g_wire[PIXEL_PER_CYCLE-1:0];
  wire [INPUT_BIT_WIDTH-1:0]        pipe_0_b_wire[PIXEL_PER_CYCLE-1:0];
  wire [INPUT_BIT_WIDTH+1:0]        pipe_0_gray_wire[PIXEL_PER_CYCLE-1:0];
  wire [INPUT_BIT_WIDTH-1:0]        pipe_0_gray_shift[PIXEL_PER_CYCLE-1:0];
  reg [INPUT_BIT_WIDTH-1:0]         pipe_0_gray[PIXEL_PER_CYCLE-1:0];
  reg                               pipe_0_tvalid = 'b0;
  reg                               pipe_0_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_0_tuser;

  reg [INPUT_BIT_WIDTH-1:0]         pipe_1_gray;
  reg [ADDER_WIDTH-1:0]             pipe_1_gray_wire;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_1_gray_shift;
  reg                               pipe_1_tvalid = 'b0;
  reg                               pipe_1_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_1_tuser;

  reg [INPUT_BIT_WIDTH-1:0]         pipe_2_tmax;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_2_tmin;
  reg [DIV_CYCLE_CNT-1:0]           pipe_2_accumulator;
  reg                               pipe_2_tvalid = 'b0;
  reg                               pipe_2_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_2_tuser;

  reg [INPUT_BIT_WIDTH-1:0]         pipe_3_tmax;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_3_tmin;
  reg [DIV_CYCLE_CNT-1:0]           pipe_3_mean_wire;
  reg                               pipe_3_tvalid = 'b0;
  reg                               pipe_3_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_3_tuser;

  reg [INPUT_BIT_WIDTH-1:0]         pipe_4_tmin;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_4_tmin_d1 = 'b0;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_4_tmin_d2 = 'b0;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_4_tmin_d3 = 'b0;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_4_tmin_d4 = 'b0;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_4_tmin_d5 = 'b0;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_4_tmin_d6 = 'b0;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_4_tmin_d7 = 'b0;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_4_tmax;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_4_tmax_d1 = 'b0;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_4_tmax_d2 = 'b0;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_4_tmax_d3 = 'b0;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_4_tmax_d4 = 'b0;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_4_tmax_d5 = 'b0;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_4_tmax_d6 = 'b0;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_4_tmax_d7 = 'b0;
  reg                               pipe_4_tvalid = 'b0;

  reg [INPUT_BIT_WIDTH:0]           pipe_5_tmin_d01 = 'b0;
  reg [INPUT_BIT_WIDTH:0]           pipe_5_tmin_d23 = 'b0;
  reg [INPUT_BIT_WIDTH:0]           pipe_5_tmin_d45 = 'b0;
  reg [INPUT_BIT_WIDTH:0]           pipe_5_tmin_d67 = 'b0;
  reg [INPUT_BIT_WIDTH:0]           pipe_5_tmax_d01 = 'b0;
  reg [INPUT_BIT_WIDTH:0]           pipe_5_tmax_d23 = 'b0;
  reg [INPUT_BIT_WIDTH:0]           pipe_5_tmax_d45 = 'b0;
  reg [INPUT_BIT_WIDTH:0]           pipe_5_tmax_d67 = 'b0;
  reg                               pipe_5_tvalid = 'b0;

  reg [INPUT_BIT_WIDTH+1:0]         pipe_6_tmin_d0123 = 'b0;
  reg [INPUT_BIT_WIDTH+1:0]         pipe_6_tmin_d4567 = 'b0;
  reg [INPUT_BIT_WIDTH+1:0]         pipe_6_tmax_d0123 = 'b0;
  reg [INPUT_BIT_WIDTH+1:0]         pipe_6_tmax_d4567 = 'b0;
  reg                               pipe_6_tvalid = 'b0;

  reg [INPUT_BIT_WIDTH+2:0]         pipe_7_tmin = 'b0;
  reg [INPUT_BIT_WIDTH+2:0]         pipe_7_tmax = 'b0;
  reg                               pipe_7_tvalid = 'b0;

  reg [INPUT_BIT_WIDTH-1:0]         pipe_out_tmin = 'b0;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_out_tmax = 'b0;
  reg                               pipe_out_tvalid = 'b0;

  // convert to simple gray scale
  generate

    for (genvar px = 0; px < PIXEL_PER_CYCLE; px = px + 1) begin
      localparam OFFSET = px * 3 * INPUT_BIT_WIDTH;

      assign pipe_0_g_wire[px] = s_axis_tdata[OFFSET + 1*INPUT_BIT_WIDTH-1: OFFSET + 0*INPUT_BIT_WIDTH];
      assign pipe_0_r_wire[px] = s_axis_tdata[OFFSET + 2*INPUT_BIT_WIDTH-1: OFFSET + 1*INPUT_BIT_WIDTH];
      assign pipe_0_b_wire[px] = s_axis_tdata[OFFSET + 3*INPUT_BIT_WIDTH-1: OFFSET + 2*INPUT_BIT_WIDTH];

      // convert to gray
      assign pipe_0_gray_wire[px] = {1'b0, pipe_0_r_wire[px], 1'b0} + {2'b0, pipe_0_g_wire[px]} + {2'b0, pipe_0_b_wire[px]} >> 2;
      assign pipe_0_gray_shift[px] = pipe_0_gray_wire[px][INPUT_BIT_WIDTH-1:0];
    end

  endgenerate

  // pipeline stage 0
  always_ff @ (posedge clk) begin
    // register everything else
    for (integer px = 0; px < PIXEL_PER_CYCLE; px = px + 1) begin
      pipe_0_gray[px]    <= pipe_0_gray_shift[px];
    end
    pipe_0_tvalid  <= s_axis_tvalid;
    pipe_0_tlast   <= s_axis_tlast;
    pipe_0_tuser   <= s_axis_tuser;

    if (rstn == 1'b0) begin
      pipe_0_tvalid <= '0;
    end
  end

  // all pixel per cycle into one
  generate

    if (PIXEL_PER_CYCLE == 1) begin
      assign pipe_1_gray_wire       = pipe_0_gray[0];
    end

    if (PIXEL_PER_CYCLE == 2) begin
      assign pipe_1_gray_wire       = ({1'b0, pipe_0_gray[0]} + {1'b0, pipe_0_gray[1]}) >> 1;
    end

    if (PIXEL_PER_CYCLE == 4) begin
      assign pipe_1_gray_wire       = ({2'b00, pipe_0_gray[0]} + {2'b00, pipe_0_gray[1]} + {2'b00, pipe_0_gray[2]} + {2'b00, pipe_0_gray[3]}) >> 2;
    end

    assign pipe_1_gray_shift = pipe_1_gray_wire[INPUT_BIT_WIDTH-1:0];

  endgenerate

  // pipeline stage 1
  always_ff @ (posedge clk) begin
    // register everything else
    pipe_1_gray    <= pipe_1_gray_shift;
    pipe_1_tvalid  <= pipe_0_tvalid;
    pipe_1_tlast   <= pipe_0_tlast;
    pipe_1_tuser   <= pipe_0_tuser;

    if (rstn == 1'b0) begin
      pipe_1_tvalid <= '0;
    end
  end

  // pipeline stage 2
  always_ff @ (posedge clk) begin

    // update control variables in case it is start of frame!
    if (pipe_1_tvalid == 1'b1) begin

      // update values; reset with start of frame
      if ((pipe_1_gray > pipe_2_tmax) || (pipe_1_tuser[0] == 1'b1)) begin
        pipe_2_tmax <= pipe_1_gray;
      end

      if ((pipe_1_gray < pipe_2_tmin) || (pipe_1_tuser[0] == 1'b1)) begin
        pipe_2_tmin <= pipe_1_gray;
      end
    end

    pipe_2_tvalid  <= pipe_1_tvalid;
    pipe_2_tlast   <= pipe_1_tlast;
    pipe_2_tuser   <= pipe_1_tuser;

    // accumulator; reset with start of frame
    pipe_2_accumulator <= pipe_2_accumulator + {{LOG_MAX_PIXEL_NUM{1'b0}}, pipe_1_gray};
    if (pipe_1_tuser[0] == 1'b1) begin
      pipe_2_accumulator <= {{LOG_MAX_PIXEL_NUM{1'b0}}, pipe_1_gray};
    end

    if (rstn == 1'b0) begin
      pipe_2_tvalid <= '0;
    end
  end

  generate

    if (PIXEL_PER_CYCLE == 1) begin
      assign pipe_3_mean_wire = pipe_2_accumulator >> (LOG_MAX_PIXEL_NUM);
    end

    if (PIXEL_PER_CYCLE == 2) begin
      assign pipe_3_mean_wire = pipe_2_accumulator >> (LOG_MAX_PIXEL_NUM-1);
    end

    if (PIXEL_PER_CYCLE == 4) begin
      assign pipe_3_mean_wire = pipe_2_accumulator >> (LOG_MAX_PIXEL_NUM-2);
    end

  endgenerate

  // pipeline stage 3
  always_ff @ (posedge clk) begin
    pipe_3_tmax <= pipe_2_tmax;
    pipe_3_tmin <= pipe_2_tmin;

    pipe_3_tvalid   <= pipe_2_tvalid;
    pipe_3_tlast    <= pipe_2_tlast;
    pipe_3_tuser    <= pipe_2_tuser;

    if (rstn == 1'b0) begin
      pipe_3_tvalid <= '0;
    end
  end

  // pipeline stage 4
  always_ff @ (posedge clk) begin

    if ((pipe_3_tvalid == 1'b1) && (pipe_3_tlast == 1'b1)) begin
      pipe_4_tmin <= pipe_3_tmin;
      pipe_4_tmax <= pipe_3_tmax;
    end

    if ((pipe_3_tvalid == 1'b1) && (pipe_3_tuser[0] == 1'b1))  begin
      pipe_4_tmin_d1 <= pipe_4_tmin;
      pipe_4_tmin_d2 <= pipe_4_tmin_d1;
      pipe_4_tmin_d3 <= pipe_4_tmin_d2;
      pipe_4_tmin_d4 <= pipe_4_tmin_d3;
      pipe_4_tmin_d5 <= pipe_4_tmin_d4;
      pipe_4_tmin_d6 <= pipe_4_tmin_d5;
      pipe_4_tmin_d7 <= pipe_4_tmin_d6;

      pipe_4_tmax_d1 <= pipe_4_tmax;
      pipe_4_tmax_d2 <= pipe_4_tmax_d1;
      pipe_4_tmax_d3 <= pipe_4_tmax_d2;
      pipe_4_tmax_d4 <= pipe_4_tmax_d3;
      pipe_4_tmax_d5 <= pipe_4_tmax_d4;
      pipe_4_tmax_d6 <= pipe_4_tmax_d5;
      pipe_4_tmax_d7 <= pipe_4_tmax_d6;
    end

    pipe_4_tvalid  <= pipe_3_tvalid & pipe_3_tlast;

    if (rstn == 1'b0) begin
      pipe_4_tvalid <= '0;
    end
  end

  // pipeline stage 5
  always_ff @ (posedge clk) begin
    pipe_5_tmin_d01 <= pipe_4_tmin + pipe_4_tmin_d1;
    pipe_5_tmin_d23 <= pipe_4_tmin_d2 + pipe_4_tmin_d3;
    pipe_5_tmin_d45 <= pipe_4_tmin_d4 + pipe_4_tmin_d5;
    pipe_5_tmin_d67 <= pipe_4_tmin_d6 + pipe_4_tmin_d7;

    pipe_5_tmax_d01 <= pipe_4_tmax + pipe_4_tmax_d1;
    pipe_5_tmax_d23 <= pipe_4_tmax_d2 + pipe_4_tmax_d3;
    pipe_5_tmax_d45 <= pipe_4_tmax_d4 + pipe_4_tmax_d5;
    pipe_5_tmax_d67 <= pipe_4_tmax_d6 + pipe_4_tmax_d7;

    pipe_5_tvalid  <= pipe_4_tvalid;

    if (rstn == 1'b0) begin
      pipe_5_tvalid <= '0;
    end
  end

  // pipeline stage 6
  always_ff @ (posedge clk) begin
    pipe_6_tmin_d0123 <= pipe_5_tmin_d01 + pipe_5_tmin_d23;
    pipe_6_tmin_d4567 <= pipe_5_tmin_d45 + pipe_5_tmin_d67;

    pipe_6_tmax_d0123 <= pipe_5_tmax_d01 + pipe_5_tmax_d23;
    pipe_6_tmax_d4567 <= pipe_5_tmax_d45 + pipe_5_tmax_d67;

    pipe_6_tvalid  <= pipe_5_tvalid;

    if (rstn == 1'b0) begin
      pipe_6_tvalid <= '0;
    end
  end

  // output stage
  always_ff @ (posedge clk) begin
    pipe_7_tmin <= pipe_6_tmin_d0123 + pipe_6_tmin_d4567;
    pipe_7_tmax <= pipe_6_tmax_d0123 + pipe_6_tmax_d4567;

    // output with end of line
    pipe_7_tvalid   <= pipe_6_tvalid;

    if (rstn == 1'b0) begin
      pipe_7_tvalid <= '0;
    end
  end

  // output stage
  always_ff @ (posedge clk) begin
    if (force_tmin[31] == 1'b1) begin
      pipe_out_tmin <= force_tmin[INPUT_BIT_WIDTH-1:0];
    end else begin
      pipe_out_tmin <= pipe_7_tmin[INPUT_BIT_WIDTH+2:3];
    end

    if (force_tmax[31] == 1'b1) begin
      pipe_out_tmax <= force_tmax[INPUT_BIT_WIDTH-1:0];
    end else begin
      pipe_out_tmax <= pipe_7_tmax[INPUT_BIT_WIDTH+2:3];
    end

    // output with end of line
    pipe_out_tvalid   <= pipe_7_tvalid;

    if (rstn == 1'b0) begin
      pipe_out_tvalid <= '0;
    end
  end

  // assign outputs
  assign m_axis_tmin    = pipe_out_tmin;
  assign m_axis_tmax    = pipe_out_tmax;
  assign m_axis_tvalid  = pipe_out_tvalid;

endmodule
