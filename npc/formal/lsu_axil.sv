// Checks the LSU master against the AXI4-Lite rules in faxil_master.
// Every top-level input is a free variable, so the slave side and the core
// may do anything the AXI rules allow.
module lsu_axil (
  input        clk,
  input        reset,
  input        inst_valid,
  input        mem_en,
  input        mem_we,
  input [31:0] mem_addr,
  input [31:0] mem_wdata,
  input [3:0]  mem_wmask,
  input        arready,
  input        rvalid,
  input [31:0] rdata,
  input [1:0]  rresp,
  input        awready,
  input        wready,
  input        bvalid,
  input [1:0]  bresp
);
  wire        arvalid, rready, awvalid, wvalid, bready, inst_done;
  wire [31:0] araddr, awaddr, wdata, mem_rdata;
  wire [3:0]  wstrb;

  LSU #(32) dut (
    .clk(clk), .reset(reset),
    .inst_valid(inst_valid), .mem_en(mem_en), .mem_we(mem_we),
    .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wmask(mem_wmask),
    .mem_rdata(mem_rdata), .inst_done(inst_done),
    .arvalid(arvalid), .arready(arready), .araddr(araddr),
    .rvalid(rvalid), .rready(rready), .rdata(rdata), .rresp(rresp),
    .awvalid(awvalid), .awready(awready), .awaddr(awaddr),
    .wvalid(wvalid), .wready(wready), .wdata(wdata), .wstrb(wstrb),
    .bvalid(bvalid), .bready(bready), .bresp(bresp)
  );

  wire [3:0] f_rd_outstanding, f_wr_outstanding, f_awr_outstanding;

  // F_OPT_RRESP/F_OPT_BRESP off restrict the slave to OKAY responses, which
  // the LSU itself asserts on every response.
  // F_OPT_ASYNC_RESET matches the LSU gating its VALIDs with reset in the
  // same cycle, as AXI requires of a master during reset; the synchronous
  // checks would flag that drop as a VALID withdrawn before its handshake.
  faxil_master #(
    .C_AXI_DATA_WIDTH(32),
    .C_AXI_ADDR_WIDTH(32),
    .F_OPT_RRESP(1'b0),
    .F_OPT_BRESP(1'b0),
    .F_OPT_ASSUME_RESET(1'b1),
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

  // Induction invariants: tie the master's visible state to the transactions
  // faxil_master has counted. Each LSU state drives a distinct valid/ready
  // pattern, so the ports identify it without reaching into the design.
  wire [4:0] f_ports  = {arvalid, rready, awvalid, wvalid, bready};
  wire [11:0] f_counts = {f_rd_outstanding, f_awr_outstanding, f_wr_outstanding};

  always @(*) if (!reset) begin
    case (f_ports)
      5'b00_000: assert(f_counts == 12'h000);  // idle
      5'b00_110: assert(f_counts == 12'h000);  // offer address and data
      5'b00_100: assert(f_counts == 12'h001);  // data taken, offer address
      5'b00_010: assert(f_counts == 12'h010);  // address taken, offer data
      5'b00_001: assert(f_counts == 12'h011);  // wait for write response
      5'b10_000: assert(f_counts == 12'h000);  // offer read address
      5'b01_000: assert(f_counts == 12'h100);  // wait for read response
      default:   assert(1'b0);
    endcase
  end

  // The contract arbiter_axil assumes of the LSU: nothing new is issued
  // until the previous transaction has completed.
  always @(*) if (!reset) begin
    if (f_rd_outstanding != 0) assert(!arvalid && !awvalid && !wvalid);
    if (f_awr_outstanding != 0) assert(!arvalid && !awvalid);
    if (f_wr_outstanding != 0)  assert(!arvalid && !wvalid);
  end

  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;

  always @(*) if (f_past_valid && !reset) begin
    cover(rvalid && rready);
    cover(bvalid && bready);
    cover(f_ports == 5'b00_100);  // write data before address
    cover(f_ports == 5'b00_010);  // write address before data
    cover(inst_done && mem_en);
  end
endmodule
