// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module colorgain
  #(
    // CFA orientation. CFA_BG=0, CFA_GB=1, CFA_GR=2, CFA_RG=3
    parameter CFA_ORIENTATION                     = 3,
    // Pixel per cycle. 1, 2 or 4
    parameter PIXEL_PER_CYCLE                     = 4,
    // Pixel bit width. 8, 10, 12, 14, 16, 18
    parameter PIXEL_BIT_WIDTH                     = 14,
    parameter DATA_WIDTH                          = 8*$rtoi($floor((PIXEL_PER_CYCLE * PIXEL_BIT_WIDTH + 7)/8)),
    parameter TUSER_WIDTH                         = 1
  )
  (
    input  wire                     clk,
    input  wire                     rstn,

    // format: Q9.7
    input  wire  [15:0]             rgain,
    input  wire  [15:0]             bgain,
    input  wire  [15:0]             g0gain,
    input  wire  [15:0]             g1gain,

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

  function [PIXEL_BIT_WIDTH-1:0] shift_and_saturate( input [PIXEL_BIT_WIDTH+16-1:0] mult_result );
    begin
      shift_and_saturate = mult_result[PIXEL_BIT_WIDTH+16-1:PIXEL_BIT_WIDTH+8-1] == 'b0 ? mult_result[PIXEL_BIT_WIDTH+7-1:7] : '1;
    end
  endfunction

  reg [15:0]            int_rgain = 'b0;
  reg [15:0]            int_bgain = 'b0;
  reg [15:0]            int_g0gain = 'b0;
  reg [15:0]            int_g1gain = 'b0;

  reg [DATA_WIDTH-1:0]  pipe_0_tdata;
  reg                   pipe_0_tvalid = 'b0;
  wire                  pipe_0_tready;
  reg                   pipe_0_tlast;
  reg [TUSER_WIDTH-1:0] pipe_0_tuser;

  reg [DATA_WIDTH-1:0]  pipe_1_tdata;
  reg                   pipe_1_tvalid = 'b0;
  wire                  pipe_1_tready;
  reg                   pipe_1_tlast;
  reg [TUSER_WIDTH-1:0] pipe_1_tuser;

  reg [DATA_WIDTH-1:0]  pipe_2_tdata;
  reg                   pipe_2_tvalid = 'b0;
  wire                  pipe_2_tready;
  reg                   pipe_2_tlast;
  reg [TUSER_WIDTH-1:0] pipe_2_tuser;

  reg [DATA_WIDTH-1:0]  pipe_3_tdata;
  reg                   pipe_3_tvalid = 'b0;
  wire                  pipe_3_tready;
  reg                   pipe_3_tlast;
  reg [TUSER_WIDTH-1:0] pipe_3_tuser;

  reg [0:0] current_pixel;
  reg [0:0] current_line;

  reg new_line = 'b0;

  reg [DATA_WIDTH-1:0] multiplier_output;

  // pipeline stage 0
  assign pipe_0_tready = pipe_1_tready | ~pipe_0_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_0_tready == 1'b1) begin
      if (s_axis_tvalid == 1'b1) begin
        // pixel logic
        // only increment pixel when
        current_pixel <= current_pixel + PIXEL_PER_CYCLE[0];
        new_line <= 1'b0;
        if (new_line == 1'b1) begin
          // increment line and reset pixel
          current_line <= current_line + 1;
          current_pixel <= 1'b0;
        end
        if (s_axis_tlast == 1'b1) begin
          new_line <= 1'b1;
        end
        if (s_axis_tuser[0] == 1'b1) begin
          // reset line and pixel with start of frame
          current_line <= 1'b0;
          current_pixel <= 1'b0;

          // capture gain values at start of frame
          int_bgain <= bgain;
          int_rgain <= rgain;
          int_g0gain <= g0gain;
          int_g1gain <= g1gain;
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
    end
  end

  // pipeline stage 1
  assign pipe_1_tready = pipe_2_tready | ~pipe_1_tvalid;

  generate

    if (PIXEL_PER_CYCLE == 1) begin

      wire [PIXEL_BIT_WIDTH-1:0] pixel_0 = pipe_0_tdata[PIXEL_BIT_WIDTH-1:0];

      reg [15:0] pixel_0_gain;
      reg [15:0] pipe_1_pixel_0_gain;
      reg [PIXEL_BIT_WIDTH-1:0] pipe_1_pixel_0;

      always_comb begin
        if (CFA_ORIENTATION == 0) begin
          case ({current_line, current_pixel})
            2'b00: pixel_0_gain = int_bgain;
            2'b01: pixel_0_gain = int_g0gain;
            2'b10: pixel_0_gain = int_g1gain;
            2'b11: pixel_0_gain = int_rgain;
          endcase
        end else if (CFA_ORIENTATION == 1) begin
          case ({current_line, current_pixel})
            2'b00: pixel_0_gain = int_g0gain;
            2'b01: pixel_0_gain = int_bgain;
            2'b10: pixel_0_gain = int_rgain;
            2'b11: pixel_0_gain = int_g1gain;
          endcase
        end else if (CFA_ORIENTATION == 2) begin
          case ({current_line, current_pixel})
            2'b00: pixel_0_gain = int_g0gain;
            2'b01: pixel_0_gain = int_rgain;
            2'b10: pixel_0_gain = int_bgain;
            2'b11: pixel_0_gain = int_g1gain;
          endcase
        end else if (CFA_ORIENTATION == 3) begin
          case ({current_line, current_pixel})
            2'b00: pixel_0_gain = int_rgain;
            2'b01: pixel_0_gain = int_g0gain;
            2'b10: pixel_0_gain = int_g1gain;
            2'b11: pixel_0_gain = int_bgain;
          endcase
        end
      end

      always_ff @ (posedge clk) begin
        if (pipe_1_tready == 1'b1) begin
          pipe_1_pixel_0      <= pixel_0;
          pipe_1_pixel_0_gain <= pixel_0_gain;
          pipe_1_tvalid       <= pipe_0_tvalid;
          pipe_1_tlast        <= pipe_0_tlast;
          pipe_1_tuser        <= pipe_0_tuser;
        end

        if (rstn == 1'b0) begin
          pipe_1_tvalid   <= '0;
        end
      end

      always_comb begin
        multiplier_output[PIXEL_BIT_WIDTH-1:0] = shift_and_saturate(pipe_1_pixel_0 * pipe_1_pixel_0_gain);
      end

    end else if (PIXEL_PER_CYCLE == 2) begin

      wire [PIXEL_BIT_WIDTH-1:0] pixel_0 = pipe_0_tdata[PIXEL_BIT_WIDTH-1:0];
      wire [PIXEL_BIT_WIDTH-1:0] pixel_1 = pipe_0_tdata[2*PIXEL_BIT_WIDTH-1:PIXEL_BIT_WIDTH];

      reg [15:0] pixel_0_gain;
      reg [15:0] pixel_1_gain;
      reg [15:0] pipe_1_pixel_0_gain;
      reg [15:0] pipe_1_pixel_1_gain;
      reg [PIXEL_BIT_WIDTH-1:0] pipe_1_pixel_0;
      reg [PIXEL_BIT_WIDTH-1:0] pipe_1_pixel_1;

      always_comb begin
        if (CFA_ORIENTATION == 0) begin
          case (current_line)
            1'b0: begin
              pixel_0_gain = int_bgain;
              pixel_1_gain = int_g0gain;
            end
            1'b1: begin
              pixel_0_gain = int_g1gain;
              pixel_1_gain = int_rgain;
            end
          endcase
        end else if (CFA_ORIENTATION == 1) begin
          case (current_line)
            1'b0: begin
              pixel_0_gain = int_g0gain;
              pixel_1_gain = int_bgain;
            end
            1'b1: begin
              pixel_0_gain = int_rgain;
              pixel_1_gain = int_g1gain;
            end
          endcase
        end else if (CFA_ORIENTATION == 2) begin
          case (current_line)
            1'b0: begin
              pixel_0_gain = int_g0gain;
              pixel_1_gain = int_rgain;
            end
            1'b1: begin
              pixel_0_gain = int_bgain;
              pixel_1_gain = int_g1gain;
            end
          endcase
        end else if (CFA_ORIENTATION == 3) begin
          case (current_line)
            1'b0: begin
              pixel_0_gain = int_rgain;
              pixel_1_gain = int_g0gain;
            end
            1'b1: begin
              pixel_0_gain = int_g1gain;
              pixel_1_gain = int_bgain;
            end
          endcase
        end
      end

      always_ff @ (posedge clk) begin
        if (pipe_1_tready == 1'b1) begin
          pipe_1_pixel_0      <= pixel_0;
          pipe_1_pixel_1      <= pixel_1;
          pipe_1_pixel_0_gain <= pixel_0_gain;
          pipe_1_pixel_1_gain <= pixel_1_gain;
          pipe_1_tvalid       <= pipe_0_tvalid;
          pipe_1_tlast        <= pipe_0_tlast;
          pipe_1_tuser        <= pipe_0_tuser;
        end

        if (rstn == 1'b0) begin
          pipe_1_tvalid   <= '0;
        end
      end

      always_comb begin
        multiplier_output[PIXEL_BIT_WIDTH-1:0] = shift_and_saturate(pipe_1_pixel_0 * pipe_1_pixel_0_gain);
        multiplier_output[2*PIXEL_BIT_WIDTH-1:PIXEL_BIT_WIDTH] = shift_and_saturate(pipe_1_pixel_1 * pipe_1_pixel_1_gain);
      end

    end else if (PIXEL_PER_CYCLE == 4) begin

      wire [PIXEL_BIT_WIDTH-1:0] pixel_0 = pipe_0_tdata[PIXEL_BIT_WIDTH-1:0];
      wire [PIXEL_BIT_WIDTH-1:0] pixel_1 = pipe_0_tdata[2*PIXEL_BIT_WIDTH-1:1*PIXEL_BIT_WIDTH];
      wire [PIXEL_BIT_WIDTH-1:0] pixel_2 = pipe_0_tdata[3*PIXEL_BIT_WIDTH-1:2*PIXEL_BIT_WIDTH];
      wire [PIXEL_BIT_WIDTH-1:0] pixel_3 = pipe_0_tdata[4*PIXEL_BIT_WIDTH-1:3*PIXEL_BIT_WIDTH];

      reg [15:0] pixel_0_gain;
      reg [15:0] pixel_1_gain;
      reg [15:0] pipe_1_pixel_0_gain;
      reg [15:0] pipe_1_pixel_1_gain;
      reg [PIXEL_BIT_WIDTH-1:0] pipe_1_pixel_0;
      reg [PIXEL_BIT_WIDTH-1:0] pipe_1_pixel_1;
      reg [PIXEL_BIT_WIDTH-1:0] pipe_1_pixel_2;
      reg [PIXEL_BIT_WIDTH-1:0] pipe_1_pixel_3;

      always_comb begin
        if (CFA_ORIENTATION == 0) begin
          case (current_line)
            1'b0: begin
              pixel_0_gain = int_bgain;
              pixel_1_gain = int_g0gain;
            end
            1'b1: begin
              pixel_0_gain = int_g1gain;
              pixel_1_gain = int_rgain;
            end
          endcase
        end else if (CFA_ORIENTATION == 1) begin
          case (current_line)
            1'b0: begin
              pixel_0_gain = int_g0gain;
              pixel_1_gain = int_bgain;
            end
            1'b1: begin
              pixel_0_gain = int_rgain;
              pixel_1_gain = int_g1gain;
            end
          endcase
        end else if (CFA_ORIENTATION == 2) begin
          case (current_line)
            1'b0: begin
              pixel_0_gain = int_g0gain;
              pixel_1_gain = int_rgain;
            end
            1'b1: begin
              pixel_0_gain = int_bgain;
              pixel_1_gain = int_g1gain;
            end
          endcase
        end else if (CFA_ORIENTATION == 3) begin
          case (current_line)
            1'b0: begin
              pixel_0_gain = int_rgain;
              pixel_1_gain = int_g0gain;
            end
            1'b1: begin
              pixel_0_gain = int_g1gain;
              pixel_1_gain = int_bgain;
            end
          endcase
        end
      end

      always_ff @ (posedge clk) begin
        if (pipe_1_tready == 1'b1) begin
          pipe_1_pixel_0      <= pixel_0;
          pipe_1_pixel_1      <= pixel_1;
          pipe_1_pixel_2      <= pixel_2;
          pipe_1_pixel_3      <= pixel_3;
          pipe_1_pixel_0_gain <= pixel_0_gain;
          pipe_1_pixel_1_gain <= pixel_1_gain;
          pipe_1_tvalid       <= pipe_0_tvalid;
          pipe_1_tlast        <= pipe_0_tlast;
          pipe_1_tuser        <= pipe_0_tuser;
        end

        if (rstn == 1'b0) begin
          pipe_1_tvalid   <= '0;
        end
      end

      always_comb begin
        multiplier_output[PIXEL_BIT_WIDTH-1:0] = shift_and_saturate(pipe_1_pixel_0 * pipe_1_pixel_0_gain);
        multiplier_output[2*PIXEL_BIT_WIDTH-1:1*PIXEL_BIT_WIDTH] = shift_and_saturate(pipe_1_pixel_1 * pipe_1_pixel_1_gain);
        multiplier_output[3*PIXEL_BIT_WIDTH-1:2*PIXEL_BIT_WIDTH] = shift_and_saturate(pipe_1_pixel_2 * pipe_1_pixel_0_gain);
        multiplier_output[4*PIXEL_BIT_WIDTH-1:3*PIXEL_BIT_WIDTH] = shift_and_saturate(pipe_1_pixel_3 * pipe_1_pixel_1_gain);
      end

    end

  endgenerate

  // pipeline stage 1
  assign pipe_2_tready = pipe_3_tready | ~pipe_2_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_2_tready == 1'b1) begin
      pipe_2_tdata   <= multiplier_output;
      pipe_2_tvalid  <= pipe_1_tvalid;
      pipe_2_tlast   <= pipe_1_tlast;
      pipe_2_tuser   <= pipe_1_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_2_tvalid   <= '0;
    end
  end

  // pipeline stage 3
  assign pipe_3_tready = m_axis_tready | ~pipe_3_tvalid;

  always_ff @ (posedge clk) begin
    if (pipe_3_tready == 1'b1) begin
      pipe_3_tdata   <= pipe_2_tdata;
      pipe_3_tvalid  <= pipe_2_tvalid;
      pipe_3_tlast   <= pipe_2_tlast;
      pipe_3_tuser   <= pipe_2_tuser;
    end

    if (rstn == 1'b0) begin
      pipe_3_tvalid   <= '0;
    end
  end

  // assign outputs
  assign s_axis_tready  = pipe_0_tready;
  assign m_axis_tdata   = pipe_3_tdata;
  assign m_axis_tvalid  = pipe_3_tvalid;
  assign m_axis_tlast   = pipe_3_tlast;
  assign m_axis_tuser   = pipe_3_tuser;

endmodule
