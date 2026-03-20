// SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
// SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

// SPDX-License-Identifier: MIT

module axi_lite_register
  #(
    parameter S_AXI_DATA_WIDTH            = 32,
    parameter S_AXI_ADDR_WIDTH            = 5,
    parameter S_AXI_WSTRB_WIDTH           = $rtoi($floor((S_AXI_DATA_WIDTH + 7)/8)),
    parameter S_AXI_RRESP_WIDTH           = 2,
    parameter S_AXI_BRESP_WIDTH           = 2
  )
  (
    input  wire                           clk,
    input  wire                           rstn,

    input  wire [S_AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire                           s_axi_awvalid,
    output wire                           s_axi_awready,
    input  wire [S_AXI_DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [S_AXI_WSTRB_WIDTH-1:0]   s_axi_wstrb,
    input  wire                           s_axi_wvalid,
    output wire                           s_axi_wready,
    output wire [S_AXI_BRESP_WIDTH-1:0]   s_axi_bresp,
    output wire                           s_axi_bvalid,
    input  wire                           s_axi_bready,
    input  wire [S_AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire                           s_axi_arvalid,
    output wire                           s_axi_arready,
    output wire [S_AXI_DATA_WIDTH-1:0]    s_axi_rdata,
    output wire [S_AXI_RRESP_WIDTH-1:0]   s_axi_rresp,
    output wire                           s_axi_rvalid,
    input  wire                           s_axi_rready,

    output wire [15:0]                    black_level,

    // format: UQ9.7
    output wire [15:0]                    rgain,
    output wire [15:0]                    bgain,
    output wire [15:0]                    g0gain,
    output wire [15:0]                    g1gain,

    // format: Q3.12
    output wire [15:0]                    ccm_r_r,
    output wire [15:0]                    ccm_r_g,
    output wire [15:0]                    ccm_r_b,
    output wire [15:0]                    ccm_g_r,
    output wire [15:0]                    ccm_g_g,
    output wire [15:0]                    ccm_g_b,
    output wire [15:0]                    ccm_b_r,
    output wire [15:0]                    ccm_b_g,
    output wire [15:0]                    ccm_b_b

  );

  localparam   NUM_REGISTERS      = 2**(S_AXI_ADDR_WIDTH-2);

  localparam   WR_IDLE            = 2'b00;
  localparam   WR_DATA            = 2'b01;
  localparam   WR_BREADY          = 2'b10;

  // state for address write channel
  reg [1:0]                       wr_state = WR_IDLE;

  // write signals
  reg                             axi_wren;
  reg [S_AXI_DATA_WIDTH-1:0]      axi_wdata;
  reg [S_AXI_WSTRB_WIDTH-1:0]     axi_wstrb;
  reg                             axi_wready;
  reg [S_AXI_ADDR_WIDTH-3:0]      axi_awaddr;
  reg                             axi_awready;
  reg                             axi_bvalid;

  localparam   RD_IDLE            = 1'b0;
  localparam   RD_DATA            = 1'b1;

  // state for read channel
  reg [0:0]                       rd_state = RD_IDLE;

  // read signals
  reg                             axi_rden;
  reg [S_AXI_ADDR_WIDTH-3:0]      axi_araddr;
  reg                             axi_arready;
  reg [S_AXI_DATA_WIDTH-1:0]      axi_rdata;
  reg                             axi_rvalid;

  // registers
  reg [S_AXI_DATA_WIDTH-1:0]      registers [0:NUM_REGISTERS-1];


  // write state machine
  always_ff @ (posedge clk) begin
    case(wr_state)

      WR_IDLE: begin
        axi_wren      <= 'b0;
        axi_wdata     <= 'b0;
        axi_wstrb     <= 'b0;
        axi_wready    <= 'b0;
        axi_awaddr    <= 'b0;
        axi_awready   <= 'b0;
        axi_bvalid    <= 'b0;

        if ((s_axi_awvalid == 1'b1) && (s_axi_wvalid == 1'b1)) begin
          axi_awready <= 1'b1;
          axi_wready  <= 1'b1;
          wr_state    <= WR_DATA;
        end
      end

      WR_DATA: begin
        axi_wdata     <= s_axi_wdata;
        axi_wstrb     <= s_axi_wstrb;
        axi_awaddr    <= s_axi_awaddr[S_AXI_ADDR_WIDTH-1:2];
        axi_wren      <= 1'b1;
        axi_bvalid    <= 1'b1;
        axi_awready   <= 1'b0;
        axi_wready    <= 1'b0;

        wr_state      <= WR_BREADY;
      end

      WR_BREADY: begin
        axi_wren      <= 1'b0;

        if (s_axi_bready == 1'b1) begin
          axi_bvalid  <= 'b0;

          wr_state    <= WR_IDLE;
        end
      end

      default: begin
        wr_state <= WR_IDLE;
      end
    endcase

    if (rstn == 1'b0) begin
      wr_state <= WR_IDLE;

      axi_wren      <= 'b0;
      axi_wdata     <= 'b0;
      axi_wstrb     <= 'b0;
      axi_wready    <= 'b0;
      axi_awaddr    <= 'b0;
      axi_awready   <= 'b0;
      axi_bvalid    <= 'b0;

    end
  end

  // read state machine
  always_ff @ (posedge clk) begin
    axi_araddr  <= s_axi_araddr[S_AXI_ADDR_WIDTH-1:2];

    case (rd_state)

      RD_IDLE: begin
        axi_rden    <= 1'b0;
        axi_arready <= 1'b1;
        axi_rvalid  <= 1'b0;

        if ((s_axi_arvalid == 1'b1) && (axi_arready == 1'b1)) begin
          axi_rden    <= 1'b1;
          axi_arready <= 1'b0;
          axi_rvalid  <= 1'b0;
          rd_state    <= RD_DATA;
        end
      end

      RD_DATA: begin
        axi_rden    <= 1'b0;
        axi_arready <= 1'b0;
        axi_rvalid  <= 1'b1;

        if ((axi_rvalid == 1'b1) && (s_axi_rready == 1'b1)) begin
          axi_rden    <= 1'b0;
          axi_arready <= 1'b1;
          axi_rvalid  <= 1'b0;
          rd_state    <= RD_IDLE;
        end
      end

      default: begin
        rd_state <= RD_IDLE;
      end
    endcase

    if (rstn == 1'b0) begin
      rd_state <= RD_IDLE;

      axi_rden    <= 'b0;
      axi_arready <= 'b0;
      axi_rvalid  <= 'b0;
      axi_araddr  <= 'b0;
    end
  end

  // register process
  always_ff @ (posedge clk) begin
    if (axi_wren == 1'b1) begin
        if (axi_wstrb[0] == 1'b1) begin
          registers[axi_awaddr][7:0] <= axi_wdata[7:0];
        end
        if (axi_wstrb[1] == 1'b1) begin
          registers[axi_awaddr][15:8] <= axi_wdata[15:8];
        end
        if (axi_wstrb[2] == 1'b1) begin
          registers[axi_awaddr][23:16] <= axi_wdata[23:16];
        end
        if (axi_wstrb[3] == 1'b1) begin
          registers[axi_awaddr][31:24] <= axi_wdata[31:24];
        end
    end

    if (axi_rden == 1'b1) begin
      axi_rdata <= registers[axi_araddr];
    end

    if (rstn == 1'b0) begin
      // bgain, rgain
      registers[0] <= 32'h00800080;
      // g1gain, g0gain
      registers[1] <= 32'h00800080;
      // ccm_r_g, ccm_r_r
      registers[2] <= 32'h00001000;
      // ccm_g_r, ccm_r_b
      registers[3] <= 32'h00000000;
      // ccm_g_b, ccm_g_g
      registers[4] <= 32'h00001000;
      // ccm_b_g, ccm_b_r
      registers[5] <= 32'h00000000;
      // black level, ccm_b_b
      registers[6] <= 32'h01001000;
    end
  end

  // register assignments
  assign rgain       = registers[0][15:0];
  assign bgain       = registers[0][31:16];
  assign g0gain      = registers[1][15:0];
  assign g1gain      = registers[1][31:16];
  assign ccm_r_r     = registers[2][15:0];
  assign ccm_r_g     = registers[2][31:16];
  assign ccm_r_b     = registers[3][15:0];
  assign ccm_g_r     = registers[3][31:16];
  assign ccm_g_g     = registers[4][15:0];
  assign ccm_g_b     = registers[4][31:16];
  assign ccm_b_r     = registers[5][15:0];
  assign ccm_b_g     = registers[5][31:16];
  assign ccm_b_b     = registers[6][15:0];
  assign black_level = registers[6][31:16];

  // output assignments
  assign s_axi_rdata    = axi_rdata;
  assign s_axi_rvalid   = axi_rvalid;
  assign s_axi_arready  = axi_arready;
  assign s_axi_wready   = axi_wready;
  assign s_axi_awready  = axi_awready;
  assign s_axi_bvalid   = axi_bvalid;

  // no other response ever
  assign s_axi_bresp = 2'b00;
  assign s_axi_rresp = 2'b00;

endmodule
