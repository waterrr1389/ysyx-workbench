// Checks the SRAM slave against the AXI4-Lite rules in faxil_slave.
// Every top-level input is a free variable, so the master side may do
// anything the AXI rules and the Arbiter contract below allow.
module sram_axil (
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

  SRAM #(32) dut (
    .clk(clk), .reset(reset),
    .arvalid(arvalid), .arready(arready), .araddr(araddr),
    .rvalid(rvalid), .rready(rready), .rdata(rdata), .rresp(rresp),
    .awvalid(awvalid), .awready(awready), .awaddr(awaddr),
    .wvalid(wvalid), .wready(wready), .wdata(wdata), .wstrb(wstrb),
    .bvalid(bvalid), .bready(bready), .bresp(bresp)
  );

  wire [3:0] f_rd_outstanding, f_wr_outstanding, f_awr_outstanding;

  // F_OPT_INITIAL is off: SRAM registers have no initial values and are
  // only defined after reset, which faxil_slave assumes on the first cycle.
  faxil_slave #(
    .C_AXI_DATA_WIDTH(32),
    .C_AXI_ADDR_WIDTH(32),
    .F_LGDEPTH(4),
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

  // Arbiter contract: the SRAM sees one transaction at a time, and a read
  // never overlaps a write. Without this, a read and a write offered in the
  // same IDLE cycle are both accepted but only the read is answered.
  always @(*) if (!reset) begin
    assume(!(arvalid && (awvalid || wvalid)));
    if (f_awr_outstanding != 0 || f_wr_outstanding != 0) assume(!arvalid);
    if (f_rd_outstanding != 0) assume(!awvalid && !wvalid);
  end

  // Induction invariants: tie the slave's visible state to the transactions
  // faxil_slave has counted, so prove mode cannot start from an unreachable
  // state. Each SRAM state drives a distinct ready/valid pattern, so the
  // ports identify it without reaching into the design.
  wire [4:0] f_ports  = {arready, awready, wready, rvalid, bvalid};
  wire [11:0] f_counts = {f_rd_outstanding, f_awr_outstanding, f_wr_outstanding};

  always @(*) if (!reset) begin
    case (f_ports)
      5'b111_00: assert(f_counts == 12'h000);  // idle
      5'b001_00: assert(f_counts == 12'h010);  // address taken, wait for data
      5'b010_00: assert(f_counts == 12'h001);  // data taken, wait for address
      5'b000_10: assert(f_counts == 12'h100);  // read response
      5'b000_01: assert(f_counts == 12'h011);  // write response
      default:   assert(1'b0);
    endcase
  end

  // Reachability after reset. faxil_slave's own covers are not gated by
  // reset and can be met by the arbitrary pre-reset state alone.
  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;

  always @(*) if (f_past_valid && !reset) begin
    cover(rvalid && rready);
    cover(bvalid && bready);
    cover(f_ports == 5'b001_00);  // write address before data
    cover(f_ports == 5'b010_00);  // write data before address
  end
endmodule
