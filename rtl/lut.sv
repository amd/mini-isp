// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module lut
  #(
    // Pixel per cycle. 1, 2 or 4
    parameter PIXEL_PER_CYCLE                     = 1,
    // Pixel bit width. 10, 12, 14, 16, 18, 20, 22, 24
    parameter INPUT_PIXEL_BIT_WIDTH               = 12,
    parameter OUTPUT_PIXEL_BIT_WIDTH              = 8,
    parameter INPUT_DATA_WIDTH                    = 8*$rtoi($floor((PIXEL_PER_CYCLE * INPUT_PIXEL_BIT_WIDTH + 7)/8)),
    parameter OUTPUT_DATA_WIDTH                   = 8*$rtoi($floor((PIXEL_PER_CYCLE * OUTPUT_PIXEL_BIT_WIDTH + 7)/8)),
    parameter TUSER_WIDTH                         = 1,
    parameter LUT_FILE                            = "../../rtl/lut.mem"
  )
  (
    input  wire                           clk,
    input  wire                           rstn,

    input  wire  [INPUT_DATA_WIDTH-1:0]   s_axis_tdata,
    input  wire                           s_axis_tvalid,
    output wire                           s_axis_tready,
    input  wire                           s_axis_tlast,
    input  wire  [TUSER_WIDTH-1:0]        s_axis_tuser,

    output wire  [OUTPUT_DATA_WIDTH-1:0]  m_axis_tdata,
    output wire                           m_axis_tvalid,
    input  wire                           m_axis_tready,
    output wire                           m_axis_tlast,
    output wire  [TUSER_WIDTH-1:0]        m_axis_tuser
  );

  localparam ROM_WIDTH              = OUTPUT_PIXEL_BIT_WIDTH;
  localparam ROM_DEPTH              = INPUT_PIXEL_BIT_WIDTH;

  reg [INPUT_PIXEL_BIT_WIDTH-1:0]   pipe_0_pixel0;
  reg [INPUT_PIXEL_BIT_WIDTH-1:0]   pipe_0_pixel1;
  reg [INPUT_PIXEL_BIT_WIDTH-1:0]   pipe_0_pixel2;
  reg [INPUT_PIXEL_BIT_WIDTH-1:0]   pipe_0_pixel3;
  wire [INPUT_PIXEL_BIT_WIDTH-1:0]  pipe_0_pixel0_wire;
  wire [INPUT_PIXEL_BIT_WIDTH-1:0]  pipe_0_pixel1_wire;
  wire [INPUT_PIXEL_BIT_WIDTH-1:0]  pipe_0_pixel2_wire;
  wire [INPUT_PIXEL_BIT_WIDTH-1:0]  pipe_0_pixel3_wire;
  reg                               pipe_0_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_0_tuser;
  reg                               pipe_0_tvalid = 'b0;
  wire                              pipe_0_tready;

  wire [OUTPUT_DATA_WIDTH-1:0]      pipe_1_tdata_wire;
  reg                               pipe_1_tvalid = 'b0;
  wire                              pipe_1_tready;
  reg                               pipe_1_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_1_tuser;

  reg [OUTPUT_DATA_WIDTH-1:0]       pipe_2_tdata;
  reg                               pipe_2_tvalid = 'b0;
  wire                              pipe_2_tready;
  reg                               pipe_2_tlast;
  reg [TUSER_WIDTH-1:0]             pipe_2_tuser;

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
  assign s_axis_tready              = pipe_0_tready;

  // assign input pixel
  generate

    assign pipe_0_pixel0_wire = s_axis_tdata[INPUT_PIXEL_BIT_WIDTH-1:0];

    if (PIXEL_PER_CYCLE > 1) begin
      assign pipe_0_pixel1_wire = s_axis_tdata[2*INPUT_PIXEL_BIT_WIDTH-1:INPUT_PIXEL_BIT_WIDTH];
    end

    if (PIXEL_PER_CYCLE > 2) begin
      assign pipe_0_pixel2_wire = s_axis_tdata[3*INPUT_PIXEL_BIT_WIDTH-1:2*INPUT_PIXEL_BIT_WIDTH];
    end

    if (PIXEL_PER_CYCLE > 3) begin
      assign pipe_0_pixel3_wire = s_axis_tdata[4*INPUT_PIXEL_BIT_WIDTH-1:3*INPUT_PIXEL_BIT_WIDTH];
    end

  endgenerate

  assign pipe_0_tready = pipe_1_tready | ~pipe_0_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_0_tready == 1'b1) begin
      pipe_0_pixel0   <= pipe_0_pixel0_wire;
      pipe_0_pixel1   <= pipe_0_pixel1_wire;
      pipe_0_pixel2   <= pipe_0_pixel2_wire;
      pipe_0_pixel3   <= pipe_0_pixel3_wire;
      pipe_0_tvalid   <= s_axis_tvalid;
      pipe_0_tlast    <= s_axis_tlast;
      pipe_0_tuser    <= s_axis_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_0_tvalid   <= '0;
    end
  end

  assign r_rom_en      = pipe_0_tready & pipe_0_tvalid;

  // map ROM ports to pixels
  assign r_rom1_addra  = pipe_0_pixel0;
  assign r_rom1_addrb  = pipe_0_pixel1;
  assign r_rom2_addra  = pipe_0_pixel2;
  assign r_rom2_addrb  = pipe_0_pixel3;

  simple_dual_ported_rom #(
    .DATA_WIDTH     (ROM_WIDTH),
    .ADDR_WIDTH     (ROM_DEPTH),
    .MEM_FILE       (LUT_FILE)
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
    .MEM_FILE       (LUT_FILE)
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

  // pipeline stage 1
  assign pipe_1_tready = pipe_2_tready | ~pipe_1_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_1_tready == 1'b1) begin
      pipe_1_tvalid   <= pipe_0_tvalid;
      pipe_1_tlast    <= pipe_0_tlast;
      pipe_1_tuser    <= pipe_0_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_1_tvalid   <= '0;
    end
  end

  generate

    assign pipe_1_tdata_wire[OUTPUT_PIXEL_BIT_WIDTH-1:0] = r_rom1_dataa;

    if (PIXEL_PER_CYCLE > 1) begin
      assign pipe_1_tdata_wire[2*OUTPUT_PIXEL_BIT_WIDTH-1:OUTPUT_PIXEL_BIT_WIDTH] = r_rom1_datab;
    end

    if (PIXEL_PER_CYCLE > 2) begin
      assign pipe_1_tdata_wire[3*OUTPUT_PIXEL_BIT_WIDTH-1:2*OUTPUT_PIXEL_BIT_WIDTH] = r_rom2_dataa;
    end

    if (PIXEL_PER_CYCLE > 3) begin
      assign pipe_1_tdata_wire[4*OUTPUT_PIXEL_BIT_WIDTH-1:3*OUTPUT_PIXEL_BIT_WIDTH] = r_rom2_datab;
    end

  endgenerate

  // pipeline stage 2
  assign pipe_2_tready = m_axis_tready | ~pipe_2_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_2_tready == 1'b1) begin
      pipe_2_tdata  <= pipe_1_tdata_wire;
      pipe_2_tvalid <= pipe_1_tvalid;
      pipe_2_tlast  <= pipe_1_tlast;
      pipe_2_tuser  <= pipe_1_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_2_tvalid   <= '0;
    end
  end

  // assign outputs
  assign m_axis_tdata   = pipe_2_tdata;
  assign m_axis_tvalid  = pipe_2_tvalid;
  assign m_axis_tlast   = pipe_2_tlast;
  assign m_axis_tuser   = pipe_2_tuser;

endmodule
