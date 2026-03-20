// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module simple_dual_ported_rom
  #(
    parameter DATA_WIDTH  = 16,
    parameter ADDR_WIDTH  = 10,
    parameter MEM_FILE    = "../../rtl/simple_dual_ported_rom.mem"
  )
  (
    input  wire                     clk,

    input  wire                     r_ena,
    input  wire [ADDR_WIDTH-1:0]    r_addra,
    output wire [DATA_WIDTH-1:0]    r_dataa,

    input  wire                     r_enb,
    input  wire [ADDR_WIDTH-1:0]    r_addrb,
    output wire [DATA_WIDTH-1:0]    r_datab
  );

  reg [DATA_WIDTH-1:0] rom [(2**ADDR_WIDTH)-1:0];
  reg [DATA_WIDTH-1:0] r_data_int_a;
  reg [DATA_WIDTH-1:0] r_data_int_b;

  initial begin
    $readmemh(MEM_FILE, rom);
  end

  always_ff @(posedge clk)
  begin
    if (r_ena == 1'b1) begin
      r_data_int_a <= rom[r_addra];
    end
  end

  always_ff @(posedge clk)
  begin
    if (r_enb == 1'b1) begin
      r_data_int_b <= rom[r_addrb];
    end
  end

  assign r_dataa = r_data_int_a;
  assign r_datab = r_data_int_b;

endmodule
