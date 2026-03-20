// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module prng
  #(
    // Output pixel bitwidth
    parameter PIXEL_BIT_WIDTH             = 8
  )
  (
    input  wire                           clk,
    input  wire                           rstn,

    output wire  [PIXEL_BIT_WIDTH-1:0]    random_out
  );

  assign random_out = 'b0;

endmodule
