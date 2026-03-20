// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module non_restoring_unsigned_divider
  #(
    parameter int NOM_DATA_WIDTH        = 48,
    parameter int DEN_DATA_WIDTH        = 24
  )
  (
    input  wire                         clk,
    input  wire                         rstn,

    input  wire  [NOM_DATA_WIDTH-1:0]   nom,
    input  wire  [DEN_DATA_WIDTH-1:0]   den,
    input  wire                         start,

    output wire  [NOM_DATA_WIDTH-1:0]   div,
    output wire  [DEN_DATA_WIDTH-1:0]   rem,
    output wire                         done
  );

  localparam int CYCLE_COUNT            = NOM_DATA_WIDTH - 1;
  localparam int CYCLE_COUNT_WIDTH      = $clog2(NOM_DATA_WIDTH);

  reg [CYCLE_COUNT_WIDTH-1:0]           cycle_count;
  reg [DEN_DATA_WIDTH-1:0]              den_int;
  reg [NOM_DATA_WIDTH-1:0]              div_int;
  reg [DEN_DATA_WIDTH-1:0]              rem_int;
  reg [DEN_DATA_WIDTH:0]                sub_int;
  reg                                   running = 1'b0;
  reg                                   done_out;

  // subtractor with guard bit
  always_comb begin
    sub_int = {rem_int[DEN_DATA_WIDTH-2:0], div_int[NOM_DATA_WIDTH-1]} - den_int;
  end

  always_ff @ (posedge clk) begin
    done_out <= 1'b0;

    if (start == 1'b1) begin
        div_int     <= nom;
        den_int     <= den;
        rem_int     <= 'b0;
        cycle_count <= CYCLE_COUNT[CYCLE_COUNT_WIDTH-1:0];
        running     <= 1'b1;

    end else if (running == 1'b1) begin

      // actual shift register / divide iteration
      if (sub_int[DEN_DATA_WIDTH] == 1'b0) begin
        rem_int <= sub_int[DEN_DATA_WIDTH-1:0];
        div_int <= {div_int[NOM_DATA_WIDTH-2:0], 1'b1};
      end else begin
        rem_int <= {rem_int[DEN_DATA_WIDTH-2:0], div_int[NOM_DATA_WIDTH-1]};
        div_int <= {div_int[NOM_DATA_WIDTH-2:0], 1'b0};
      end

      // are we done?
      if (cycle_count == 'b0) begin
        running   <= 1'b0;
        done_out  <= 1'b1;
      end

      // decrement cycle count
      cycle_count <= cycle_count - 1'b1;
    end

    if (rstn == 1'b0) begin
      done_out <= 1'b0;
      running  <= 1'b0;
    end
  end

  // assign outputs
  assign div    = div_int;
  assign rem    = rem_int;
  assign done   = done_out;

endmodule
