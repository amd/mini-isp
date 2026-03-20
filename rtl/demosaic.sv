// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module demosaic
  #(
    // CFA orientation. CFA_BG=0, CFA_GB=1, CFA_GR=2, CFA_RG=3
    parameter CFA_ORIENTATION                     = 3,
    // Resolution. RES_2K=2048, RES_4K=4096, RES_8K=8192
    parameter MAX_RESOLUTION                      = 4096,
    // Pixel per cycle. 1, 2 or 4
    parameter PIXEL_PER_CYCLE                     = 4,
    // Pixel bit width. 8, 10, 12, 14, 16, 18
    parameter PIXEL_BIT_WIDTH                     = 12,
    parameter S_AXIS_DATA_WIDTH                   = 8*$rtoi($floor((PIXEL_PER_CYCLE * PIXEL_BIT_WIDTH + 7)/8)),
    parameter M_AXIS_DATA_WIDTH                   = 8*$rtoi($floor((PIXEL_PER_CYCLE * 3 * PIXEL_BIT_WIDTH + 7)/8)),
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

    output wire  [M_AXIS_DATA_WIDTH-1:0]  m_axis_tdata,
    output wire                           m_axis_tvalid,
    input  wire                           m_axis_tready,
    output wire                           m_axis_tlast,
    output wire  [TUSER_WIDTH-1:0]        m_axis_tuser
  );

  function [PIXEL_BIT_WIDTH-1:0] shift_and_saturate( input [PIXEL_BIT_WIDTH+11:0] data );
    begin
      if (data[PIXEL_BIT_WIDTH+11] == 1'b1) begin
        // negative number, set to zero
        shift_and_saturate = '0;
      end else if (data[PIXEL_BIT_WIDTH+10:PIXEL_BIT_WIDTH+4] != '0) begin
        // overflow, set to maximum allowed value
        shift_and_saturate = '1;
      end else begin
        // all good, shift and output
        shift_and_saturate = data[PIXEL_BIT_WIDTH+3:4];
      end
    end
  endfunction

  // 5x5 context required. 5 rows fixed.
  localparam NUM_ROWS     = 5;
  // one pixel: 5 columns; two pixel: 6 columns; four pixel: 8 columns
  localparam NUM_COLUMNS  = 4 + PIXEL_PER_CYCLE;
  // pipeline stages: one pixel: 5 stages; two pixel: 3 stages; four pixel: 2 stages
  localparam PIPE_STAGES = $rtoi($floor(NUM_COLUMNS / PIXEL_PER_CYCLE));
  // line buffer output data width
  localparam LINEBUF_DATA_WIDTH = NUM_ROWS * S_AXIS_DATA_WIDTH;
  // CFA pattern line init
  localparam bit [0:0] LINE_INIT = CFA_ORIENTATION[1:1];
  // CFA pattern pixel init
  localparam bit [0:0] PIXEL_INIT = CFA_ORIENTATION[0:0];

  reg [0:0] current_pixel = 1'b0;
  reg [0:0] current_line  = 1'b0;

  reg [PIXEL_BIT_WIDTH+1:0] pipe_0_center             [0:PIXEL_PER_CYCLE-1]; // no compute
  reg [PIXEL_BIT_WIDTH+1:0] pipe_0_outer_horizontal   [0:PIXEL_PER_CYCLE-1]; // add
  reg [PIXEL_BIT_WIDTH+1:0] pipe_0_outer_vertical     [0:PIXEL_PER_CYCLE-1]; // add
  reg [PIXEL_BIT_WIDTH+1:0] pipe_0_inner_horizontal   [0:PIXEL_PER_CYCLE-1]; // add
  reg [PIXEL_BIT_WIDTH+1:0] pipe_0_inner_vertical     [0:PIXEL_PER_CYCLE-1]; // add
  reg [PIXEL_BIT_WIDTH+1:0] pipe_0_inner_top          [0:PIXEL_PER_CYCLE-1]; // add
  reg [PIXEL_BIT_WIDTH+1:0] pipe_0_inner_bottom       [0:PIXEL_PER_CYCLE-1]; // add
  reg                       pipe_0_tvalid = 'b0;
  wire                      pipe_0_tready;
  reg                       pipe_0_tlast;
  reg [TUSER_WIDTH-1:0]     pipe_0_tuser;

  reg [PIXEL_BIT_WIDTH+5:0] pipe_1_center             [0:PIXEL_PER_CYCLE-1]; // no compute
  reg [PIXEL_BIT_WIDTH+5:0] pipe_1_center_x5          [0:PIXEL_PER_CYCLE-1]; // add + shift
  reg [PIXEL_BIT_WIDTH+5:0] pipe_1_center_x6          [0:PIXEL_PER_CYCLE-1]; // add + shift
  reg [PIXEL_BIT_WIDTH+5:0] pipe_1_outer_horizontal   [0:PIXEL_PER_CYCLE-1]; // no compute
  reg [PIXEL_BIT_WIDTH+5:0] pipe_1_outer_vertical     [0:PIXEL_PER_CYCLE-1]; // no compute
  reg [PIXEL_BIT_WIDTH+5:0] pipe_1_outer_cross        [0:PIXEL_PER_CYCLE-1]; // add
  reg [PIXEL_BIT_WIDTH+5:0] pipe_1_inner_h_outer_v_x2 [0:PIXEL_PER_CYCLE-1]; // add
  reg [PIXEL_BIT_WIDTH+5:0] pipe_1_inner_v_outer_h_x2 [0:PIXEL_PER_CYCLE-1]; // add
  reg [PIXEL_BIT_WIDTH+5:0] pipe_1_inner_corner       [0:PIXEL_PER_CYCLE-1]; // add
  reg [PIXEL_BIT_WIDTH+5:0] pipe_1_inner_cross        [0:PIXEL_PER_CYCLE-1]; // add
  reg                       pipe_1_tvalid = 'b0;
  wire                      pipe_1_tready;
  reg                       pipe_1_tlast;
  reg [TUSER_WIDTH-1:0]     pipe_1_tuser;

  reg [PIXEL_BIT_WIDTH+9:0] pipe_2_center             [0:PIXEL_PER_CYCLE-1]; // no compute
  reg [PIXEL_BIT_WIDTH+9:0] pipe_2_center_cross_x2    [0:PIXEL_PER_CYCLE-1]; // add
  reg [PIXEL_BIT_WIDTH+9:0] pipe_2_outer_cross_x2     [0:PIXEL_PER_CYCLE-1]; // no compute
  reg [PIXEL_BIT_WIDTH+9:0] pipe_2_outer_cross_x3     [0:PIXEL_PER_CYCLE-1]; // add
  reg [PIXEL_BIT_WIDTH+9:0] pipe_2_inner_c_outer_h_x2 [0:PIXEL_PER_CYCLE-1]; // add
  reg [PIXEL_BIT_WIDTH+9:0] pipe_2_inner_c_outer_v_x2 [0:PIXEL_PER_CYCLE-1]; // add
  reg [PIXEL_BIT_WIDTH+9:0] pipe_2_rb_at_g1_x2        [0:PIXEL_PER_CYCLE-1]; // add
  reg [PIXEL_BIT_WIDTH+9:0] pipe_2_rb_at_g2_x2        [0:PIXEL_PER_CYCLE-1]; // add
  reg [PIXEL_BIT_WIDTH+9:0] pipe_2_rb_at_rb_x2        [0:PIXEL_PER_CYCLE-1]; // add
  reg                       pipe_2_tvalid = 'b0;
  wire                      pipe_2_tready;
  reg                       pipe_2_tlast;
  reg [TUSER_WIDTH-1:0]     pipe_2_tuser;

  reg [PIXEL_BIT_WIDTH-1:0] pipe_3_center             [0:PIXEL_PER_CYCLE-1]; // no compute
  reg [PIXEL_BIT_WIDTH-1:0] pipe_3_g_at_rb            [0:PIXEL_PER_CYCLE-1]; // add
  reg [PIXEL_BIT_WIDTH-1:0] pipe_3_rb_at_g1           [0:PIXEL_PER_CYCLE-1]; // add
  reg [PIXEL_BIT_WIDTH-1:0] pipe_3_rb_at_g2           [0:PIXEL_PER_CYCLE-1]; // add
  reg [PIXEL_BIT_WIDTH-1:0] pipe_3_rb_at_rb           [0:PIXEL_PER_CYCLE-1]; // add
  reg                       pipe_3_tvalid = 'b0;
  wire                      pipe_3_tready;
  reg                       pipe_3_tlast;
  reg [TUSER_WIDTH-1:0]     pipe_3_tuser;

  reg [M_AXIS_DATA_WIDTH-1:0] pipe_4_tdata;
  reg [M_AXIS_DATA_WIDTH-1:0] pipe_4_tdata_comb;
  reg                         pipe_4_tvalid = 'b0;
  wire                        pipe_4_tready;
  reg                         pipe_4_tlast;
  reg [TUSER_WIDTH-1:0]       pipe_4_tuser;

  reg new_line = 'b0;

  // rows x cols, shifted every cycle
  wire [PIXEL_BIT_WIDTH-1:0] conv_window [0:NUM_ROWS-1][0:NUM_COLUMNS-1];

  reg  [LINEBUF_DATA_WIDTH-1:0] conv_tdata  [0:PIPE_STAGES-1];
  reg  [PIPE_STAGES-1:0]        conv_valid  = 'b0;
  wire                          conv_tvalid;
  wire                          conv_tready;
  reg                           conv_tlast;
  reg  [TUSER_WIDTH-1:0]        conv_tuser;

  wire [LINEBUF_DATA_WIDTH-1:0] linebuf_tdata;
  wire                          linebuf_tvalid;
  wire                          linebuf_tready;
  wire                          linebuf_tlast;
  wire [TUSER_WIDTH-1:0]        linebuf_tuser;

  // instantiate the line buffer
  linebuffer #(
    .MAX_RESOLUTION       (MAX_RESOLUTION),
    .PIXEL_PER_CYCLE      (PIXEL_PER_CYCLE),
    .PIXEL_BIT_WIDTH      (PIXEL_BIT_WIDTH),
    .CONV_SIZE            (NUM_ROWS)
  ) linebuffer_inst
  (
    .clk            (clk),
    .rstn           (rstn),

    .s_axis_tdata   (s_axis_tdata),
    .s_axis_tvalid  (s_axis_tvalid),
    .s_axis_tready  (s_axis_tready),
    .s_axis_tlast   (s_axis_tlast),
    .s_axis_tuser   (s_axis_tuser),

    .m_axis_tdata   (linebuf_tdata),
    .m_axis_tvalid  (linebuf_tvalid),
    .m_axis_tready  (linebuf_tready),
    .m_axis_tlast   (linebuf_tlast),
    .m_axis_tuser   (linebuf_tuser)
  );

  assign linebuf_tready = pipe_0_tready | ~conv_tvalid;

  assign conv_tvalid = (conv_valid == '1) ? 1'b1 : 1'b0;

  // linebuffer pipeline
  always_ff @ (posedge clk) begin

    if (pipe_0_tready & conv_tvalid) begin
      // Invalidate last stage of pipeline (may be overridden below)
      conv_valid[PIPE_STAGES-1] <= 1'b0;
      // reset SOF bit
      conv_tuser[0] <= 1'b0;
    end

    if (linebuf_tready & linebuf_tvalid) begin
      for (int j = PIPE_STAGES-1; j > 0; j = j-1) begin
        conv_valid[j]    <= conv_valid[j-1];
        conv_tdata[j]    <= conv_tdata[j-1];
      end
    end

    // invalidate pipeline if we encounter EOL in last stage ...
    if (pipe_0_tready & conv_tvalid & conv_tlast) begin
      conv_valid <= '0;
    end

    // ... but make sure we capture new data if valid
    if (linebuf_tready & linebuf_tvalid) begin
      conv_valid[0]    <= 1'b1;
      conv_tdata[0]    <= linebuf_tdata;
      conv_tlast       <= linebuf_tlast;

      // capture SOF; it is reset when a successful transfer happened
      if (linebuf_tuser) begin
        conv_tuser[0]  <= linebuf_tuser;
      end
    end

    if (rstn == 1'b0) begin
      conv_valid <= '0;
    end
  end

  generate

      // Re-map linebuffer output and pipeline stages to easier-to-use 2D array
      //                   |-> 5x5 Context for 1 pixel per cycle
      //                   |   |-> 5x6 Context for 2 pixel per cycle
      // __   _   _   _   _|  _|      _|-> 5x8 Context for 4 pixel per cycle
      // |0   0   0   0   0|  0|  0   0|
      // |0   0   0   0   0|  0|  0   0|
      // |0   0  C0  C1  C2| C3|  0   0|     Center pixel (for output calculation)
      // |0   0   0   0   0|  0|  0   0|
      // |0   0   0   0   0|  0|  0   0|
      //  ^0  ^1  ^2  ^3  ^4              -> Pipeline stages for 1 pixel per cycle; 5 stages to fill context
      //  ^0  ^0  ^1  ^1  ^2  ^2          -> Pipeline stages for 2 pixel per cycle; 3 stages to fill context
      //  ^0  ^0  ^0  ^0  ^1  ^1  ^1  ^1  -> Pipeline stages for 4 pixel per cycle; 2 stages to fill context
      for (genvar row=0; row < NUM_ROWS; row += 1) begin
        for (genvar stage=0; stage < PIPE_STAGES; stage += 1) begin
          for (genvar pixel=0; pixel < PIXEL_PER_CYCLE; pixel += 1) begin
            assign conv_window[row][stage*PIXEL_PER_CYCLE+pixel] = conv_tdata[PIPE_STAGES-1-stage][row*S_AXIS_DATA_WIDTH+pixel*PIXEL_BIT_WIDTH+PIXEL_BIT_WIDTH-1:row*S_AXIS_DATA_WIDTH+pixel*PIXEL_BIT_WIDTH];
          end
        end
      end

  endgenerate

  // pipeline stage 0
  assign pipe_0_tready = pipe_1_tready | ~pipe_0_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_0_tready == 1'b1) begin
      for (int px = 0; px < PIXEL_PER_CYCLE; px += 1) begin
        pipe_0_center[px]           <= {2'b00, conv_window[2][px+2]};
        pipe_0_outer_horizontal[px] <= {1'b0,  conv_window[2][px+0]} + {1'b0, conv_window[2][px+4]};
        pipe_0_outer_vertical[px]   <= {1'b0,  conv_window[0][px+2]} + {1'b0, conv_window[4][px+2]};
        pipe_0_inner_horizontal[px] <= {1'b0,  conv_window[2][px+1]} + {1'b0, conv_window[2][px+3]};
        pipe_0_inner_vertical[px]   <= {1'b0,  conv_window[1][px+2]} + {1'b0, conv_window[3][px+2]};
        pipe_0_inner_top[px]        <= {1'b0,  conv_window[3][px+1]} + {1'b0, conv_window[3][px+3]};
        pipe_0_inner_bottom[px]     <= {1'b0,  conv_window[1][px+1]} + {1'b0, conv_window[1][px+3]};
      end

      pipe_0_tvalid  <= conv_tvalid;
      pipe_0_tlast   <= conv_tlast;
      pipe_0_tuser   <= conv_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_0_tvalid <= '0;
    end
  end

  // pipeline stage 1
  assign pipe_1_tready = pipe_2_tready | ~pipe_1_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_1_tready == 1'b1) begin
      for (int px = 0; px < PIXEL_PER_CYCLE; px += 1) begin
        pipe_1_center[px]               <= { 4'b0000, pipe_0_center[px]};
        pipe_1_center_x5[px]            <= { 4'b0000, pipe_0_center[px]}                 + ({4'b0000, pipe_0_center[px]} << 2);
        pipe_1_center_x6[px]            <= ({4'b0000, pipe_0_center[px]} << 1)           + ({4'b0000, pipe_0_center[px]} << 2);
        pipe_1_outer_horizontal[px]     <= { 4'b0000, pipe_0_outer_horizontal[px]};
        pipe_1_outer_vertical[px]       <= { 4'b0000, pipe_0_outer_vertical[px]};
        pipe_1_outer_cross[px]          <= { 4'b0000, pipe_0_outer_horizontal[px]}       + {4'b0000, pipe_0_outer_vertical[px]};
        pipe_1_inner_h_outer_v_x2[px]   <= ({4'b0000, pipe_0_inner_horizontal[px]} << 3) + {4'b0000, pipe_0_outer_vertical[px]};
        pipe_1_inner_v_outer_h_x2[px]   <= ({4'b0000, pipe_0_inner_vertical[px]} << 3)   + {4'b0000, pipe_0_outer_horizontal[px]};
        pipe_1_inner_corner[px]         <= { 4'b0000, pipe_0_inner_top[px]}              + {4'b0000, pipe_0_inner_bottom[px]};
        pipe_1_inner_cross[px]          <= { 4'b0000, pipe_0_inner_horizontal[px]}       + {4'b0000, pipe_0_inner_vertical[px]};
      end

      pipe_1_tvalid         <= pipe_0_tvalid;
      pipe_1_tlast          <= pipe_0_tlast;
      pipe_1_tuser          <= pipe_0_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_1_tvalid <= '0;
    end
  end

  // pipeline stage 2
  assign pipe_2_tready = pipe_3_tready | ~pipe_2_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_2_tready == 1'b1) begin
      for (int px = 0; px < PIXEL_PER_CYCLE; px += 1) begin
        pipe_2_center[px]               <= {  4'b0000, pipe_1_center[px]};
        pipe_2_center_cross_x2[px]      <= ( {4'b0000, pipe_1_center[px]} << 3)      + ({4'b0000, pipe_1_inner_cross[px]} << 2);
        pipe_2_outer_cross_x2[px]       <= {  4'b0000, pipe_1_outer_cross[px]} << 1;
        pipe_2_outer_cross_x3[px]       <= (({4'b0000, pipe_1_outer_cross[px]} << 1) +  {4'b0000, pipe_1_outer_cross[px]});
        pipe_2_inner_c_outer_h_x2[px]   <= ( {4'b0000, pipe_1_inner_corner[px]}      +  {4'b0000, pipe_1_outer_horizontal[px]}) << 1;
        pipe_2_inner_c_outer_v_x2[px]   <= ( {4'b0000, pipe_1_inner_corner[px]}      +  {4'b0000, pipe_1_outer_vertical[px]}) << 1;
        pipe_2_rb_at_g1_x2[px]          <= ( {4'b0000, pipe_1_center_x5[px]} << 1)   +  {4'b0000, pipe_1_inner_h_outer_v_x2[px]};
        pipe_2_rb_at_g2_x2[px]          <= ( {4'b0000, pipe_1_center_x5[px]} << 1)   +  {4'b0000, pipe_1_inner_v_outer_h_x2[px]};
        pipe_2_rb_at_rb_x2[px]          <= ( {4'b0000, pipe_1_center_x6[px]}         + ({4'b0000, pipe_1_inner_corner[px]} << 1)) << 1;
      end

      pipe_2_tvalid         <= pipe_1_tvalid;
      pipe_2_tlast          <= pipe_1_tlast;
      pipe_2_tuser          <= pipe_1_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_2_tvalid <= '0;
    end
  end

  // pipeline stage 3
  assign pipe_3_tready = pipe_4_tready | ~pipe_3_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_3_tready == 1'b1) begin
      for (int px = 0; px < PIXEL_PER_CYCLE; px += 1) begin
        pipe_3_center[px]       <= pipe_2_center[px][PIXEL_BIT_WIDTH-1:0];
        pipe_3_g_at_rb[px]      <= shift_and_saturate({2'b0, pipe_2_center_cross_x2[px]}  - {2'b0, pipe_2_outer_cross_x2[px]});
        pipe_3_rb_at_g1[px]     <= shift_and_saturate({2'b0, pipe_2_rb_at_g1_x2[px]}      - {2'b0, pipe_2_inner_c_outer_h_x2[px]});
        pipe_3_rb_at_g2[px]     <= shift_and_saturate({2'b0, pipe_2_rb_at_g2_x2[px]}      - {2'b0, pipe_2_inner_c_outer_v_x2[px]});
        pipe_3_rb_at_rb[px]     <= shift_and_saturate({2'b0, pipe_2_rb_at_rb_x2[px]}      - {2'b0, pipe_2_outer_cross_x3[px]});
      end

      if (pipe_2_tvalid == 1'b1) begin
        // pixel logic
        // only increment pixel when
        current_pixel <= current_pixel + PIXEL_PER_CYCLE[0];
        new_line <= 1'b0;
        if (new_line == 1'b1) begin
          // increment line and reset pixel
          current_line <= current_line + 1;
          current_pixel <= PIXEL_INIT;
        end
        if (pipe_2_tlast == 1'b1) begin
          new_line <= 1'b1;
        end
        if (pipe_2_tuser[0] == 1'b1) begin
          // reset line and pixel with start of frame
          current_line <= LINE_INIT;
          current_pixel <= PIXEL_INIT;
        end
      end

      pipe_3_tvalid         <= pipe_2_tvalid;
      pipe_3_tlast          <= pipe_2_tlast;
      pipe_3_tuser          <= pipe_2_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_3_tvalid <= '0;
    end
  end

  // pipeline stage 4
  assign pipe_4_tready = m_axis_tready | ~pipe_4_tvalid;

  generate

    if (PIXEL_PER_CYCLE == 1) begin

      reg [PIXEL_BIT_WIDTH-1:0]  pixel_0_r;
      reg [PIXEL_BIT_WIDTH-1:0]  pixel_0_g;
      reg [PIXEL_BIT_WIDTH-1:0]  pixel_0_b;

      always_comb begin
        case ({current_line, current_pixel})
          2'b00: begin
            // blue pixel
            pixel_0_r = pipe_3_rb_at_rb[0];
            pixel_0_g = pipe_3_g_at_rb[0];
            pixel_0_b = pipe_3_center[0];
          end
          2'b01: begin
            // green pixel in blue row
            pixel_0_r = pipe_3_rb_at_g2[0];
            pixel_0_g = pipe_3_center[0];
            pixel_0_b = pipe_3_rb_at_g1[0];
          end
          2'b10: begin
            // green pixel in red row
            pixel_0_r = pipe_3_rb_at_g1[0];
            pixel_0_g = pipe_3_center[0];
            pixel_0_b = pipe_3_rb_at_g2[0];
          end
          2'b11: begin
            // red pixel
            pixel_0_r = pipe_3_center[0];
            pixel_0_g = pipe_3_g_at_rb[0];
            pixel_0_b = pipe_3_rb_at_rb[0];
          end
        endcase

        pipe_4_tdata_comb[3*PIXEL_PER_CYCLE*PIXEL_BIT_WIDTH-1:0] = {pixel_0_r, pixel_0_b, pixel_0_g};
      end

    end else if (PIXEL_PER_CYCLE == 2) begin

      reg [PIXEL_BIT_WIDTH-1:0]  pixel_0_r;
      reg [PIXEL_BIT_WIDTH-1:0]  pixel_0_g;
      reg [PIXEL_BIT_WIDTH-1:0]  pixel_0_b;

      reg [PIXEL_BIT_WIDTH-1:0]  pixel_1_r;
      reg [PIXEL_BIT_WIDTH-1:0]  pixel_1_g;
      reg [PIXEL_BIT_WIDTH-1:0]  pixel_1_b;

      always_comb begin
        case ({current_line, current_pixel})
          2'b00: begin
            // blue pixel
            pixel_0_r = pipe_3_rb_at_rb[0];
            pixel_0_g = pipe_3_g_at_rb[0];
            pixel_0_b = pipe_3_center[0];

            // green pixel in blue row
            pixel_1_r = pipe_3_rb_at_g2[1];
            pixel_1_g = pipe_3_center[1];
            pixel_1_b = pipe_3_rb_at_g1[1];
          end
          2'b01: begin
            // green pixel in blue row
            pixel_0_r = pipe_3_rb_at_g2[0];
            pixel_0_g = pipe_3_center[0];
            pixel_0_b = pipe_3_rb_at_g1[0];

            // blue pixel
            pixel_1_r = pipe_3_rb_at_rb[1];
            pixel_1_g = pipe_3_g_at_rb[1];
            pixel_1_b = pipe_3_center[1];
          end
          2'b10: begin
            // green pixel in red row
            pixel_0_r = pipe_3_rb_at_g1[0];
            pixel_0_g = pipe_3_center[0];
            pixel_0_b = pipe_3_rb_at_g2[0];

            // red pixel
            pixel_1_r = pipe_3_center[1];
            pixel_1_g = pipe_3_g_at_rb[1];
            pixel_1_b = pipe_3_rb_at_rb[1];
          end
          2'b11: begin
            // red pixel
            pixel_0_r = pipe_3_center[0];
            pixel_0_g = pipe_3_g_at_rb[0];
            pixel_0_b = pipe_3_rb_at_rb[0];

            // green pixel in red row
            pixel_1_r = pipe_3_rb_at_g1[1];
            pixel_1_g = pipe_3_center[1];
            pixel_1_b = pipe_3_rb_at_g2[1];
          end
        endcase

        pipe_4_tdata_comb[3*PIXEL_PER_CYCLE*PIXEL_BIT_WIDTH-1:0] = {pixel_1_r, pixel_1_b, pixel_1_g, pixel_0_r, pixel_0_b, pixel_0_g};
      end

    end else if (PIXEL_PER_CYCLE == 4) begin
      reg [PIXEL_BIT_WIDTH-1:0]  pixel_0_r;
      reg [PIXEL_BIT_WIDTH-1:0]  pixel_0_g;
      reg [PIXEL_BIT_WIDTH-1:0]  pixel_0_b;

      reg [PIXEL_BIT_WIDTH-1:0]  pixel_1_r;
      reg [PIXEL_BIT_WIDTH-1:0]  pixel_1_g;
      reg [PIXEL_BIT_WIDTH-1:0]  pixel_1_b;

      reg [PIXEL_BIT_WIDTH-1:0]  pixel_2_r;
      reg [PIXEL_BIT_WIDTH-1:0]  pixel_2_g;
      reg [PIXEL_BIT_WIDTH-1:0]  pixel_2_b;

      reg [PIXEL_BIT_WIDTH-1:0]  pixel_3_r;
      reg [PIXEL_BIT_WIDTH-1:0]  pixel_3_g;
      reg [PIXEL_BIT_WIDTH-1:0]  pixel_3_b;

      always_comb begin
        case ({current_line, current_pixel})
          2'b00: begin
            // blue pixel
            pixel_0_r = pipe_3_rb_at_rb[0];
            pixel_0_g = pipe_3_g_at_rb[0];
            pixel_0_b = pipe_3_center[0];

            // green pixel in blue row
            pixel_1_r = pipe_3_rb_at_g2[1];
            pixel_1_g = pipe_3_center[1];
            pixel_1_b = pipe_3_rb_at_g1[1];

            // blue pixel
            pixel_2_r = pipe_3_rb_at_rb[2];
            pixel_2_g = pipe_3_g_at_rb[2];
            pixel_2_b = pipe_3_center[2];

            // green pixel in blue row
            pixel_3_r = pipe_3_rb_at_g2[3];
            pixel_3_g = pipe_3_center[3];
            pixel_3_b = pipe_3_rb_at_g1[3];
          end
          2'b01: begin
            // green pixel in blue row
            pixel_0_r = pipe_3_rb_at_g2[0];
            pixel_0_g = pipe_3_center[0];
            pixel_0_b = pipe_3_rb_at_g1[0];

            // blue pixel
            pixel_1_r = pipe_3_rb_at_rb[1];
            pixel_1_g = pipe_3_g_at_rb[1];
            pixel_1_b = pipe_3_center[1];

            // green pixel in blue row
            pixel_2_r = pipe_3_rb_at_g2[2];
            pixel_2_g = pipe_3_center[2];
            pixel_2_b = pipe_3_rb_at_g1[2];

            // blue pixel
            pixel_3_r = pipe_3_rb_at_rb[3];
            pixel_3_g = pipe_3_g_at_rb[3];
            pixel_3_b = pipe_3_center[3];
          end
          2'b10: begin
            // green pixel in red row
            pixel_0_r = pipe_3_rb_at_g1[0];
            pixel_0_g = pipe_3_center[0];
            pixel_0_b = pipe_3_rb_at_g2[0];

            // red pixel
            pixel_1_r = pipe_3_center[1];
            pixel_1_g = pipe_3_g_at_rb[1];
            pixel_1_b = pipe_3_rb_at_rb[1];

            // green pixel in red row
            pixel_2_r = pipe_3_rb_at_g1[2];
            pixel_2_g = pipe_3_center[2];
            pixel_2_b = pipe_3_rb_at_g2[2];

            // red pixel
            pixel_3_r = pipe_3_center[3];
            pixel_3_g = pipe_3_g_at_rb[3];
            pixel_3_b = pipe_3_rb_at_rb[3];
          end
          2'b11: begin
            // red pixel
            pixel_0_r = pipe_3_center[0];
            pixel_0_g = pipe_3_g_at_rb[0];
            pixel_0_b = pipe_3_rb_at_rb[0];

            // green pixel in red row
            pixel_1_r = pipe_3_rb_at_g1[1];
            pixel_1_g = pipe_3_center[1];
            pixel_1_b = pipe_3_rb_at_g2[1];

            // red pixel
            pixel_2_r = pipe_3_center[2];
            pixel_2_g = pipe_3_g_at_rb[2];
            pixel_2_b = pipe_3_rb_at_rb[2];

            // green pixel in red row
            pixel_3_r = pipe_3_rb_at_g1[3];
            pixel_3_g = pipe_3_center[3];
            pixel_3_b = pipe_3_rb_at_g2[3];
          end
        endcase

        pipe_4_tdata_comb[3*PIXEL_PER_CYCLE*PIXEL_BIT_WIDTH-1:0] = {pixel_3_r, pixel_3_b, pixel_3_g, pixel_2_r, pixel_2_b, pixel_2_g, pixel_1_r, pixel_1_b, pixel_1_g, pixel_0_r, pixel_0_b, pixel_0_g};
      end
    end

  endgenerate

  always_ff @ (posedge clk) begin
    if (pipe_4_tready == 1'b1) begin
      pipe_4_tdata          <= pipe_4_tdata_comb;
      pipe_4_tvalid         <= pipe_3_tvalid;
      pipe_4_tlast          <= pipe_3_tlast;
      pipe_4_tuser          <= pipe_3_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_4_tvalid <= '0;
    end
  end

  // assign outputs
  assign m_axis_tdata   = pipe_4_tdata;
  assign m_axis_tvalid  = pipe_4_tvalid;
  assign m_axis_tlast   = pipe_4_tlast;
  assign m_axis_tuser   = pipe_4_tuser;

endmodule
