// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module bitsqrt
  #(
    // Pixel per cycle. 1, 2 or 4
    parameter PIXEL_PER_CYCLE                     = 4,
    // Pixel bit width. 10, 12, 14, 16, 18, 20, 22, 24
    parameter PIXEL_BIT_WIDTH                     = 32, // TODO: only works for >= 14 right now...
    parameter DATA_WIDTH                          = 8*$rtoi($floor((PIXEL_PER_CYCLE * PIXEL_BIT_WIDTH + 7)/8)),
    parameter TUSER_WIDTH                         = 1,
    parameter BITSQRT_FILE                        = "../../rtl/bitsqrt.mem"
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

  localparam ROM_WIDTH              = 32;
  localparam ROM_DEPTH              = 10;

  localparam LZC_COUNT_WIDTH        = $clog2(PIXEL_BIT_WIDTH/2);
  localparam LZC_BIT_WIDTH          = 2 ** $clog2(PIXEL_BIT_WIDTH);
  localparam LZC_DATA_WIDTH         = PIXEL_PER_CYCLE * LZC_BIT_WIDTH;
  localparam LZC_MAX                = LZC_BIT_WIDTH-1;
  localparam LZC_STAGES             = $clog2(PIXEL_BIT_WIDTH/2);

  localparam SHIFT_BIT_WIDTH        = $clog2(ROM_WIDTH);
  localparam SHIFT_BIT_PADDING      = SHIFT_BIT_WIDTH-(LZC_COUNT_WIDTH-1);

  reg [LZC_BIT_WIDTH-1:0]           pipe_pixel0[LZC_STAGES:0];
  reg [LZC_BIT_WIDTH-1:0]           pipe_pixel1[LZC_STAGES:0];
  reg [LZC_BIT_WIDTH-1:0]           pipe_pixel2[LZC_STAGES:0];
  reg [LZC_BIT_WIDTH-1:0]           pipe_pixel3[LZC_STAGES:0];
  reg                               pipe_tvalid[LZC_STAGES:0];
  // verilator lint_off UNOPTFLAT
  wire                              pipe_tready[LZC_STAGES:0];
  // verilator lint_on UNOPTFLAT
  reg                               pipe_tlast[LZC_STAGES:0];
  reg [TUSER_WIDTH-1:0]             pipe_tuser[LZC_STAGES:0];
  reg [LZC_COUNT_WIDTH-1:0]         pipe_lzc0[LZC_STAGES:0];
  reg [LZC_COUNT_WIDTH-1:0]         pipe_lzc1[LZC_STAGES:0];
  reg [LZC_COUNT_WIDTH-1:0]         pipe_lzc2[LZC_STAGES:0];
  reg [LZC_COUNT_WIDTH-1:0]         pipe_lzc3[LZC_STAGES:0];

  reg                               pipe_0_tvalid = 'b0;
  wire                              pipe_0_tready;
  reg                               pipe_0_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_0_tuser;
  reg [SHIFT_BIT_WIDTH:0]           pipe_0_shift0;
  reg [SHIFT_BIT_WIDTH:0]           pipe_0_shift1;
  reg [SHIFT_BIT_WIDTH:0]           pipe_0_shift2;
  reg [SHIFT_BIT_WIDTH:0]           pipe_0_shift3;

  reg [DATA_WIDTH-1:0]              pipe_1_tdata;
  wire [DATA_WIDTH-1:0]             pipe_1_tdata_wire;
  reg                               pipe_1_tvalid = 'b0;
  wire                              pipe_1_tready;
  reg                               pipe_1_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_1_tuser;

  wire                              r_rom_en;
  wire [ROM_DEPTH-1:0]              r_rom1_addra;
  wire [ROM_WIDTH-1:0]              r_rom1_dataa;
  wire [ROM_DEPTH-1:0]              r_rom1_addrb;
  wire [ROM_WIDTH-1:0]              r_rom1_datab;

  wire [ROM_DEPTH-1:0]              r_rom2_addra;
  wire [ROM_WIDTH-1:0]              r_rom2_dataa;
  wire [ROM_DEPTH-1:0]              r_rom2_addrb;
  wire [ROM_WIDTH-1:0]              r_rom2_datab;

  // assign inputs
  assign s_axis_tready              = pipe_tready[LZC_STAGES];
  assign pipe_tvalid[LZC_STAGES]    = s_axis_tvalid;
  assign pipe_tlast[LZC_STAGES]     = s_axis_tlast;
  assign pipe_tuser[LZC_STAGES]     = s_axis_tuser;

  assign pipe_lzc0[LZC_STAGES]      = {LZC_STAGES{1'b1}};
  assign pipe_lzc1[LZC_STAGES]      = {LZC_STAGES{1'b1}};
  assign pipe_lzc2[LZC_STAGES]      = {LZC_STAGES{1'b1}};
  assign pipe_lzc3[LZC_STAGES]      = {LZC_STAGES{1'b1}};

  // assign input pixel
  generate

    assign pipe_pixel0[LZC_STAGES] = {{(LZC_BIT_WIDTH-PIXEL_BIT_WIDTH){1'b0}}, s_axis_tdata[PIXEL_BIT_WIDTH-1:0]};

    if (PIXEL_PER_CYCLE > 1) begin
      assign pipe_pixel1[LZC_STAGES] = {{(LZC_BIT_WIDTH-PIXEL_BIT_WIDTH){1'b0}}, s_axis_tdata[2*PIXEL_BIT_WIDTH-1:PIXEL_BIT_WIDTH]};
    end

    if (PIXEL_PER_CYCLE > 2) begin
      assign pipe_pixel2[LZC_STAGES] = {{(LZC_BIT_WIDTH-PIXEL_BIT_WIDTH){1'b0}}, s_axis_tdata[3*PIXEL_BIT_WIDTH-1:2*PIXEL_BIT_WIDTH]};
    end

    if (PIXEL_PER_CYCLE > 3) begin
      assign pipe_pixel3[LZC_STAGES] = {{(LZC_BIT_WIDTH-PIXEL_BIT_WIDTH){1'b0}}, s_axis_tdata[4*PIXEL_BIT_WIDTH-1:3*PIXEL_BIT_WIDTH]};
    end

  endgenerate

  generate

    for (genvar i = LZC_STAGES-1; i >= 0; i = i - 1) begin

      assign pipe_tready[i+1] = pipe_tready[i] | ~pipe_tvalid[i+1];

      always_ff @ (posedge clk) begin
        if (pipe_tready[i] == 1'b1) begin

          // register everything
          pipe_tvalid[i]          <= pipe_tvalid[i+1];
          pipe_tlast[i]           <= pipe_tlast[i+1];
          pipe_tuser[i]           <= pipe_tuser[i+1];

          pipe_pixel0[i]          <= pipe_pixel0[i+1];
          pipe_pixel1[i]          <= pipe_pixel1[i+1];
          pipe_pixel2[i]          <= pipe_pixel2[i+1];
          pipe_pixel3[i]          <= pipe_pixel3[i+1];

          pipe_lzc0[i]            <= pipe_lzc0[i+1];
          pipe_lzc1[i]            <= pipe_lzc1[i+1];
          pipe_lzc2[i]            <= pipe_lzc2[i+1];
          pipe_lzc3[i]            <= pipe_lzc3[i+1];

          // if upper 2**i bts are all zero, we shift up the data and reset the corresponding leading zero count bit
          // in the end, we will have the left-aligned remaining data (must be a 1 in first position)
          // the leading zero count lzc is negated, because in do not want to count the zeros, but compute log2
          // 111...1 - xxx..x = ~(xxx...x)
          if (pipe_pixel0[i+1][LZC_BIT_WIDTH-1:LZC_BIT_WIDTH-2**(i+1)] == 'b0) begin
            pipe_pixel0[i]        <= pipe_pixel0[i+1] <<< 2**(i+1);
            pipe_lzc0[i][i]       <= 1'b0;
          end

          if (pipe_pixel1[i+1][LZC_BIT_WIDTH-1:LZC_BIT_WIDTH-2**(i+1)] == 'b0) begin
            pipe_pixel1[i]        <= pipe_pixel1[i+1] <<< 2**(i+1);
            pipe_lzc1[i][i]       <= 1'b0;
          end

          if (pipe_pixel2[i+1][LZC_BIT_WIDTH-1:LZC_BIT_WIDTH-2**(i+1)] == 'b0) begin
            pipe_pixel2[i]        <= pipe_pixel2[i+1] <<< 2**(i+1);
            pipe_lzc2[i][i]       <= 1'b0;
          end

          if (pipe_pixel3[i+1][LZC_BIT_WIDTH-1:LZC_BIT_WIDTH-2**(i+1)] == 'b0) begin
            pipe_pixel3[i]        <= pipe_pixel3[i+1] <<< 2**(i+1);
            pipe_lzc3[i][i]       <= 1'b0;
          end
        end

        if (rstn == 1'b0) begin
          pipe_tvalid[i]   <= '0;
        end
      end

    end

  endgenerate

  assign r_rom_en      = pipe_tready[0] & pipe_tvalid[0];

  // map ROM ports to pixels
  assign r_rom1_addra  = pipe_pixel0[0][LZC_BIT_WIDTH-1:LZC_BIT_WIDTH-(ROM_DEPTH)];
  assign r_rom1_addrb  = pipe_pixel1[0][LZC_BIT_WIDTH-1:LZC_BIT_WIDTH-(ROM_DEPTH)];
  assign r_rom2_addra  = pipe_pixel2[0][LZC_BIT_WIDTH-1:LZC_BIT_WIDTH-(ROM_DEPTH)];
  assign r_rom2_addrb  = pipe_pixel3[0][LZC_BIT_WIDTH-1:LZC_BIT_WIDTH-(ROM_DEPTH)];

  simple_dual_ported_rom #(
    .DATA_WIDTH     (ROM_WIDTH),
    .ADDR_WIDTH     (ROM_DEPTH),
    .MEM_FILE       (BITSQRT_FILE)
  ) lut_rom1_inst
  (
    .clk            (clk),
    .r_ena          (r_rom_en),
    .r_addra        (r_rom1_addra),
    .r_dataa        (r_rom1_dataa),
    .r_enb          (r_rom_en),
    .r_addrb        (r_rom1_addrb),
    .r_datab        (r_rom1_datab)
  );

  simple_dual_ported_rom #(
    .DATA_WIDTH     (ROM_WIDTH),
    .ADDR_WIDTH     (ROM_DEPTH),
    .MEM_FILE       (BITSQRT_FILE)
  ) lut_rom2_inst
  (
    .clk            (clk),
    .r_ena          (r_rom_en),
    .r_addra        (r_rom2_addra),
    .r_dataa        (r_rom2_dataa),
    .r_enb          (r_rom_en),
    .r_addrb        (r_rom2_addrb),
    .r_datab        (r_rom2_datab)
  );

  assign pipe_tready[0] = pipe_0_tready;

  // pipeline stage 0
  assign pipe_0_tready = pipe_1_tready | ~pipe_0_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_0_tready == 1'b1) begin
      pipe_0_tvalid   <= pipe_tvalid[0];
      pipe_0_tlast    <= pipe_tlast[0];
      pipe_0_tuser    <= pipe_tuser[0];
      // compute the final output shift
      pipe_0_shift0   <= SHIFT_BIT_WIDTH'((ROM_WIDTH-1) - (PIXEL_BIT_WIDTH/2)) - {{(SHIFT_BIT_PADDING){1'b0}}, {pipe_lzc0[0]}};
      pipe_0_shift1   <= SHIFT_BIT_WIDTH'((ROM_WIDTH-1) - (PIXEL_BIT_WIDTH/2)) - {{(SHIFT_BIT_PADDING){1'b0}}, {pipe_lzc1[0]}};
      pipe_0_shift2   <= SHIFT_BIT_WIDTH'((ROM_WIDTH-1) - (PIXEL_BIT_WIDTH/2)) - {{(SHIFT_BIT_PADDING){1'b0}}, {pipe_lzc2[0]}};
      pipe_0_shift3   <= SHIFT_BIT_WIDTH'((ROM_WIDTH-1) - (PIXEL_BIT_WIDTH/2)) - {{(SHIFT_BIT_PADDING){1'b0}}, {pipe_lzc3[0]}};
    end

    if (rstn == 1'b0) begin
      pipe_0_tvalid   <= '0;
    end
  end

  // pipeline stage 1
  assign pipe_1_tready = m_axis_tready | ~pipe_1_tvalid;

  generate

    // TODO: add register stage (or multiple) for barrel shifter here.
    wire [ROM_WIDTH-1:0] pixel_0_shift = (r_rom1_dataa[ROM_WIDTH-1:0] >> pipe_0_shift0);
    assign pipe_1_tdata_wire[PIXEL_BIT_WIDTH-1:0] = pixel_0_shift[PIXEL_BIT_WIDTH-1:0];

    if (PIXEL_PER_CYCLE > 1) begin
      wire [ROM_WIDTH-1:0] pixel_1_shift = (r_rom1_datab[ROM_WIDTH-1:0] >> pipe_0_shift1);
      assign pipe_1_tdata_wire[2*PIXEL_BIT_WIDTH-1:PIXEL_BIT_WIDTH] = pixel_1_shift[PIXEL_BIT_WIDTH-1:0];
    end

    if (PIXEL_PER_CYCLE > 2) begin
      wire [ROM_WIDTH-1:0] pixel_2_shift = (r_rom2_dataa[ROM_WIDTH-1:0] >> pipe_0_shift2);
      assign pipe_1_tdata_wire[3*PIXEL_BIT_WIDTH-1:2*PIXEL_BIT_WIDTH] = pixel_2_shift[PIXEL_BIT_WIDTH-1:0];
    end

    if (PIXEL_PER_CYCLE > 3) begin
      wire [ROM_WIDTH-1:0] pixel_3_shift = (r_rom2_datab[ROM_WIDTH-1:0] >> pipe_0_shift3);
      assign pipe_1_tdata_wire[4*PIXEL_BIT_WIDTH-1:3*PIXEL_BIT_WIDTH] = pixel_3_shift[PIXEL_BIT_WIDTH-1:0];
    end

  endgenerate

  always_ff @ (posedge clk) begin
    if (pipe_1_tready == 1'b1) begin
      pipe_1_tdata  <= pipe_1_tdata_wire;
      pipe_1_tvalid <= pipe_0_tvalid;
      pipe_1_tlast  <= pipe_0_tlast;
      pipe_1_tuser  <= pipe_0_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_1_tvalid   <= '0;
    end
  end

  // assign outputs
  assign m_axis_tdata   = pipe_1_tdata;
  assign m_axis_tvalid  = pipe_1_tvalid;
  assign m_axis_tlast   = pipe_1_tlast;
  assign m_axis_tuser   = pipe_1_tuser;

endmodule
