// Checks the Xbar on all three AXI4-Lite ports: as a slave towards the
// Arbiter (faxil_slave) and as a master towards the SRAM and the UART
// (faxil_master). It also proves the contracts sram_axil and uart_axil
// assume: the SRAM never sees a read and a write at once, and the UART
// never sees a read.
module xbar_axil (
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
  input        bready,

  input        sram_arready,
  input        sram_rvalid,
  input [31:0] sram_rdata,
  input [1:0]  sram_rresp,
  input        sram_awready,
  input        sram_wready,
  input        sram_bvalid,
  input [1:0]  sram_bresp,

  input        uart_awready,
  input        uart_wready,
  input        uart_bvalid,
  input [1:0]  uart_bresp
);
  wire        arready, rvalid, awready, wready, bvalid;
  wire [31:0] rdata;
  wire [1:0]  rresp, bresp;
  wire        sram_arvalid, sram_rready, sram_awvalid, sram_wvalid, sram_bready;
  wire [31:0] sram_araddr, sram_awaddr, sram_wdata;
  wire [3:0]  sram_wstrb;
  wire        uart_arvalid, uart_rready, uart_awvalid, uart_wvalid, uart_bready;
  wire [31:0] uart_araddr, uart_awaddr, uart_wdata;
  wire [3:0]  uart_wstrb;
  wire [1:0]  f_state, f_route;
  wire        f_err_resp;

  Xbar dut (
    .f_state(f_state), .f_route(f_route), .f_err_resp(f_err_resp),
    .clk(clk), .reset(reset),
    .arvalid(arvalid), .arready(arready), .araddr(araddr),
    .rvalid(rvalid), .rready(rready), .rdata(rdata), .rresp(rresp),
    .awvalid(awvalid), .awready(awready), .awaddr(awaddr),
    .wvalid(wvalid), .wready(wready), .wdata(wdata), .wstrb(wstrb),
    .bvalid(bvalid), .bready(bready), .bresp(bresp),
    .sram_arvalid(sram_arvalid), .sram_arready(sram_arready), .sram_araddr(sram_araddr),
    .sram_rvalid(sram_rvalid), .sram_rready(sram_rready), .sram_rdata(sram_rdata),
    .sram_rresp(sram_rresp),
    .sram_awvalid(sram_awvalid), .sram_awready(sram_awready), .sram_awaddr(sram_awaddr),
    .sram_wvalid(sram_wvalid), .sram_wready(sram_wready), .sram_wdata(sram_wdata),
    .sram_wstrb(sram_wstrb),
    .sram_bvalid(sram_bvalid), .sram_bready(sram_bready), .sram_bresp(sram_bresp),
    .uart_arvalid(uart_arvalid), .uart_arready(1'b0), .uart_araddr(uart_araddr),
    .uart_rvalid(1'b0), .uart_rready(uart_rready), .uart_rdata(32'b0),
    .uart_rresp(2'b0),
    .uart_awvalid(uart_awvalid), .uart_awready(uart_awready), .uart_awaddr(uart_awaddr),
    .uart_wvalid(uart_wvalid), .uart_wready(uart_wready), .uart_wdata(uart_wdata),
    .uart_wstrb(uart_wstrb),
    .uart_bvalid(uart_bvalid), .uart_bready(uart_bready), .uart_bresp(uart_bresp)
  );

  wire [3:0] f_rd, f_wr, f_awr;
  wire [3:0] f_sram_rd, f_sram_wr, f_sram_awr;
  wire [3:0] f_uart_rd, f_uart_wr, f_uart_awr;

  // F_OPT_ASYNC_RESET on every port: the Xbar drops its routed VALIDs in the
  // reset cycle itself, as AXI requires during reset. The upstream bounds
  // catch a request that is never answered: IDLE adds one cycle of READY
  // wait to the slave's, and the response delay is the slave's own.
  faxil_slave #(
    .C_AXI_DATA_WIDTH(32),
    .C_AXI_ADDR_WIDTH(32),
    .F_AXI_MAXWAIT(13),
    .F_AXI_MAXDELAY(12),
    .F_OPT_ASYNC_RESET(1'b1),
    .F_OPT_INITIAL(1'b0)
  ) up_port (
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
    .f_axi_rd_outstanding(f_rd),
    .f_axi_wr_outstanding(f_wr),
    .f_axi_awr_outstanding(f_awr)
  );

  faxil_master #(
    .C_AXI_DATA_WIDTH(32),
    .C_AXI_ADDR_WIDTH(32),
    .F_OPT_ASSUME_RESET(1'b1),
    .F_OPT_ASYNC_RESET(1'b1),
    .F_OPT_INITIAL(1'b0)
  ) sram_port (
    .i_clk(clk), .i_axi_reset_n(!reset),
    .i_axi_awvalid(sram_awvalid), .i_axi_awready(sram_awready),
    .i_axi_awaddr(sram_awaddr), .i_axi_awprot(3'b0),
    .i_axi_wvalid(sram_wvalid), .i_axi_wready(sram_wready),
    .i_axi_wdata(sram_wdata), .i_axi_wstrb(sram_wstrb),
    .i_axi_bvalid(sram_bvalid), .i_axi_bready(sram_bready), .i_axi_bresp(sram_bresp),
    .i_axi_arvalid(sram_arvalid), .i_axi_arready(sram_arready),
    .i_axi_araddr(sram_araddr), .i_axi_arprot(3'b0),
    .i_axi_rvalid(sram_rvalid), .i_axi_rready(sram_rready),
    .i_axi_rdata(sram_rdata), .i_axi_rresp(sram_rresp),
    .f_axi_rd_outstanding(f_sram_rd),
    .f_axi_wr_outstanding(f_sram_wr),
    .f_axi_awr_outstanding(f_sram_awr)
  );

  // F_OPT_WRITE_ONLY asserts the UART never sees a read.
  faxil_master #(
    .C_AXI_DATA_WIDTH(32),
    .C_AXI_ADDR_WIDTH(32),
    .F_OPT_WRITE_ONLY(1'b1),
    .F_OPT_ASSUME_RESET(1'b1),
    .F_OPT_ASYNC_RESET(1'b1),
    .F_OPT_INITIAL(1'b0)
  ) uart_port (
    .i_clk(clk), .i_axi_reset_n(!reset),
    .i_axi_awvalid(uart_awvalid), .i_axi_awready(uart_awready),
    .i_axi_awaddr(uart_awaddr), .i_axi_awprot(3'b0),
    .i_axi_wvalid(uart_wvalid), .i_axi_wready(uart_wready),
    .i_axi_wdata(uart_wdata), .i_axi_wstrb(uart_wstrb),
    .i_axi_bvalid(uart_bvalid), .i_axi_bready(uart_bready), .i_axi_bresp(uart_bresp),
    .i_axi_arvalid(uart_arvalid), .i_axi_arready(1'b0),
    .i_axi_araddr(uart_araddr), .i_axi_arprot(3'b0),
    .i_axi_rvalid(1'b0), .i_axi_rready(uart_rready),
    .i_axi_rdata(32'b0), .i_axi_rresp(2'b0),
    .f_axi_rd_outstanding(f_uart_rd),
    .f_axi_wr_outstanding(f_uart_wr),
    .f_axi_awr_outstanding(f_uart_awr)
  );

  // Upstream contract, proven by arbiter_axil: one transaction at a time,
  // and nothing new is offered until the previous one has completed.
  wire f_busy = f_rd != 0 || f_awr != 0 || f_wr != 0;

  always @(*) if (!reset) begin
    assume(!(arvalid && (awvalid || wvalid)));
    if (f_rd != 0) assume(!arvalid && !awvalid && !wvalid);
    if (f_awr != 0) assume(!arvalid && !awvalid);
    if (f_wr != 0)  assume(!arvalid && !wvalid);
  end

  // The contract sram_axil assumes, over the SRAM port counters.
  always @(*) if (!reset) begin
    assert(!(sram_arvalid && (sram_awvalid || sram_wvalid)));
    if (f_sram_awr != 0 || f_sram_wr != 0) assert(!sram_arvalid);
    if (f_sram_rd != 0) assert(!sram_awvalid && !sram_wvalid);
  end

  // Address decoding: a request reaches a slave only inside its range.
  always @(*) if (!reset) begin
    if (sram_arvalid) assert(sram_araddr - 32'h8000_0000 < 32'h0200_0000);
    if (sram_awvalid) assert(sram_awaddr - 32'h8000_0000 < 32'h0200_0000);
    if (uart_awvalid) assert(uart_awaddr - 32'ha000_03f8 < 32'h0000_0008);
  end

  // Induction invariants: tie the latched route to the transaction counted
  // on each side. f_state, f_route and f_err_resp are exported from the
  // copy the Makefile adapts.
  localparam [1:0] XBAR_IDLE = 2'd0, XBAR_READ = 2'd1, XBAR_WRITE = 2'd2;
  localparam [1:0] ROUTE_SRAM = 2'd0, ROUTE_UART = 2'd1, ROUTE_ERR = 2'd2;

  wire [11:0] f_up   = {f_rd, f_awr, f_wr};
  wire [11:0] f_sram = {f_sram_rd, f_sram_awr, f_sram_wr};
  wire [11:0] f_uart = {f_uart_rd, f_uart_awr, f_uart_wr};

  always @(*) if (!reset) begin
    assert(f_state != 2'd3);
    // route is latched on leaving IDLE and meaningless before that.
    if (f_state != XBAR_IDLE) assert(f_route != 2'd3);
    assert(f_rd <= 1 && f_awr <= 1 && f_wr <= 1);
    // A request that moved the Xbar out of IDLE is either still offered or
    // already taken: the master cannot withdraw it.
    if (f_state == XBAR_READ) assert(f_rd == 1 || arvalid);
    if (f_state == XBAR_WRITE) begin
      assert(f_awr == 1 || awvalid);
      assert(f_wr == 1 || wvalid);
    end
    if (f_state == XBAR_IDLE) begin
      assert(!f_busy);
      assert(!f_err_resp);
    end
    if (f_state == XBAR_READ)  assert(f_route != ROUTE_UART && f_awr == 0 && f_wr == 0);
    if (f_state == XBAR_WRITE) assert(f_route != 2'd3 && f_rd == 0);
    if (f_state == XBAR_IDLE || f_route != ROUTE_SRAM) assert(f_sram == 12'h000);
    if (f_state == XBAR_IDLE || f_route != ROUTE_UART) assert(f_uart == 12'h000);
    if (f_state != XBAR_IDLE && f_route == ROUTE_SRAM) assert(f_sram == f_up);
    if (f_state != XBAR_IDLE && f_route == ROUTE_UART) assert(f_uart == f_up);
    if (f_state != XBAR_IDLE && f_route == ROUTE_ERR)
      assert(f_err_resp == (f_up != 12'h000));
  end

  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;

  always @(*) if (f_past_valid && !reset) begin
    cover(sram_rvalid && sram_rready);
    cover(sram_bvalid && sram_bready);
    cover(uart_bvalid && uart_bready);
    cover(rvalid && rready && rresp == 2'b11);
    cover(bvalid && bready && bresp == 2'b11);
  end
endmodule
