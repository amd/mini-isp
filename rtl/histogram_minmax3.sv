// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module histogram_minmax3
  #(
    // Pixel per cycle. 1, 2 or 4
    parameter PIXEL_PER_CYCLE                     = 4,
    // Pixel bit width. 10, 12, 14, 16, 18, 20, 22, 24
    parameter INPUT_BIT_WIDTH                     = 24,
    parameter DOWNSAMPLE_STAGES                   = 4,
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

  localparam int RAM_ADDR_WIDTH     = 12;
  localparam int RAM_DATA_WIDTH     = 9;

  wire [INPUT_BIT_WIDTH-1:0]        pipe_0_r_wire[PIXEL_PER_CYCLE-1:0];
  wire [INPUT_BIT_WIDTH-1:0]        pipe_0_g_wire[PIXEL_PER_CYCLE-1:0];
  wire [INPUT_BIT_WIDTH-1:0]        pipe_0_b_wire[PIXEL_PER_CYCLE-1:0];
  wire [INPUT_BIT_WIDTH+1:0]        pipe_0_gray_wire[PIXEL_PER_CYCLE-1:0];
  wire [INPUT_BIT_WIDTH-1:0]        pipe_0_gray_shift[PIXEL_PER_CYCLE-1:0];
  reg [INPUT_BIT_WIDTH-1:0]         pipe_0_gray;
  reg                               pipe_0_tvalid = 'b0;
  reg                               pipe_0_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_0_tuser;
  reg                               pipe_0_readout_done;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_0_total_counter;
  reg                               pipe_0_ram_select = 1'b0;
  reg [RAM_ADDR_WIDTH-1:0]          pipe_0_readout_counter;
  reg                               pipe_0_readout_direction;
  reg                               pipe_0_readout_active;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_0_target_count;

  reg [INPUT_BIT_WIDTH-1:0]         pipe_1_gray;
  reg                               pipe_1_tvalid = 'b0;
  reg                               pipe_1_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_1_tuser;
  reg                               pipe_1_readout_done;
  reg                               pipe_1_ram_select = 1'b0;
  reg [RAM_ADDR_WIDTH-1:0]          pipe_1_readout_counter;
  reg                               pipe_1_readout_direction;
  reg                               pipe_1_readout_active;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_1_target_count;

  reg [INPUT_BIT_WIDTH-1:0]         pipe_2_gray;
  reg                               pipe_2_tvalid = 'b0;
  reg                               pipe_2_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_2_tuser;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_2_max_acc;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_2_min_acc;
  reg                               pipe_2_readout_done;
  reg [RAM_ADDR_WIDTH-1:0]          pipe_2_readout_counter;
  reg                               pipe_2_readout_active;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_2_target_count;

  reg [INPUT_BIT_WIDTH-1:0]         pipe_out_tmin;
  reg [INPUT_BIT_WIDTH-1:0]         pipe_out_tmax;
  reg                               pipe_out_tvalid = 'b0;

  reg                               ram0_wen;
  reg [RAM_ADDR_WIDTH-1:0]          ram0_waddr;
  reg [RAM_DATA_WIDTH-1:0]          ram0_wdata;
  reg                               ram0_ren;
  reg [RAM_ADDR_WIDTH-1:0]          ram0_raddr;
  reg [RAM_DATA_WIDTH-1:0]          ram0_rdata;

  reg                               ram1_wen;
  reg [RAM_ADDR_WIDTH-1:0]          ram1_waddr;
  reg [RAM_DATA_WIDTH-1:0]          ram1_wdata;
  reg                               ram1_ren;
  reg [RAM_ADDR_WIDTH-1:0]          ram1_raddr;
  reg [RAM_DATA_WIDTH-1:0]          ram1_rdata;

  // convert to simple gray scale
  generate

    for (genvar px = 0; px < PIXEL_PER_CYCLE; px = px + 1) begin
      localparam OFFSET = px * 3 * INPUT_BIT_WIDTH;

      assign pipe_0_g_wire[px] = s_axis_tdata[OFFSET + 1*INPUT_BIT_WIDTH-1: OFFSET + 0*INPUT_BIT_WIDTH];
      assign pipe_0_r_wire[px] = s_axis_tdata[OFFSET + 2*INPUT_BIT_WIDTH-1: OFFSET + 1*INPUT_BIT_WIDTH];
      assign pipe_0_b_wire[px] = s_axis_tdata[OFFSET + 3*INPUT_BIT_WIDTH-1: OFFSET + 2*INPUT_BIT_WIDTH];

      // convert to gray
      assign pipe_0_gray_wire[px] = {1'b0, pipe_0_r_wire[px], 1'b0} + {2'b0, pipe_0_g_wire[px]} + {2'b0, pipe_0_b_wire[px]} >> 2;
      assign pipe_0_gray_shift[px] = (pipe_0_gray_wire[px][INPUT_BIT_WIDTH-1:RAM_ADDR_WIDTH] == '0) ? pipe_0_gray_wire[px][INPUT_BIT_WIDTH-1:0] : '1;
    end

  endgenerate

  // pipeline stage 0
  always_ff @ (posedge clk) begin
    // register everything else
    pipe_0_gray         <= pipe_0_gray_shift[0];
    pipe_0_tvalid       <= s_axis_tvalid;
    pipe_0_tlast        <= s_axis_tlast;
    pipe_0_tuser        <= s_axis_tuser;
    pipe_0_readout_done <= 1'b0;

    // states:
    // 1. read out / clear state -> triggered by start of frame
    // 2. wait for next line --> triggered by end of address counter
    // 3. normal histogram operation
    if (s_axis_tvalid == 1'b1) begin
      pipe_0_total_counter    <= pipe_0_total_counter + 1'b1;
    end

    // read out counter logic. need to count down from top and then up from bottom
    // only in the bottom to top phase, the RAM is deleted.
    if (pipe_0_readout_active == 1'b1) begin
      if (pipe_0_readout_direction == 1'b0) begin
        pipe_0_readout_counter <= pipe_0_readout_counter - 1'b1;
        if (pipe_0_readout_counter == 1) begin
          pipe_0_readout_direction  <= 1'b1;
        end
      end else begin
        pipe_0_readout_counter <= pipe_0_readout_counter + 1'b1;
        if (pipe_0_readout_counter == '1) begin
          pipe_0_readout_direction  <= 1'b0;
          pipe_0_readout_active     <= 1'b0;
          pipe_0_readout_done       <= 1'b1;
        end
      end
    end

    // on start of frame, switch active RAM and start readout process
    if (s_axis_tvalid == 1'b1 && s_axis_tuser[0] == 1'b1) begin
      pipe_0_ram_select         <= ~pipe_0_ram_select;
      pipe_0_readout_counter    <= '1;
      pipe_0_readout_direction  <= 1'b0;
      pipe_0_readout_active     <= 1'b1;
      pipe_0_total_counter      <= 1'b1;
      pipe_0_target_count       <= pipe_0_total_counter >> 7;
    end

    if (rstn == 1'b0) begin
      pipe_0_tvalid <= '0;
    end
  end

  // pipeline stage 0
  always_ff @ (posedge clk) begin
    // register everything else
    pipe_1_gray       <= pipe_0_gray;
    pipe_1_tvalid     <= pipe_0_tvalid;
    pipe_1_tlast      <= pipe_0_tlast;
    pipe_1_tuser      <= pipe_0_tuser;
    pipe_1_ram_select <= pipe_0_ram_select;

    pipe_1_readout_active <= pipe_0_readout_active;
    pipe_1_readout_done       <= pipe_0_readout_done;
    pipe_1_readout_direction <= pipe_0_readout_direction;
    pipe_1_readout_counter <= pipe_0_readout_counter;
    pipe_1_target_count <= pipe_0_target_count;

    // states:
    // 1. read out / clear state -> triggered by start of frame
    // 2. wait for next line --> triggered by end of address counter
    // 3. normal histogram operation

    if (pipe_0_ram_select == 1'b0) begin
      ram0_ren    <= pipe_0_tvalid;
      ram0_raddr  <= pipe_0_gray[RAM_ADDR_WIDTH-1:0];

      ram1_ren    <= pipe_0_readout_active;
      ram1_raddr  <= pipe_0_readout_counter;
    end else begin
      ram0_ren    <= pipe_0_readout_active;
      ram0_raddr  <= pipe_0_readout_counter;

      ram1_ren    <= pipe_0_tvalid;
      ram1_raddr  <= pipe_0_gray[RAM_ADDR_WIDTH-1:0];
    end

    if (rstn == 1'b0) begin
      pipe_1_tvalid <= '0;
    end
  end

  // pipeline stage 0
  always_ff @ (posedge clk) begin
    // register everything else
    pipe_2_gray       <= pipe_1_gray;
    pipe_2_tvalid     <= pipe_1_tvalid;
    pipe_2_tlast      <= pipe_1_tlast;
    pipe_2_tuser      <= pipe_1_tuser;
    pipe_2_readout_counter <= pipe_1_readout_counter;
    pipe_2_target_count <= pipe_1_target_count;
    pipe_2_readout_active <= pipe_1_readout_active;
    pipe_2_readout_done       <= pipe_1_readout_done;

    // accumulator logic
    if (pipe_1_readout_active == 1'b1) begin
      if (pipe_1_readout_direction == 1'b0) begin
        if (pipe_1_ram_select == 1'b0) begin
          pipe_2_max_acc <= pipe_2_max_acc + ram1_rdata;
        end else begin
          pipe_2_max_acc <= pipe_2_max_acc + ram0_rdata;
        end
      end else begin
        if (pipe_1_ram_select == 1'b0) begin
          pipe_2_min_acc <= pipe_2_min_acc + ram1_rdata;
        end else begin
          pipe_2_min_acc <= pipe_2_min_acc + ram0_rdata;
        end
      end
    end

    if (pipe_1_readout_done == 1'b1) begin
      pipe_2_min_acc <= '0;
      pipe_2_max_acc <= '0;
    end

    // states:
    // 1. read out / clear state -> triggered by start of frame
    // 2. wait for next line --> triggered by end of address counter
    // 3. normal histogram operation

    if (pipe_1_ram_select == 1'b0) begin
      ram0_wen      <= pipe_1_tvalid;
      ram0_waddr    <= pipe_1_gray[RAM_ADDR_WIDTH-1:0];
      ram0_wdata    <= ram0_rdata + 1'b1;

      ram1_wen      <= pipe_1_readout_direction & pipe_1_readout_active;
      ram1_waddr    <= pipe_1_readout_counter;
      ram1_wdata    <= '0;
    end else begin
      ram0_wen      <= pipe_1_readout_direction & pipe_1_readout_active;
      ram0_waddr    <= pipe_1_readout_counter;
      ram0_wdata    <= '0;

      ram1_wen      <= pipe_1_tvalid;
      ram1_waddr    <= pipe_1_gray[RAM_ADDR_WIDTH-1:0];
      ram1_wdata    <= ram1_rdata + 1'b1;
    end

    if (rstn == 1'b0) begin
      pipe_2_tvalid <= '0;
    end
  end

  simple_dual_ported_ram #(
    .DATA_WIDTH               (RAM_DATA_WIDTH),
    .ADDR_WIDTH               (RAM_ADDR_WIDTH)
  ) ram0_inst (
    .clk                      (clk),
    .w_en                     (ram0_wen),
    .w_addr                   (ram0_waddr),
    .w_data                   (ram0_wdata),
    .r_en                     (ram0_ren),
    .r_addr                   (ram0_raddr),
    .r_data                   (ram0_rdata)
  );

  simple_dual_ported_ram #(
    .DATA_WIDTH               (RAM_DATA_WIDTH),
    .ADDR_WIDTH               (RAM_ADDR_WIDTH)
  ) ram1_inst (
    .clk                      (clk),
    .w_en                     (ram1_wen),
    .w_addr                   (ram1_waddr),
    .w_data                   (ram1_wdata),
    .r_en                     (ram1_ren),
    .r_addr                   (ram1_raddr),
    .r_data                   (ram1_rdata)
  );

  // output process
  always_ff @ (posedge clk) begin
    if (pipe_2_readout_active == 1'b1) begin
      if (pipe_2_max_acc < pipe_2_target_count) begin
        pipe_out_tmax[RAM_ADDR_WIDTH-1:0] <= pipe_2_readout_counter;
      end

      if (pipe_2_min_acc < pipe_2_target_count) begin
        pipe_out_tmin[RAM_ADDR_WIDTH-1:0] <= pipe_2_readout_counter;
      end
    end

    pipe_out_tvalid   <= pipe_2_readout_done;

    if (rstn == 1'b0) begin
      pipe_out_tvalid <= '0;
    end
  end

  // assign outputs
  assign m_axis_tmin    = pipe_out_tmin;
  assign m_axis_tmax    = pipe_out_tmax;
  assign m_axis_tvalid  = pipe_out_tvalid;

endmodule
