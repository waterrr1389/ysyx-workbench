// Checks the IFU read master against the AXI4-Lite rules in faxil_master.
// Every top-level input is a free variable, so the slave side and the core
// may do anything the AXI rules allow.
module ifu_axil (
  input        clk,
  input        reset,
  input [31:0] pc,
  input        inst_done,
  input        arready,
  input        rvalid,
  input [31:0] rdata,
  input [1:0]  rresp
);
  wire        arvalid, rready, inst_valid;
  wire [31:0] araddr, inst;

  IFU #(32) dut (
    .clk(clk), .reset(reset),
    .pc(pc), .inst_done(inst_done), .inst(inst), .inst_valid(inst_valid),
    .arvalid(arvalid), .arready(arready), .araddr(araddr),
    .rvalid(rvalid), .rready(rready), .rdata(rdata), .rresp(rresp)
  );

  wire [3:0] f_rd_outstanding, f_wr_outstanding, f_awr_outstanding;

  // The IFU has no write channels. F_OPT_RRESP off restricts the slave to
  // OKAY responses, which the IFU itself asserts on every read.
  // F_OPT_ASYNC_RESET matches the IFU gating ARVALID with reset in the same
  // cycle, as AXI requires of a master during reset; the synchronous checks
  // would flag that drop as a VALID withdrawn before its handshake.
  faxil_master #(
    .C_AXI_DATA_WIDTH(32),
    .C_AXI_ADDR_WIDTH(32),
    .F_OPT_READ_ONLY(1'b1),
    .F_OPT_RRESP(1'b0),
    .F_OPT_ASSUME_RESET(1'b1),
    .F_OPT_ASYNC_RESET(1'b1),
    .F_OPT_INITIAL(1'b0)
  ) faxil (
    .i_clk(clk), .i_axi_reset_n(!reset),
    .i_axi_awvalid(1'b0), .i_axi_awready(1'b0),
    .i_axi_awaddr(32'b0), .i_axi_awprot(3'b0),
    .i_axi_wvalid(1'b0), .i_axi_wready(1'b0),
    .i_axi_wdata(32'b0), .i_axi_wstrb(4'b0),
    .i_axi_bvalid(1'b0), .i_axi_bready(1'b0), .i_axi_bresp(2'b0),
    .i_axi_arvalid(arvalid), .i_axi_arready(arready),
    .i_axi_araddr(araddr), .i_axi_arprot(3'b0),
    .i_axi_rvalid(rvalid), .i_axi_rready(rready),
    .i_axi_rdata(rdata), .i_axi_rresp(rresp),
    .f_axi_rd_outstanding(f_rd_outstanding),
    .f_axi_wr_outstanding(f_wr_outstanding),
    .f_axi_awr_outstanding(f_awr_outstanding)
  );

  // Induction invariant: a read is outstanding exactly while the IFU waits
  // for its response, the only state in which it raises RREADY.
  always @(*) if (!reset) assert(f_rd_outstanding == {3'b0, rready});

  // The contract arbiter_axil assumes of the IFU: nothing new is issued
  // while a read is outstanding.
  always @(*) if (!reset && f_rd_outstanding != 0) assert(!arvalid);

  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;

  always @(*) if (f_past_valid && !reset) begin
    cover(rvalid && rready);
    cover(inst_valid);
  end
endmodule
