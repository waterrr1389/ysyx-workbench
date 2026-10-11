// Checks the Arbiter on all three AXI4-Lite ports: as a slave towards the IFU
// and the LSU (faxil_slave), and as a master towards the SRAM (faxil_master).
// It also proves the contract sram_axil assumes: the SRAM never sees a read
// and a write at the same time.
module arbiter_axil (
  input        clk,
  input        reset,

  input        ifu_arvalid,
  input [31:0] ifu_araddr,
  input        ifu_rready,

  input        lsu_arvalid,
  input [31:0] lsu_araddr,
  input        lsu_rready,
  input        lsu_awvalid,
  input [31:0] lsu_awaddr,
  input        lsu_wvalid,
  input [31:0] lsu_wdata,
  input [3:0]  lsu_wstrb,
  input        lsu_bready,

  input        s_arready,
  input        s_rvalid,
  input [31:0] s_rdata,
  input [1:0]  s_rresp,
  input        s_awready,
  input        s_wready,
  input        s_bvalid,
  input [1:0]  s_bresp
);
  wire        ifu_arready, ifu_rvalid;
  wire [31:0] ifu_rdata;
  wire [1:0]  ifu_rresp;
  wire        lsu_arready, lsu_rvalid, lsu_awready, lsu_wready, lsu_bvalid;
  wire [31:0] lsu_rdata;
  wire [1:0]  lsu_rresp, lsu_bresp;
  wire        s_arvalid, s_rready, s_awvalid, s_wvalid, s_bready;
  wire [31:0] s_araddr, s_awaddr, s_wdata;
  wire [3:0]  s_wstrb;

  wire [1:0] f_state;

  Arbiter dut (
    .f_state(f_state),
    .clk(clk), .reset(reset),
    .ifu_arvalid(ifu_arvalid), .ifu_arready(ifu_arready), .ifu_araddr(ifu_araddr),
    .ifu_rvalid(ifu_rvalid), .ifu_rready(ifu_rready), .ifu_rdata(ifu_rdata), .ifu_rresp(ifu_rresp),
    .lsu_arvalid(lsu_arvalid), .lsu_arready(lsu_arready), .lsu_araddr(lsu_araddr),
    .lsu_rvalid(lsu_rvalid), .lsu_rready(lsu_rready), .lsu_rdata(lsu_rdata), .lsu_rresp(lsu_rresp),
    .lsu_awvalid(lsu_awvalid), .lsu_awready(lsu_awready), .lsu_awaddr(lsu_awaddr),
    .lsu_wvalid(lsu_wvalid), .lsu_wready(lsu_wready), .lsu_wdata(lsu_wdata), .lsu_wstrb(lsu_wstrb),
    .lsu_bvalid(lsu_bvalid), .lsu_bready(lsu_bready), .lsu_bresp(lsu_bresp),
    .s_arvalid(s_arvalid), .s_arready(s_arready), .s_araddr(s_araddr),
    .s_rvalid(s_rvalid), .s_rready(s_rready), .s_rdata(s_rdata), .s_rresp(s_rresp),
    .s_awvalid(s_awvalid), .s_awready(s_awready), .s_awaddr(s_awaddr),
    .s_wvalid(s_wvalid), .s_wready(s_wready), .s_wdata(s_wdata), .s_wstrb(s_wstrb),
    .s_bvalid(s_bvalid), .s_bready(s_bready), .s_bresp(s_bresp)
  );

  wire [3:0] f_ifu_rd, f_ifu_wr, f_ifu_awr;
  wire [3:0] f_lsu_rd, f_lsu_wr, f_lsu_awr;
  wire [3:0] f_s_rd, f_s_wr, f_s_awr;

  // F_OPT_ASYNC_RESET on every port: the Arbiter drops its routed VALIDs in
  // the reset cycle itself, and the IFU and LSU do the same upstream, as AXI
  // requires during reset. The synchronous checks would treat that drop as a
  // VALID withdrawn before its handshake.
  //
  // Upstream latency bounds are off: a master may wait behind the other one
  // for as long as the SRAM and that master take.
  faxil_slave #(
    .C_AXI_DATA_WIDTH(32),
    .C_AXI_ADDR_WIDTH(32),
    .F_OPT_READ_ONLY(1'b1),
    .F_AXI_MAXWAIT(0),
    .F_AXI_MAXDELAY(0),
    .F_OPT_ASYNC_RESET(1'b1),
    .F_OPT_INITIAL(1'b0)
  ) ifu_port (
    .i_clk(clk), .i_axi_reset_n(!reset),
    .i_axi_awvalid(1'b0), .i_axi_awready(1'b0),
    .i_axi_awaddr(32'b0), .i_axi_awprot(3'b0),
    .i_axi_wvalid(1'b0), .i_axi_wready(1'b0),
    .i_axi_wdata(32'b0), .i_axi_wstrb(4'b0),
    .i_axi_bvalid(1'b0), .i_axi_bready(1'b0), .i_axi_bresp(2'b0),
    .i_axi_arvalid(ifu_arvalid), .i_axi_arready(ifu_arready),
    .i_axi_araddr(ifu_araddr), .i_axi_arprot(3'b0),
    .i_axi_rvalid(ifu_rvalid), .i_axi_rready(ifu_rready),
    .i_axi_rdata(ifu_rdata), .i_axi_rresp(ifu_rresp),
    .f_axi_rd_outstanding(f_ifu_rd),
    .f_axi_wr_outstanding(f_ifu_wr),
    .f_axi_awr_outstanding(f_ifu_awr)
  );

  faxil_slave #(
    .C_AXI_DATA_WIDTH(32),
    .C_AXI_ADDR_WIDTH(32),
    .F_AXI_MAXWAIT(0),
    .F_AXI_MAXDELAY(0),
    .F_OPT_ASYNC_RESET(1'b1),
    .F_OPT_INITIAL(1'b0)
  ) lsu_port (
    .i_clk(clk), .i_axi_reset_n(!reset),
    .i_axi_awvalid(lsu_awvalid), .i_axi_awready(lsu_awready),
    .i_axi_awaddr(lsu_awaddr), .i_axi_awprot(3'b0),
    .i_axi_wvalid(lsu_wvalid), .i_axi_wready(lsu_wready),
    .i_axi_wdata(lsu_wdata), .i_axi_wstrb(lsu_wstrb),
    .i_axi_bvalid(lsu_bvalid), .i_axi_bready(lsu_bready), .i_axi_bresp(lsu_bresp),
    .i_axi_arvalid(lsu_arvalid), .i_axi_arready(lsu_arready),
    .i_axi_araddr(lsu_araddr), .i_axi_arprot(3'b0),
    .i_axi_rvalid(lsu_rvalid), .i_axi_rready(lsu_rready),
    .i_axi_rdata(lsu_rdata), .i_axi_rresp(lsu_rresp),
    .f_axi_rd_outstanding(f_lsu_rd),
    .f_axi_wr_outstanding(f_lsu_wr),
    .f_axi_awr_outstanding(f_lsu_awr)
  );

  faxil_master #(
    .C_AXI_DATA_WIDTH(32),
    .C_AXI_ADDR_WIDTH(32),
    .F_OPT_ASSUME_RESET(1'b1),
    .F_OPT_ASYNC_RESET(1'b1),
    .F_OPT_INITIAL(1'b0)
  ) sram_port (
    .i_clk(clk), .i_axi_reset_n(!reset),
    .i_axi_awvalid(s_awvalid), .i_axi_awready(s_awready),
    .i_axi_awaddr(s_awaddr), .i_axi_awprot(3'b0),
    .i_axi_wvalid(s_wvalid), .i_axi_wready(s_wready),
    .i_axi_wdata(s_wdata), .i_axi_wstrb(s_wstrb),
    .i_axi_bvalid(s_bvalid), .i_axi_bready(s_bready), .i_axi_bresp(s_bresp),
    .i_axi_arvalid(s_arvalid), .i_axi_arready(s_arready),
    .i_axi_araddr(s_araddr), .i_axi_arprot(3'b0),
    .i_axi_rvalid(s_rvalid), .i_axi_rready(s_rready),
    .i_axi_rdata(s_rdata), .i_axi_rresp(s_rresp),
    .f_axi_rd_outstanding(f_s_rd),
    .f_axi_wr_outstanding(f_s_wr),
    .f_axi_awr_outstanding(f_s_awr)
  );

  // Upstream contract, proven by ifu_axil and lsu_axil: a master issues
  // nothing new until its previous transaction has completed. The Arbiter
  // relies on it: while routed to a master it forwards that master's
  // requests, and it returns to IDLE on the response handshake, so a request
  // issued in that same cycle would be left outstanding and untracked.
  always @(*) if (!reset) begin
    if (f_ifu_rd != 0) assume(!ifu_arvalid);
    if (f_lsu_rd != 0) assume(!lsu_arvalid && !lsu_awvalid && !lsu_wvalid);
    if (f_lsu_awr != 0) assume(!lsu_arvalid && !lsu_awvalid);
    if (f_lsu_wr != 0)  assume(!lsu_arvalid && !lsu_wvalid);
  end

  // The contract xbar_axil assumes of its master, stated here over the same
  // counters: one transaction at a time, nothing new until it completes.
  always @(*) if (!reset) begin
    assert(!(s_arvalid && (s_awvalid || s_wvalid)));
    if (f_s_rd != 0) assert(!s_arvalid && !s_awvalid && !s_wvalid);
    if (f_s_awr != 0) assert(!s_arvalid && !s_awvalid);
    if (f_s_wr != 0)  assert(!s_arvalid && !s_wvalid);
  end

  // Every transaction the SRAM sees belongs to exactly one master, and only
  // one transaction is in flight at a time.
  wire f_ifu_busy = f_ifu_rd != 0;
  wire f_lsu_busy = f_lsu_rd != 0 || f_lsu_awr != 0 || f_lsu_wr != 0;

  always @(*) if (!reset) begin
    assert(f_ifu_rd <= 1 && f_lsu_rd <= 1 && f_lsu_awr <= 1 && f_lsu_wr <= 1);
    assert(!(f_ifu_busy && f_lsu_busy));
    assert(!(f_lsu_rd != 0 && (f_lsu_awr != 0 || f_lsu_wr != 0)));

    // The route stays locked to the master whose transaction is in flight.
    // f_state is exported from the converted copy by the Makefile.
    if (f_ifu_busy) assert(f_state == 2'd1);
    if (f_lsu_rd != 0) assert(f_state == 2'd2);
    if (f_lsu_awr != 0 || f_lsu_wr != 0) assert(f_state == 2'd3);
    assert(f_s_rd  == f_ifu_rd + f_lsu_rd);
    assert(f_s_awr == f_lsu_awr);
    assert(f_s_wr  == f_lsu_wr);
  end

  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;

  always @(*) if (f_past_valid && !reset) begin
    cover(ifu_rvalid && ifu_rready);
    cover(lsu_rvalid && lsu_rready);
    cover(lsu_bvalid && lsu_bready);
  end
endmodule
