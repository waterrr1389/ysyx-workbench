// SoC-facing top; port names follow ysyxSoC/spec/cpu-interface.md.
module ysyx_00000000
  import ysyx_00000000_pkg::*;
(
  input         clock,
  input         reset,
  input         io_interrupt,

  input         io_master_awready,
  output        io_master_awvalid,
  output [31:0] io_master_awaddr,
  output [3:0]  io_master_awid,
  output [7:0]  io_master_awlen,
  output [2:0]  io_master_awsize,
  output [1:0]  io_master_awburst,
  input         io_master_wready,
  output        io_master_wvalid,
  output [31:0] io_master_wdata,
  output [3:0]  io_master_wstrb,
  output        io_master_wlast,
  output        io_master_bready,
  input         io_master_bvalid,
  input  [1:0]  io_master_bresp,
  input  [3:0]  io_master_bid,
  input         io_master_arready,
  output        io_master_arvalid,
  output [31:0] io_master_araddr,
  output [3:0]  io_master_arid,
  output [7:0]  io_master_arlen,
  output [2:0]  io_master_arsize,
  output [1:0]  io_master_arburst,
  output        io_master_rready,
  input         io_master_rvalid,
  input  [1:0]  io_master_rresp,
  input  [31:0] io_master_rdata,
  input         io_master_rlast,
  input  [3:0]  io_master_rid,

  output        io_slave_awready,
  input         io_slave_awvalid,
  input  [31:0] io_slave_awaddr,
  input  [3:0]  io_slave_awid,
  input  [7:0]  io_slave_awlen,
  input  [2:0]  io_slave_awsize,
  input  [1:0]  io_slave_awburst,
  output        io_slave_wready,
  input         io_slave_wvalid,
  input  [31:0] io_slave_wdata,
  input  [3:0]  io_slave_wstrb,
  input         io_slave_wlast,
  input         io_slave_bready,
  output        io_slave_bvalid,
  output [1:0]  io_slave_bresp,
  output [3:0]  io_slave_bid,
  output        io_slave_arready,
  input         io_slave_arvalid,
  input  [31:0] io_slave_araddr,
  input  [3:0]  io_slave_arid,
  input  [7:0]  io_slave_arlen,
  input  [2:0]  io_slave_arsize,
  input  [1:0]  io_slave_arburst,
  input         io_slave_rready,
  output        io_slave_rvalid,
  output [1:0]  io_slave_rresp,
  output [31:0] io_slave_rdata,
  output        io_slave_rlast,
  output [3:0]  io_slave_rid
);

  assign io_slave_awready = 1'b0;
  assign io_slave_wready  = 1'b0;
  assign io_slave_bvalid  = 1'b0;
  assign io_slave_bresp   = 2'b0;
  assign io_slave_bid     = 4'b0;
  assign io_slave_arready = 1'b0;
  assign io_slave_rvalid  = 1'b0;
  assign io_slave_rresp   = 2'b0;
  assign io_slave_rdata   = 32'b0;
  assign io_slave_rlast   = 1'b0;
  assign io_slave_rid     = 4'b0;

  // ------------------------------------------------------------------ core
  logic        imem_req_valid, imem_req_ready, imem_resp_valid, imem_resp_ready, imem_resp_err, imem_fencei;
  logic [31:0] imem_req_addr, imem_resp_inst;
  logic        dmem_req_valid, dmem_req_ready, dmem_req_wen, dmem_resp_valid, dmem_resp_err;
  logic [31:0] dmem_req_addr, dmem_req_wdata, dmem_resp_rdata;
  logic [1:0]  dmem_req_size;
  logic [3:0]  dmem_req_wstrb;
  logic        retire_valid;
  mem2wb_t     retire_bits;

  ysyx_00000000_Core u_core (
    .clock, .reset,
    .imem_req_valid, .imem_req_ready, .imem_req_addr,
    .imem_resp_valid, .imem_resp_ready, .imem_resp_inst, .imem_resp_err, .imem_fencei,
    .dmem_req_valid, .dmem_req_ready, .dmem_req_addr, .dmem_req_wen, .dmem_req_size,
    .dmem_req_wdata, .dmem_req_wstrb, .dmem_resp_valid, .dmem_resp_rdata, .dmem_resp_err,
    .retire_valid, .retire_bits
  );

  // ------------------------------------------------------------------ fetch path
  logic   if_ar_valid, if_ar_ready, if_r_valid, if_r_ready;
  axi_a_t if_ar_bits;
  axi_r_t if_r_bits;

  ysyx_00000000_ICache u_icache (
    .clock, .reset,
    .req_valid(imem_req_valid), .req_ready(imem_req_ready), .req_addr(imem_req_addr),
    .resp_valid(imem_resp_valid), .resp_ready(imem_resp_ready),
    .resp_inst(imem_resp_inst), .resp_err(imem_resp_err), .fencei(imem_fencei),
    .ar_valid(if_ar_valid), .ar_ready(if_ar_ready), .ar_bits(if_ar_bits),
    .r_valid(if_r_valid), .r_ready(if_r_ready), .r_bits(if_r_bits)
  );

  // ------------------------------------------------------------------ data path
  logic        clint_req_valid, clint_req_ready, clint_resp_valid, clint_resp_err;
  logic [31:0] clint_resp_rdata;
  logic        lsu_req_valid, lsu_req_ready, lsu_resp_valid, lsu_resp_err;
  logic [31:0] lsu_resp_rdata;

  ysyx_00000000_DmemXbar u_dxbar (
    .clock, .reset,
    .req_valid(dmem_req_valid), .req_ready(dmem_req_ready), .req_addr(dmem_req_addr),
    .resp_valid(dmem_resp_valid), .resp_rdata(dmem_resp_rdata), .resp_err(dmem_resp_err),
    .clint_req_valid, .clint_req_ready, .clint_resp_valid, .clint_resp_rdata, .clint_resp_err,
    .bus_req_valid(lsu_req_valid), .bus_req_ready(lsu_req_ready), .bus_resp_valid(lsu_resp_valid),
    .bus_resp_rdata(lsu_resp_rdata), .bus_resp_err(lsu_resp_err)
  );

  ysyx_00000000_CLINT u_clint (
    .clock, .reset,
    .req_valid(clint_req_valid), .req_ready(clint_req_ready), .req_addr(dmem_req_addr),
    .resp_valid(clint_resp_valid), .resp_rdata(clint_resp_rdata), .resp_err(clint_resp_err)
  );

  logic   ls_ar_valid, ls_ar_ready, ls_r_valid, ls_r_ready, ls_aw_valid, ls_aw_ready;
  logic   ls_w_valid, ls_w_ready, ls_b_valid, ls_b_ready;
  axi_a_t ls_ar_bits, ls_aw_bits;
  axi_r_t ls_r_bits;
  axi_w_t ls_w_bits;
  axi_b_t ls_b_bits;

  ysyx_00000000_LSUAXI u_lsuaxi (
    .clock, .reset,
    .req_valid(lsu_req_valid), .req_ready(lsu_req_ready), .req_addr(dmem_req_addr),
    .req_wen(dmem_req_wen), .req_size(dmem_req_size), .req_wdata(dmem_req_wdata),
    .req_wstrb(dmem_req_wstrb),
    .resp_valid(lsu_resp_valid), .resp_rdata(lsu_resp_rdata), .resp_err(lsu_resp_err),
    .ar_valid(ls_ar_valid), .ar_ready(ls_ar_ready), .ar_bits(ls_ar_bits),
    .r_valid(ls_r_valid), .r_ready(ls_r_ready), .r_bits(ls_r_bits),
    .aw_valid(ls_aw_valid), .aw_ready(ls_aw_ready), .aw_bits(ls_aw_bits),
    .w_valid(ls_w_valid), .w_ready(ls_w_ready), .w_bits(ls_w_bits),
    .b_valid(ls_b_valid), .b_ready(ls_b_ready), .b_bits(ls_b_bits)
  );

  // ------------------------------------------------------------------ SoC port
  axi_a_t ar, aw;
  axi_w_t w;
  axi_r_t r;
  axi_b_t b;

  assign r = '{id: io_master_rid, data: io_master_rdata, resp: io_master_rresp, last: io_master_rlast};
  assign b = '{id: io_master_bid, resp: io_master_bresp};

  ysyx_00000000_AXIArbiter u_arb (
    .clock, .reset,
    .if_ar_valid, .if_ar_ready, .if_ar_bits, .if_r_valid, .if_r_ready, .if_r_bits,
    .ls_ar_valid, .ls_ar_ready, .ls_ar_bits, .ls_r_valid, .ls_r_ready, .ls_r_bits,
    .ls_aw_valid, .ls_aw_ready, .ls_aw_bits, .ls_w_valid, .ls_w_ready, .ls_w_bits,
    .ls_b_valid, .ls_b_ready, .ls_b_bits,
    .ar_valid(io_master_arvalid), .ar_ready(io_master_arready), .ar_bits(ar),
    .r_valid(io_master_rvalid), .r_ready(io_master_rready), .r_bits(r),
    .aw_valid(io_master_awvalid), .aw_ready(io_master_awready), .aw_bits(aw),
    .w_valid(io_master_wvalid), .w_ready(io_master_wready), .w_bits(w),
    .b_valid(io_master_bvalid), .b_ready(io_master_bready), .b_bits(b)
  );

  assign io_master_arid    = ar.id;
  assign io_master_araddr  = ar.addr;
  assign io_master_arlen   = ar.len;
  assign io_master_arsize  = ar.size;
  assign io_master_arburst = ar.burst;
  assign io_master_awid    = aw.id;
  assign io_master_awaddr  = aw.addr;
  assign io_master_awlen   = aw.len;
  assign io_master_awsize  = aw.size;
  assign io_master_awburst = aw.burst;
  assign io_master_wdata   = w.data;
  assign io_master_wstrb   = w.strb;
  assign io_master_wlast   = w.last;

`ifndef SYNTHESIS
  ysyx_00000000_SimHook u_simhook (.clock, .retire_valid, .retire_bits);
`endif

  wire unused = &{1'b0, io_interrupt};

endmodule
