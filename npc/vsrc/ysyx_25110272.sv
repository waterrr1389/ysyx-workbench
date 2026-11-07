// CPU top for ysyxSoC: Core with its AXI4 master flattened to the port names of
// ysyxSoC/spec/cpu-interface.md. The slave port and the interrupt are not used:
// slave outputs are held at 0 and unused inputs are left unread.
module ysyx_25110272
  import npc_pkg::*;
(
  input  logic        clock,
  input  logic        reset,
  input  logic        io_interrupt,

  input  logic        io_master_awready,
  output logic        io_master_awvalid,
  output logic [31:0] io_master_awaddr,
  output logic [3:0]  io_master_awid,
  output logic [7:0]  io_master_awlen,
  output logic [2:0]  io_master_awsize,
  output logic [1:0]  io_master_awburst,
  input  logic        io_master_wready,
  output logic        io_master_wvalid,
  output logic [31:0] io_master_wdata,
  output logic [3:0]  io_master_wstrb,
  output logic        io_master_wlast,
  output logic        io_master_bready,
  input  logic        io_master_bvalid,
  input  logic [1:0]  io_master_bresp,
  input  logic [3:0]  io_master_bid,
  input  logic        io_master_arready,
  output logic        io_master_arvalid,
  output logic [31:0] io_master_araddr,
  output logic [3:0]  io_master_arid,
  output logic [7:0]  io_master_arlen,
  output logic [2:0]  io_master_arsize,
  output logic [1:0]  io_master_arburst,
  output logic        io_master_rready,
  input  logic        io_master_rvalid,
  input  logic [1:0]  io_master_rresp,
  input  logic [31:0] io_master_rdata,
  input  logic        io_master_rlast,
  input  logic [3:0]  io_master_rid,

  output logic        io_slave_awready,
  input  logic        io_slave_awvalid,
  input  logic [31:0] io_slave_awaddr,
  input  logic [3:0]  io_slave_awid,
  input  logic [7:0]  io_slave_awlen,
  input  logic [2:0]  io_slave_awsize,
  input  logic [1:0]  io_slave_awburst,
  output logic        io_slave_wready,
  input  logic        io_slave_wvalid,
  input  logic [31:0] io_slave_wdata,
  input  logic [3:0]  io_slave_wstrb,
  input  logic        io_slave_wlast,
  input  logic        io_slave_bready,
  output logic        io_slave_bvalid,
  output logic [1:0]  io_slave_bresp,
  output logic [3:0]  io_slave_bid,
  output logic        io_slave_arready,
  input  logic        io_slave_arvalid,
  input  logic [31:0] io_slave_araddr,
  input  logic [3:0]  io_slave_arid,
  input  logic [7:0]  io_slave_arlen,
  input  logic [2:0]  io_slave_arsize,
  input  logic [1:0]  io_slave_arburst,
  input  logic        io_slave_rready,
  output logic        io_slave_rvalid,
  output logic [1:0]  io_slave_rresp,
  output logic [31:0] io_slave_rdata,
  output logic        io_slave_rlast,
  output logic [3:0]  io_slave_rid
);

  axi_req_t bus_req;
  axi_rsp_t bus_rsp;

  // ysyxSoC boots from MROM.
  Core #(.RESET_PC(32'h2000_0000)) u_core (.clk(clock), .reset, .bus_req, .bus_rsp);

  assign io_master_awvalid = bus_req.aw_valid;
  assign io_master_awaddr  = bus_req.aw.addr;
  assign io_master_awid    = bus_req.aw.id;
  assign io_master_awlen   = bus_req.aw.len;
  assign io_master_awsize  = bus_req.aw.size;
  assign io_master_awburst = bus_req.aw.burst;
  assign io_master_wvalid  = bus_req.w_valid;
  assign io_master_wdata   = bus_req.w.data;
  assign io_master_wstrb   = bus_req.w.strb;
  assign io_master_wlast   = bus_req.w.last;
  assign io_master_bready  = bus_req.b_ready;
  assign io_master_arvalid = bus_req.ar_valid;
  assign io_master_araddr  = bus_req.ar.addr;
  assign io_master_arid    = bus_req.ar.id;
  assign io_master_arlen   = bus_req.ar.len;
  assign io_master_arsize  = bus_req.ar.size;
  assign io_master_arburst = bus_req.ar.burst;
  assign io_master_rready  = bus_req.r_ready;

  assign bus_rsp.aw_ready = io_master_awready;
  assign bus_rsp.w_ready  = io_master_wready;
  assign bus_rsp.b_valid  = io_master_bvalid;
  assign bus_rsp.b        = '{id: io_master_bid, resp: axi_resp_e'(io_master_bresp)};
  assign bus_rsp.ar_ready = io_master_arready;
  assign bus_rsp.r_valid  = io_master_rvalid;
  assign bus_rsp.r        = '{id: io_master_rid, data: io_master_rdata,
                              resp: axi_resp_e'(io_master_rresp), last: io_master_rlast};

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

endmodule
