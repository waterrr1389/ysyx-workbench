// Checks the write-only UART slave against the AXI4-Lite rules in faxil_slave.
// Every top-level input is a free variable, so the master side may do
// anything the AXI rules and the Xbar contract below allow.
module uart_axil (
  input        clk,
  input        reset,
  input        arvalid,
  input [31:0] araddr,
  input        rready,
  input        awvalid,
  input [31:0] awaddr,
  input        wvalid,
  input [31:0] wdata,
  input [3:0]  wstrb,
  input        bready
);
  wire        arready, rvalid, awready, wready, bvalid;
  wire [31:0] rdata;
  wire [1:0]  rresp, bresp;

  UART #(32) dut (
    .clk(clk), .reset(reset),
    .arvalid(arvalid), .arready(arready), .araddr(araddr),
    .rvalid(rvalid), .rready(rready), .rdata(rdata), .rresp(rresp),
    .awvalid(awvalid), .awready(awready), .awaddr(awaddr),
    .wvalid(wvalid), .wready(wready), .wdata(wdata), .wstrb(wstrb),
    .bvalid(bvalid), .bready(bready), .bresp(bresp)
  );

  wire [3:0] f_rd_outstanding, f_wr_outstanding, f_awr_outstanding;

  // F_OPT_WRITE_ONLY is the Xbar contract: reads to the UART range are
  // answered with DECERR by the Xbar and never reach this slave.
  // F_OPT_ASYNC_RESET matches the UART gating BVALID with reset in the same
  // cycle, as AXI requires during reset; the synchronous checks would flag
  // that drop as a VALID withdrawn before its handshake.
  faxil_slave #(
    .C_AXI_DATA_WIDTH(32),
    .C_AXI_ADDR_WIDTH(32),
    .F_OPT_WRITE_ONLY(1'b1),
    .F_OPT_ASYNC_RESET(1'b1),
    .F_OPT_INITIAL(1'b0)
  ) faxil (
    .i_clk(clk), .i_axi_reset_n(!reset),
    .i_axi_awvalid(awvalid), .i_axi_awready(awready),
    .i_axi_awaddr(awaddr), .i_axi_awprot(3'b0),
    .i_axi_wvalid(wvalid), .i_axi_wready(wready),
    .i_axi_wdata(wdata), .i_axi_wstrb(wstrb),
    .i_axi_bvalid(bvalid), .i_axi_bready(bready), .i_axi_bresp(bresp),
    .i_axi_arvalid(arvalid), .i_axi_arready(arready),
    .i_axi_araddr(araddr), .i_axi_arprot(3'b0),
    .i_axi_rvalid(rvalid), .i_axi_rready(rready),
    .i_axi_rdata(rdata), .i_axi_rresp(rresp),
    .f_axi_rd_outstanding(f_rd_outstanding),
    .f_axi_wr_outstanding(f_wr_outstanding),
    .f_axi_awr_outstanding(f_awr_outstanding)
  );

  // Induction invariant: a write is outstanding exactly while BVALID is up,
  // and AW and W are always taken together.
  always @(*) if (!reset) begin
    assert(f_awr_outstanding == {3'b0, bvalid});
    assert(f_wr_outstanding  == {3'b0, bvalid});
  end

  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;

  always @(*) if (f_past_valid && !reset) cover(bvalid && bready);
endmodule
