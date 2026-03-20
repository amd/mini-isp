// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module simple_dual_ported_ram
  #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 10
  )
  (
    input  wire                     clk,

    input  wire                     w_en,
    input  wire [ADDR_WIDTH-1:0]    w_addr,
    input  wire [DATA_WIDTH-1:0]    w_data,

    input  wire                     r_en,
    input  wire [ADDR_WIDTH-1:0]    r_addr,
    output wire [DATA_WIDTH-1:0]    r_data
  );

  reg [DATA_WIDTH-1:0] ram [(2**ADDR_WIDTH)-1:0];
  reg [DATA_WIDTH-1:0] r_data_int;

  always_ff @(posedge clk)
  begin
    if (r_en == 1'b1) begin
      r_data_int <= ram[r_addr];
    end
  end

  always_ff @(posedge clk)
  begin
    if (w_en == 1'b1) begin
      ram[w_addr] <= w_data;
    end
  end

  assign r_data = r_data_int;

endmodule
