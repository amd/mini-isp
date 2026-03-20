// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module linebuffer
  #(
    // Resolution. RES_2K=2048, RES_4K=4096, RES_8K=8192
    parameter MAX_RESOLUTION                      = 4096,
    // Pixel per cycle. 1, 2 or 4
    parameter PIXEL_PER_CYCLE                     = 4,
    // Pixel bit width. 8, 10, 12, 14, 16, 18
    parameter PIXEL_BIT_WIDTH                     = 14,
    // Convolution size. 3X3=3, 5X5=5, 7X7=7, 9X9=9, 11X11=11
    parameter CONV_SIZE                           = 5,
    parameter S_AXIS_DATA_WIDTH                   = 8*$rtoi($floor((PIXEL_PER_CYCLE * PIXEL_BIT_WIDTH + 7)/8)),
    parameter M_AXIS_DATA_WIDTH                   = CONV_SIZE * S_AXIS_DATA_WIDTH,
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

  localparam MEM_WIDTH  = PIXEL_PER_CYCLE * PIXEL_BIT_WIDTH;
  localparam MEM_DEPTH  = $clog2(MAX_RESOLUTION >> $clog2(PIXEL_PER_CYCLE));

  reg [$clog2(CONV_SIZE)-1:0]   ignore_lines;
  reg                           output_enable = '0;
  reg                           output_enable_d = '0;

  reg [S_AXIS_DATA_WIDTH-1:0]   pipe_0_tdata;
  reg                           pipe_0_tvalid = 'b0;
  wire                          pipe_0_tready;
  reg                           pipe_0_tlast;
  reg [TUSER_WIDTH-1:0]         pipe_0_tuser;

  reg [M_AXIS_DATA_WIDTH-1:0]   pipe_1_tdata;
  reg                           pipe_1_tvalid = 'b0;
  wire                          pipe_1_tready;
  reg                           pipe_1_tlast;
  reg [TUSER_WIDTH-1:0]         pipe_1_tuser;

  reg [MEM_WIDTH-1:0]           line_data [CONV_SIZE-1:0];

  wire [M_AXIS_DATA_WIDTH-1:0]  line_data_out;

  reg [MEM_DEPTH-1:0]           read_counter = '0;
  wire                          read_en;
  reg [MEM_DEPTH-1:0]           write_counter = '0;
  reg                           write_en;

  genvar i;
  generate
    for (i=0; i < CONV_SIZE-1; i = i+1) begin : linebuffer_sdpram

      simple_dual_ported_ram #(
        .DATA_WIDTH   (MEM_WIDTH),
        .ADDR_WIDTH   (MEM_DEPTH)
      ) sdpram
      (
        .clk      (clk),
        .w_en     (write_en),
        .w_addr   (write_counter),
        .w_data   (line_data[i]),
        .r_en     (read_en),
        .r_addr   (read_counter),
        .r_data   (line_data[i+1])
      );

      // remap data from line buffers to match AXI video stream pixel data
      assign line_data_out[(CONV_SIZE-i-2) * S_AXIS_DATA_WIDTH + MEM_WIDTH - 1 : (CONV_SIZE-i-2) * S_AXIS_DATA_WIDTH] = line_data[i+1];

    end
  endgenerate

  // remap to AXI video stream pixel data
  assign line_data_out[CONV_SIZE * S_AXIS_DATA_WIDTH-1 : (CONV_SIZE-1) * S_AXIS_DATA_WIDTH] = pipe_0_tdata;

  // pipeline stage 0
  assign pipe_0_tready = pipe_1_tready | ~pipe_0_tvalid | (ignore_lines != '0);

  assign read_en = pipe_0_tready & pipe_0_tvalid;

  always_ff @ (posedge clk) begin
    write_en        <= 1'b0;

    if (s_axis_tready == 1'b1) begin

      if (s_axis_tvalid == 1'b1) begin
        // increment read counter on valid transfer
        read_counter  <= read_counter + 1;

        // write current data to previous read location
        write_counter <= read_counter;
        write_en      <= '1;
        line_data[0]  <= s_axis_tdata[MEM_WIDTH-1:0];

        output_enable_d <= output_enable;
        if (ignore_lines == '0) begin
            output_enable <= '1;
        end

        if (s_axis_tlast == 1'b1) begin
          // reset read counter
          read_counter <= '0;
          if (ignore_lines != '0) begin
            ignore_lines <= ignore_lines - 1;
          end
        end

        if (s_axis_tuser[0] == 1'b1) begin
          // TUSER start frame
          // reset number of lines to ignore
          ignore_lines  <= CONV_SIZE[$clog2(CONV_SIZE)-1:0]-1;
          output_enable <= '0;
        end
      end

      // register everything else
      pipe_0_tdata   <= s_axis_tdata;
      pipe_0_tvalid  <= s_axis_tvalid;
      pipe_0_tlast   <= s_axis_tlast;
      pipe_0_tuser   <= s_axis_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_0_tvalid   <= '0;
      read_counter    <= '0;
      write_counter   <= '0;
      ignore_lines    <= '0;
      output_enable   <= '0;
      output_enable_d <= '0;
      write_en        <= '0;
    end
  end

  // pipeline stage 1
  assign pipe_1_tready = m_axis_tready | ~pipe_1_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_1_tready == 1'b1 ) begin
      pipe_1_tdata    <= line_data_out;
      pipe_1_tvalid   <= pipe_0_tvalid & output_enable;
      pipe_1_tlast    <= pipe_0_tlast;
      pipe_1_tuser    <= pipe_0_tuser;
      // re-create start of frame signal from output enable
      pipe_1_tuser[0] <= output_enable & ~output_enable_d;
    end

    if (rstn == 1'b0) begin
      pipe_1_tvalid   <= '0;
    end
  end

  // assign outputs
  assign s_axis_tready  = pipe_0_tready;

  assign m_axis_tdata   = pipe_1_tdata;
  assign m_axis_tvalid  = pipe_1_tvalid;
  assign m_axis_tlast   = pipe_1_tlast;
  assign m_axis_tuser   = pipe_1_tuser;

endmodule
