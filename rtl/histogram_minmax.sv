// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module histogram_minmax
  #(
    // Pixel per cycle. 1, 2 or 4
    parameter PIXEL_PER_CYCLE                     = 4,
    // Pixel bit width. 10, 12, 14, 16, 18, 20, 22, 24
    parameter INPUT_BIT_WIDTH                     = 24,
    parameter MAX_ROWS                            = 4096,
    parameter MAX_COLS                            = 4096,
    parameter DATA_WIDTH                          = 8*$rtoi($floor((PIXEL_PER_CYCLE * 3 * INPUT_BIT_WIDTH + 7)/8)),
    parameter TUSER_WIDTH                         = 1
  )
  (
    input  wire                         clk,
    input  wire                         rstn,

    input  wire  [DATA_WIDTH-1:0]       s_axis_tdata,
    input  wire                         s_axis_tvalid,
    input  wire                         s_axis_tlast,
    input  wire  [TUSER_WIDTH-1:0]      s_axis_tuser,

    output wire  [INPUT_BIT_WIDTH-1:0]  m_axis_tmin,
    output wire  [INPUT_BIT_WIDTH-1:0]  m_axis_tmax,
    output wire                         m_axis_tvalid
  );

  localparam int COUNTER_WIDTH      = $rtoi($clog2(MAX_ROWS*MAX_COLS));

  wire [INPUT_BIT_WIDTH-1:0]        pipe_0_r_wire[PIXEL_PER_CYCLE-1:0];
  wire [INPUT_BIT_WIDTH-1:0]        pipe_0_g_wire[PIXEL_PER_CYCLE-1:0];
  wire [INPUT_BIT_WIDTH-1:0]        pipe_0_b_wire[PIXEL_PER_CYCLE-1:0];
  wire [INPUT_BIT_WIDTH+1:0]        pipe_0_gray_wire[PIXEL_PER_CYCLE-1:0];
  wire [INPUT_BIT_WIDTH-1:0]        pipe_0_gray_shift[PIXEL_PER_CYCLE-1:0];
  reg [INPUT_BIT_WIDTH-1:0]         pipe_0_gray[PIXEL_PER_CYCLE-1:0];
  reg                               pipe_0_tvalid = 'b0;
  reg                               pipe_0_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_0_tuser;

  reg [INPUT_BIT_WIDTH-1:0]         pipe_1_gray[PIXEL_PER_CYCLE-1:0];
  reg                               pipe_1_tvalid = 'b0;
  reg                               pipe_1_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_1_tuser;

  reg [INPUT_BIT_WIDTH-1:0]         pipe_2_gray[PIXEL_PER_CYCLE-1:0];
  reg                               pipe_2_tvalid = 'b0;
  reg                               pipe_2_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_2_tuser;

  reg [INPUT_BIT_WIDTH-1:0]         pipe_3_gray[PIXEL_PER_CYCLE-1:0];
  reg                               pipe_3_tvalid = 'b0;
  reg                               pipe_3_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_3_tuser;

  reg [2:0]                         pipe_update_min_count_incr;
  reg [2:0]                         pipe_update_max_count_incr;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_update_min_per_cycle;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_update_max_per_cycle;
  reg                               pipe_update_tvalid = 'b0;
  reg                               pipe_update_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_update_tuser;

  reg [INPUT_BIT_WIDTH-1:0]         pipe_out_tmin;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_out_tmax;
  reg                               pipe_out_tvalid = 'b0;

  reg [COUNTER_WIDTH-1:0]           total_pixel_count;
  reg [COUNTER_WIDTH-1:0]           target_min_count;
  reg [COUNTER_WIDTH-1:0]           target_max_count;
  wire signed [COUNTER_WIDTH:0]     target_min_count_wire;
  wire signed [COUNTER_WIDTH:0]   target_max_count_wire;
  reg [COUNTER_WIDTH-1:0]           actual_min_count;
  reg [COUNTER_WIDTH-1:0]           actual_max_count;
  wire signed [COUNTER_WIDTH:0]     actual_min_count_wire;
  wire signed [COUNTER_WIDTH:0]     actual_max_count_wire;

  reg signed [COUNTER_WIDTH:0]      error_min_count;
  reg signed [COUNTER_WIDTH:0]      error_max_count;

  reg [INPUT_BIT_WIDTH-1:0]         last_min_value = '0;
  reg [INPUT_BIT_WIDTH-1:0]         last_max_value = '1;
  reg [INPUT_BIT_WIDTH-1:0]         current_min_value;
  reg [INPUT_BIT_WIDTH-1:0]         current_max_value;

  reg signed [INPUT_BIT_WIDTH-1:0]  tmp_value_min;
  reg signed [INPUT_BIT_WIDTH-1:0]  tmp_value_max;
  reg [INPUT_BIT_WIDTH-1:0]         set_value_min;
  reg [INPUT_BIT_WIDTH-1:0]         set_value_max;

  reg signed [INPUT_BIT_WIDTH-1:0]  integral_min;
  reg signed [INPUT_BIT_WIDTH-1:0]  integral_max;

  reg signed [INPUT_BIT_WIDTH-1:0]  proportional_min;
  reg signed [INPUT_BIT_WIDTH-1:0]  proportional_max;

  // 1. convert to simple gray scale

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

  assign target_min_count_wire = {1'b0, target_min_count};
  assign target_max_count_wire = {1'b0, target_max_count};

  assign actual_min_count_wire = {1'b0, actual_min_count};
  assign actual_max_count_wire = {1'b0, actual_max_count};

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

    if (s_axis_tvalid == 1'b1) begin
      // count total pixel
      total_pixel_count <= total_pixel_count + PIXEL_PER_CYCLE;

    end

    // update control variables in case it is start of frame!
    if (s_axis_tvalid == 1'b1 && s_axis_tuser[0] == 1'b1) begin
      // reset total_pixel_count
      total_pixel_count <= PIXEL_PER_CYCLE;

      // set target min and max values to (roughly) 1% if the last total pixel count
      target_min_count <= total_pixel_count >> 7;
      target_max_count <= total_pixel_count >> 7;

      // update error
      error_min_count <= target_min_count_wire - actual_min_count_wire;
      error_max_count <= target_max_count_wire - actual_max_count_wire;
    end

    if (rstn == 1'b0) begin
      pipe_0_tvalid <= '0;
    end
  end

  // pipeline stage 1
  always_ff @ (posedge clk) begin
    // register everything else
    for (integer px = 0; px < PIXEL_PER_CYCLE; px = px + 1) begin
      pipe_1_gray[px]    <= pipe_0_gray[px];
    end
    pipe_1_tvalid  <= pipe_0_tvalid;
    pipe_1_tlast   <= pipe_0_tlast;
    pipe_1_tuser   <= pipe_0_tuser;

    // update control variables in case it is start of frame!
    if (pipe_0_tvalid == 1'b1 && pipe_0_tuser[0] == 1'b1) begin

      // update proportional part of PID
      proportional_min <= error_min_count[INPUT_BIT_WIDTH-1:0];
      proportional_max <= error_max_count[INPUT_BIT_WIDTH-1:0];

      // update integral part of PID
      /* verilator lint_off WIDTHTRUNC */
      integral_min <= integral_min + (error_min_count >>> 5);
      integral_max <= integral_max + (error_max_count >>> 5);
      /* verilator lint_on WIDTHTRUNC */

    end

    if (rstn == 1'b0) begin
      pipe_1_tvalid <= '0;
    end
  end

  // pipeline stage 2
  always_ff @ (posedge clk) begin
    // register everything else
    for (integer px = 0; px < PIXEL_PER_CYCLE; px = px + 1) begin
      pipe_2_gray[px]    <= pipe_1_gray[px];
    end
    pipe_2_tvalid  <= pipe_1_tvalid;
    pipe_2_tlast   <= pipe_1_tlast;
    pipe_2_tuser   <= pipe_1_tuser;

    // update control variables in case it is start of frame!
    if (pipe_1_tvalid == 1'b1 && pipe_1_tuser[0] == 1'b1) begin

      // update set value
      // K_p = 128
      // K_i = 16
      // K_d = 0
      tmp_value_min <= set_value_min + (proportional_min << 0) + (integral_min << 0);
      tmp_value_max <= set_value_max + (proportional_max << 0) + (integral_max << 0);

    end

    if (rstn == 1'b0) begin
      pipe_2_tvalid <= '0;
    end
  end

  // pipeline stage 3
  always_ff @ (posedge clk) begin
    // register everything else
    for (integer px = 0; px < PIXEL_PER_CYCLE; px = px + 1) begin
      pipe_3_gray[px]    <= pipe_2_gray[px];
    end
    pipe_3_tvalid  <= pipe_2_tvalid;
    pipe_3_tlast   <= pipe_2_tlast;
    pipe_3_tuser   <= pipe_2_tuser;

    // update control variables in case it is start of frame!
    if (pipe_2_tvalid == 1'b1 && pipe_2_tuser[0] == 1'b1) begin

      // update set value
      if (tmp_value_min > last_max_value || tmp_value_min < last_min_value) begin
        set_value_min <= last_min_value;
      end else begin
        set_value_min <= tmp_value_min;
      end

      if (tmp_value_max > last_max_value || tmp_value_max < last_min_value) begin
        set_value_max <= last_max_value;
      end else begin
        set_value_max <= tmp_value_max;
      end

    end

    if (rstn == 1'b0) begin
      pipe_3_tvalid <= '0;
    end
  end

  // 2. initialize min and max to theoretical min and max values
  // 3. at start of frame, compute new current_percentile_max/current_percentile_min values
  // 4. a) find absolute min and max (tree structure for multiple pixel)
  // 4. b) count number of values below/above current_percentile_max/current_percentile_min

  // find maximum per clock cycle
  generate
    if (PIXEL_PER_CYCLE == 1) begin

      always_ff @ (posedge clk) begin
        pipe_update_min_per_cycle <= pipe_3_gray[0];
        pipe_update_max_per_cycle <= pipe_3_gray[0];

        pipe_update_min_count_incr <= 2'b00;
        pipe_update_max_count_incr <= 2'b00;

        if (pipe_3_gray[0] < set_value_min) begin
          pipe_update_min_count_incr <= 2'b01;
        end

        if (pipe_3_gray[0] > set_value_max) begin
          pipe_update_max_count_incr <= 2'b01;
        end

        pipe_update_tvalid <= pipe_3_tvalid;
        pipe_update_tuser  <= pipe_3_tuser;

        if (rstn == 1'b0) begin
          pipe_update_tvalid <= '0;
        end
      end

    end

    if (PIXEL_PER_CYCLE == 2) begin

      wire pixel_0_greater = pipe_3_gray[0] > set_value_max ? 1'b1 : 1'b0;
      wire pixel_1_greater = pipe_3_gray[1] > set_value_max ? 1'b1 : 1'b0;
      wire pixel_0_smaller = pipe_3_gray[0] < set_value_min ? 1'b1 : 1'b0;
      wire pixel_1_smaller = pipe_3_gray[1] < set_value_min ? 1'b1 : 1'b0;

      wire [1:0] pixel_greater = {pixel_1_greater, pixel_0_greater};
      wire [1:0] pixel_smaller = {pixel_1_smaller, pixel_0_smaller};

      always_ff @ (posedge clk) begin
        if (pipe_3_gray[0] > pipe_3_gray[1]) begin
          pipe_update_min_per_cycle <= pipe_3_gray[1];
          pipe_update_max_per_cycle <= pipe_3_gray[0];
        end else begin
          pipe_update_min_per_cycle <= pipe_3_gray[0];
          pipe_update_max_per_cycle <= pipe_3_gray[1];
        end

        pipe_update_min_count_incr <= 3'b000;
        pipe_update_max_count_incr <= 3'b000;

        case (pixel_smaller)
          2'b00: pipe_update_min_count_incr <= 3'b000;
          2'b01: pipe_update_min_count_incr <= 3'b001;
          2'b10: pipe_update_min_count_incr <= 3'b001;
          2'b11: pipe_update_min_count_incr <= 3'b010;
        endcase

        case (pixel_greater)
          2'b00: pipe_update_max_count_incr <= 3'b000;
          2'b01: pipe_update_max_count_incr <= 3'b001;
          2'b10: pipe_update_max_count_incr <= 3'b001;
          2'b11: pipe_update_max_count_incr <= 3'b010;
        endcase

        pipe_update_tvalid <= pipe_3_tvalid;
        pipe_update_tuser  <= pipe_3_tuser;

        if (rstn == 1'b0) begin
          pipe_update_tvalid <= '0;
        end
      end

    end

    if (PIXEL_PER_CYCLE == 4) begin

      wire pixel_0_greater = pipe_3_gray[0] > set_value_max ? 1'b1 : 1'b0;
      wire pixel_1_greater = pipe_3_gray[1] > set_value_max ? 1'b1 : 1'b0;
      wire pixel_2_greater = pipe_3_gray[2] > set_value_max ? 1'b1 : 1'b0;
      wire pixel_3_greater = pipe_3_gray[3] > set_value_max ? 1'b1 : 1'b0;
      wire pixel_0_smaller = pipe_3_gray[0] < set_value_min ? 1'b1 : 1'b0;
      wire pixel_1_smaller = pipe_3_gray[1] < set_value_min ? 1'b1 : 1'b0;
      wire pixel_2_smaller = pipe_3_gray[2] < set_value_min ? 1'b1 : 1'b0;
      wire pixel_3_smaller = pipe_3_gray[3] < set_value_min ? 1'b1 : 1'b0;

      wire [3:0] pixel_greater = {pixel_3_greater, pixel_2_greater, pixel_1_greater, pixel_0_greater};
      wire [3:0] pixel_smaller = {pixel_3_smaller, pixel_2_smaller, pixel_1_smaller, pixel_0_smaller};

      always_ff @ (posedge clk) begin
        // TODO: ignore other pixels for min/max calculation for now!!!
        if (pipe_3_gray[0] > pipe_3_gray[1]) begin
          pipe_update_min_per_cycle <= pipe_3_gray[1];
          pipe_update_max_per_cycle <= pipe_3_gray[0];
        end else begin
          pipe_update_min_per_cycle <= pipe_3_gray[0];
          pipe_update_max_per_cycle <= pipe_3_gray[1];
        end

        pipe_update_min_count_incr <= 3'b000;
        pipe_update_max_count_incr <= 3'b000;

        case (pixel_smaller)
          4'b0000: pipe_update_min_count_incr <= 3'b000;
          4'b0001: pipe_update_min_count_incr <= 3'b001;
          4'b0010: pipe_update_min_count_incr <= 3'b001;
          4'b0011: pipe_update_min_count_incr <= 3'b010;
          4'b0100: pipe_update_min_count_incr <= 3'b001;
          4'b0101: pipe_update_min_count_incr <= 3'b010;
          4'b0110: pipe_update_min_count_incr <= 3'b010;
          4'b0111: pipe_update_min_count_incr <= 3'b011;
          4'b1000: pipe_update_min_count_incr <= 3'b001;
          4'b1001: pipe_update_min_count_incr <= 3'b010;
          4'b1010: pipe_update_min_count_incr <= 3'b010;
          4'b1011: pipe_update_min_count_incr <= 3'b011;
          4'b1100: pipe_update_min_count_incr <= 3'b010;
          4'b1101: pipe_update_min_count_incr <= 3'b011;
          4'b1110: pipe_update_min_count_incr <= 3'b011;
          4'b1111: pipe_update_min_count_incr <= 3'b100;
        endcase

        case (pixel_greater)
          4'b0000: pipe_update_max_count_incr <= 3'b000;
          4'b0001: pipe_update_max_count_incr <= 3'b001;
          4'b0010: pipe_update_max_count_incr <= 3'b001;
          4'b0011: pipe_update_max_count_incr <= 3'b010;
          4'b0100: pipe_update_max_count_incr <= 3'b001;
          4'b0101: pipe_update_max_count_incr <= 3'b010;
          4'b0110: pipe_update_max_count_incr <= 3'b010;
          4'b0111: pipe_update_max_count_incr <= 3'b011;
          4'b1000: pipe_update_max_count_incr <= 3'b001;
          4'b1001: pipe_update_max_count_incr <= 3'b010;
          4'b1010: pipe_update_max_count_incr <= 3'b010;
          4'b1011: pipe_update_max_count_incr <= 3'b011;
          4'b1100: pipe_update_max_count_incr <= 3'b010;
          4'b1101: pipe_update_max_count_incr <= 3'b011;
          4'b1110: pipe_update_max_count_incr <= 3'b011;
          4'b1111: pipe_update_max_count_incr <= 3'b100;
        endcase

        pipe_update_tvalid <= pipe_3_tvalid;
        pipe_update_tuser  <= pipe_3_tuser;

        if (rstn == 1'b0) begin
          pipe_update_tvalid <= '0;
        end
      end
    end
  endgenerate

  always_ff @ (posedge clk) begin
    if (pipe_update_tvalid == 1'b1) begin
      if (pipe_update_max_per_cycle > current_max_value) begin
        current_max_value <= pipe_update_max_per_cycle;
      end

      if (pipe_update_min_per_cycle < current_min_value) begin
        current_min_value <= pipe_update_min_per_cycle;
      end

      /* verilator lint_off WIDTHEXPAND */
      actual_min_count <= actual_min_count + pipe_update_min_count_incr;
      actual_max_count <= actual_max_count + pipe_update_max_count_incr;
      /* verilator lint_on WIDTHEXPAND */
    end

    if (pipe_update_tvalid == 1'b1 && pipe_update_tuser[0] == 1'b1) begin
      current_max_value <= pipe_update_max_per_cycle;
      current_min_value <= pipe_update_min_per_cycle;

      last_max_value <= current_max_value;
      last_min_value <= current_min_value;

      actual_min_count  <= '0;
      actual_max_count  <= '0;
    end
  end

  // output process
  always_ff @ (posedge clk) begin
    pipe_out_tmax     <= set_value_max;
    pipe_out_tmin     <= set_value_min;
    pipe_out_tvalid   <= pipe_3_tvalid & pipe_3_tlast;

    if (rstn == 1'b0) begin
      pipe_out_tvalid <= '0;
    end
  end

  // assign outputs
  assign m_axis_tmin    = pipe_out_tmin;
  assign m_axis_tmax    = pipe_out_tmax;
  assign m_axis_tvalid  = pipe_out_tvalid;

endmodule
