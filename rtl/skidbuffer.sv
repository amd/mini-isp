// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module skidbuffer
  #(
    parameter DATA_WIDTH                = 16,
    parameter TUSER_WIDTH               = 1
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

  reg                   skid_tvalid     = 1'b0;
  reg [DATA_WIDTH-1:0]  skid_tdata      = '0;
  reg                   skid_tlast      = 1'b0;
  reg [TUSER_WIDTH-1:0] skid_tuser      = '0;

  reg                   pipe_0_tvalid   = 1'b0;
  reg [DATA_WIDTH-1:0]  pipe_0_tdata    = '0;
  reg                   pipe_0_tlast    = 1'b0;
  reg [TUSER_WIDTH-1:0] pipe_0_tuser    = '0;

  assign s_axis_tready = ~skid_tvalid;

  // skid buffer
  always @(posedge clk) begin
    if ((s_axis_tvalid == 1'b1 && s_axis_tready == 1'b1) && (m_axis_tvalid == 1'b1 && m_axis_tready == 1'b0)) begin
      skid_tvalid <= 1'b1;
    end else if (m_axis_tready == 1'b1) begin
      skid_tvalid <= 1'b0;
    end

    // save data in skid buffer
    if (s_axis_tvalid == 1'b1 && s_axis_tready == 1'b1) begin
      skid_tdata  <= s_axis_tdata;
      skid_tlast  <= s_axis_tlast;
      skid_tuser  <= s_axis_tuser;
    end

    if (rstn == 1'b0) begin
      skid_tvalid <= 1'b0;
    end
  end

  // output logic & register
  always @(posedge clk) begin
    if (m_axis_tvalid == 1'b0 || m_axis_tready == 1'b1) begin
      pipe_0_tvalid <= s_axis_tvalid | skid_tvalid;

      if (skid_tvalid == 1'b1) begin
        pipe_0_tdata  <= skid_tdata;
        pipe_0_tlast  <= skid_tlast;
        pipe_0_tuser  <= skid_tuser;
      end else begin
        pipe_0_tdata  <= s_axis_tdata;
        pipe_0_tlast  <= s_axis_tlast;
        pipe_0_tuser  <= s_axis_tuser;
      end
    end

    if (rstn == 1'b0) begin
      pipe_0_tvalid   <= 1'b0;
    end
  end

  // assign outputs
  assign m_axis_tdata   = pipe_0_tdata;
  assign m_axis_tvalid  = pipe_0_tvalid;
  assign m_axis_tlast   = pipe_0_tlast;
  assign m_axis_tuser   = pipe_0_tuser;

endmodule
