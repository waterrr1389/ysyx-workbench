// Routes dmem requests to the CLINT or to the SoC bus by address. The core keeps at most one request
// outstanding, so the target of that request selects the response.
module ysyx_00000000_DmemXbar (
  input  logic        clock,
  input  logic        reset,

  input  logic        req_valid,
  output logic        req_ready,
  input  logic [31:0] req_addr,
  output logic        resp_valid,
  output logic [31:0] resp_rdata,
  output logic        resp_err,

  output logic        clint_req_valid,
  input  logic        clint_req_ready,
  input  logic        clint_resp_valid,
  input  logic [31:0] clint_resp_rdata,
  input  logic        clint_resp_err,

  output logic        bus_req_valid,
  input  logic        bus_req_ready,
  input  logic        bus_resp_valid,
  input  logic [31:0] bus_resp_rdata,
  input  logic        bus_resp_err
);

  localparam logic [15:0] CLINT_PAGE = 16'h0200;

  wire to_clint = req_addr[31:16] == CLINT_PAGE;
  logic sel_clint;

  assign clint_req_valid = req_valid && to_clint;
  assign bus_req_valid   = req_valid && !to_clint;
  assign req_ready       = to_clint ? clint_req_ready : bus_req_ready;

  always_ff @(posedge clock) begin
    if (reset)                       sel_clint <= 1'b0;
    else if (req_valid && req_ready) sel_clint <= to_clint;
  end

  assign resp_valid = sel_clint ? clint_resp_valid : bus_resp_valid;
  assign resp_rdata = sel_clint ? clint_resp_rdata : bus_resp_rdata;
  assign resp_err   = sel_clint ? clint_resp_err   : bus_resp_err;

endmodule
