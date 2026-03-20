// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module decompanding
  #(
    // Pixel per cycle. 1, 2 or 4
    parameter PIXEL_PER_CYCLE                     = 1,
    // Pixel bit width. 8, 10, 12, 14, 16, 18
    parameter PIXEL_BIT_WIDTH_IN                  = 12,
    parameter PIXEL_BIT_WIDTH_OUT                 = 24,
    parameter S_AXIS_DATA_WIDTH                   = 8*$rtoi($floor((PIXEL_PER_CYCLE * PIXEL_BIT_WIDTH_IN + 7)/8)),
    parameter M_AXIS_DATA_WIDTH                   = 8*$rtoi($floor((PIXEL_PER_CYCLE * PIXEL_BIT_WIDTH_OUT + 7)/8)),
    parameter TUSER_WIDTH                         = 1,
    parameter NUM_KNEE_POINTS                     = 16,
    parameter XLUT_FILE                           = "../../rtl/decompanding_xlut.mem",
    parameter YLUT_FILE                           = "../../rtl/decompanding_ylut_12_bit.mem",
    parameter FLUT_FILE                           = "../../rtl/decompanding_flut_12_bit.mem"
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

  reg [M_AXIS_DATA_WIDTH-1:0]   pipe_tdata[NUM_KNEE_POINTS:0];
  reg                           pipe_tvalid[NUM_KNEE_POINTS:0];
  // verilator lint_off UNOPTFLAT
  reg                           pipe_tready[NUM_KNEE_POINTS:0];
  // verilator lint_on UNOPTFLAT
  reg                           pipe_tlast[NUM_KNEE_POINTS:0];
  reg [TUSER_WIDTH-1:0]         pipe_tuser[NUM_KNEE_POINTS:0];

  reg [PIXEL_PER_CYCLE-1:0]     pipe_conversion_done[NUM_KNEE_POINTS:0];

  reg [31:0]                    knee_point_xlut[0:NUM_KNEE_POINTS];
  reg [31:0]                    knee_point_ylut[0:NUM_KNEE_POINTS];
  reg [7:0]                     knee_point_flut[0:NUM_KNEE_POINTS];

  initial begin
    $readmemh(XLUT_FILE, knee_point_xlut);
    $readmemh(YLUT_FILE, knee_point_ylut);
    $readmemh(FLUT_FILE, knee_point_flut);
  end

  // assign inputs
  assign s_axis_tready                        = pipe_tready[0];
  assign pipe_tvalid[0]                       = s_axis_tvalid;
  assign pipe_tlast[0]                        = s_axis_tlast;
  assign pipe_tuser[0]                        = s_axis_tuser;

  // for loop assign pixel
  generate
    for (genvar pixel = 0; pixel < PIXEL_PER_CYCLE; pixel = pixel + 1) begin
      assign pipe_tdata[0][pixel*PIXEL_BIT_WIDTH_OUT+PIXEL_BIT_WIDTH_IN-1:pixel*PIXEL_BIT_WIDTH_OUT] = s_axis_tdata[(pixel+1)*PIXEL_BIT_WIDTH_IN-1:pixel*PIXEL_BIT_WIDTH_IN];
      assign pipe_conversion_done[0][pixel]     = 1'b0;
    end
  endgenerate

  generate
    for (genvar i = 1; i <= NUM_KNEE_POINTS; i = i + 1) begin

      assign pipe_tready[i-1] = pipe_tready[i] | ~pipe_tvalid[i-1];

      if (PIXEL_PER_CYCLE == 1) begin
        // pipeline stage
        always_ff @ (posedge clk) begin
          if (pipe_tready[i] == 1'b1) begin

            // register everything
            pipe_tvalid[i]          <= pipe_tvalid[i-1];
            pipe_tlast[i]           <= pipe_tlast[i-1];
            pipe_tuser[i]           <= pipe_tuser[i-1];
            pipe_tdata[i]           <= pipe_tdata[i-1];
            pipe_conversion_done[i] <= pipe_conversion_done[i-1];

            if (i < NUM_KNEE_POINTS) begin
              // update data if it is below the knee point
              if ((pipe_conversion_done[i-1][0] == 1'b0) && (pipe_tdata[i-1][PIXEL_BIT_WIDTH_OUT-1:0] < knee_point_ylut[i][PIXEL_BIT_WIDTH_OUT-1:0])) begin
                pipe_tdata[i][PIXEL_BIT_WIDTH_OUT-1:0]  <= knee_point_xlut[i-1][PIXEL_BIT_WIDTH_OUT-1:0] + ((pipe_tdata[i-1][PIXEL_BIT_WIDTH_OUT-1:0] - knee_point_ylut[i-1][PIXEL_BIT_WIDTH_OUT-1:0]) << knee_point_flut[i]);
                pipe_conversion_done[i][0] <= 1'b1;
              end
            end else begin
              // last step saturation logic
              // saturation logic in case the data is above the highest LUT value
              if ((pipe_conversion_done[i-1][0] == 1'b0)) begin
                pipe_tdata[i][PIXEL_BIT_WIDTH_OUT-1:0] <= {PIXEL_BIT_WIDTH_OUT{1'b1}};
              end
            end
          end

          if (rstn == 1'b0) begin
            pipe_tvalid[i]   <= '0;
          end
        end

      end else if (PIXEL_PER_CYCLE == 2) begin
        // pipeline stage
        always_ff @ (posedge clk) begin
          if (pipe_tready[i] == 1'b1) begin

            // register everything
            pipe_tvalid[i]          <= pipe_tvalid[i-1];
            pipe_tlast[i]           <= pipe_tlast[i-1];
            pipe_tuser[i]           <= pipe_tuser[i-1];
            pipe_tdata[i]           <= pipe_tdata[i-1];
            pipe_conversion_done[i] <= pipe_conversion_done[i-1];

            if (i < NUM_KNEE_POINTS) begin
              if ((pipe_conversion_done[i-1][0] == 1'b0) && (pipe_tdata[i-1][PIXEL_BIT_WIDTH_OUT-1:0] < knee_point_ylut[i][PIXEL_BIT_WIDTH_OUT-1:0])) begin
                pipe_tdata[i][PIXEL_BIT_WIDTH_OUT-1:0]  <= knee_point_xlut[i-1][PIXEL_BIT_WIDTH_OUT-1:0] + ((pipe_tdata[i-1][PIXEL_BIT_WIDTH_OUT-1:0] - knee_point_ylut[i-1][PIXEL_BIT_WIDTH_OUT-1:0]) << knee_point_flut[i]);
                pipe_conversion_done[i][0] <= 1'b1;
              end
              if ((pipe_conversion_done[i-1][1] == 1'b0) && (pipe_tdata[i-1][2*PIXEL_BIT_WIDTH_OUT-1:PIXEL_BIT_WIDTH_OUT] < knee_point_ylut[i][PIXEL_BIT_WIDTH_OUT-1:0])) begin
                pipe_tdata[i][2*PIXEL_BIT_WIDTH_OUT-1:PIXEL_BIT_WIDTH_OUT]  <= knee_point_xlut[i-1][PIXEL_BIT_WIDTH_OUT-1:0] + ((pipe_tdata[i-1][2*PIXEL_BIT_WIDTH_OUT-1:PIXEL_BIT_WIDTH_OUT] - knee_point_ylut[i-1][PIXEL_BIT_WIDTH_OUT-1:0]) << knee_point_flut[i]);
                pipe_conversion_done[i][1] <= 1'b1;
              end
            end else begin
              // last step saturation logic
              // saturation logic in case the data is above the highest LUT value
              if ((pipe_conversion_done[i-1][0] == 1'b0)) begin
                pipe_tdata[i][PIXEL_BIT_WIDTH_OUT-1:0] <= {PIXEL_BIT_WIDTH_OUT{1'b1}};
              end
              if ((pipe_conversion_done[i-1][1] == 1'b0)) begin
                pipe_tdata[i][2*PIXEL_BIT_WIDTH_OUT-1:PIXEL_BIT_WIDTH_OUT] <= {PIXEL_BIT_WIDTH_OUT{1'b1}};
              end
            end
          end

          if (rstn == 1'b0) begin
            pipe_tvalid[i]   <= '0;
          end
        end

      end else if (PIXEL_PER_CYCLE == 4) begin
        // pipeline stage
        always_ff @ (posedge clk) begin
          if (pipe_tready[i] == 1'b1) begin

            // register everything
            pipe_tvalid[i]          <= pipe_tvalid[i-1];
            pipe_tlast[i]           <= pipe_tlast[i-1];
            pipe_tuser[i]           <= pipe_tuser[i-1];
            pipe_tdata[i]           <= pipe_tdata[i-1];
            pipe_conversion_done[i] <= pipe_conversion_done[i-1];

            if (i < NUM_KNEE_POINTS) begin
              // update data if it is below the knee point
              if ((pipe_conversion_done[i-1][0] == 1'b0) && (pipe_tdata[i-1][PIXEL_BIT_WIDTH_OUT-1:0] < knee_point_ylut[i][PIXEL_BIT_WIDTH_OUT-1:0])) begin
                pipe_tdata[i][PIXEL_BIT_WIDTH_OUT-1:0]  <= knee_point_xlut[i-1][PIXEL_BIT_WIDTH_OUT-1:0] + ((pipe_tdata[i-1][PIXEL_BIT_WIDTH_OUT-1:0] - knee_point_ylut[i-1][PIXEL_BIT_WIDTH_OUT-1:0]) << knee_point_flut[i]);
                pipe_conversion_done[i][0] <= 1'b1;
              end
              if ((pipe_conversion_done[i-1][1] == 1'b0) && (pipe_tdata[i-1][2*PIXEL_BIT_WIDTH_OUT-1:PIXEL_BIT_WIDTH_OUT] < knee_point_ylut[i][PIXEL_BIT_WIDTH_OUT-1:0])) begin
                pipe_tdata[i][2*PIXEL_BIT_WIDTH_OUT-1:PIXEL_BIT_WIDTH_OUT]  <= knee_point_xlut[i-1][PIXEL_BIT_WIDTH_OUT-1:0] + ((pipe_tdata[i-1][2*PIXEL_BIT_WIDTH_OUT-1:PIXEL_BIT_WIDTH_OUT] - knee_point_ylut[i-1][PIXEL_BIT_WIDTH_OUT-1:0]) << knee_point_flut[i]);
                pipe_conversion_done[i][1] <= 1'b1;
              end
              if ((pipe_conversion_done[i-1][2] == 1'b0) && (pipe_tdata[i-1][3*PIXEL_BIT_WIDTH_OUT-1:2*PIXEL_BIT_WIDTH_OUT] < knee_point_ylut[i][PIXEL_BIT_WIDTH_OUT-1:0])) begin
                pipe_tdata[i][3*PIXEL_BIT_WIDTH_OUT-1:2*PIXEL_BIT_WIDTH_OUT]  <= knee_point_xlut[i-1][PIXEL_BIT_WIDTH_OUT-1:0] + ((pipe_tdata[i-1][3*PIXEL_BIT_WIDTH_OUT-1:2*PIXEL_BIT_WIDTH_OUT] - knee_point_ylut[i-1][PIXEL_BIT_WIDTH_OUT-1:0]) << knee_point_flut[i]);
                pipe_conversion_done[i][2] <= 1'b1;
              end
              if ((pipe_conversion_done[i-1][3] == 1'b0) && (pipe_tdata[i-1][4*PIXEL_BIT_WIDTH_OUT-1:3*PIXEL_BIT_WIDTH_OUT] < knee_point_ylut[i][PIXEL_BIT_WIDTH_OUT-1:0])) begin
                pipe_tdata[i][4*PIXEL_BIT_WIDTH_OUT-1:3*PIXEL_BIT_WIDTH_OUT]  <= knee_point_xlut[i-1][PIXEL_BIT_WIDTH_OUT-1:0] + ((pipe_tdata[i-1][4*PIXEL_BIT_WIDTH_OUT-1:3*PIXEL_BIT_WIDTH_OUT] - knee_point_ylut[i-1][PIXEL_BIT_WIDTH_OUT-1:0]) << knee_point_flut[i]);
                pipe_conversion_done[i][3] <= 1'b1;
              end
            end else begin
              // last step saturation logic
              // saturation logic in case the data is above the highest LUT value
              if ((pipe_conversion_done[i-1][0] == 1'b0)) begin
                pipe_tdata[i][PIXEL_BIT_WIDTH_OUT-1:0] <= {PIXEL_BIT_WIDTH_OUT{1'b1}};
              end
              if ((pipe_conversion_done[i-1][1] == 1'b0)) begin
                pipe_tdata[i][2*PIXEL_BIT_WIDTH_OUT-1:PIXEL_BIT_WIDTH_OUT] <= {PIXEL_BIT_WIDTH_OUT{1'b1}};
              end
              if ((pipe_conversion_done[i-1][2] == 1'b0)) begin
                pipe_tdata[i][3*PIXEL_BIT_WIDTH_OUT-1:2*PIXEL_BIT_WIDTH_OUT] <= {PIXEL_BIT_WIDTH_OUT{1'b1}};
              end
              if ((pipe_conversion_done[i-1][3] == 1'b0)) begin
                pipe_tdata[i][4*PIXEL_BIT_WIDTH_OUT-1:3*PIXEL_BIT_WIDTH_OUT] <= {PIXEL_BIT_WIDTH_OUT{1'b1}};
              end
            end
          end

          if (rstn == 1'b0) begin
            pipe_tvalid[i]   <= '0;
          end
        end
      end
    end
  endgenerate

  // assign outputs
  assign pipe_tready[NUM_KNEE_POINTS]   = m_axis_tready;
  assign m_axis_tdata                   = pipe_tdata[NUM_KNEE_POINTS];
  assign m_axis_tvalid                  = pipe_tvalid[NUM_KNEE_POINTS];
  assign m_axis_tlast                   = pipe_tlast[NUM_KNEE_POINTS];
  assign m_axis_tuser                   = pipe_tuser[NUM_KNEE_POINTS];

endmodule
