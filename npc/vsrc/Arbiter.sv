// Two AXI masters onto one link, one whole transaction at a time.
//
// The owner is locked from the first cycle a request is presented, not from its
// handshake: an AXI master must hold valid until ready, so a request already shown
// to the slave cannot be withdrawn in favour of the other master.
module Arbiter
  import npc_pkg::*;
(
  input  logic     clk,
  input  logic     reset,

  input  axi_req_t ifu_req,
  output axi_rsp_t ifu_rsp,
  input  axi_req_t lsu_req,
  output axi_rsp_t lsu_rsp,

  output axi_req_t out_req,
  input  axi_rsp_t out_rsp
);

  typedef enum logic [1:0] { OWN_NONE, OWN_IFU, OWN_LSU } owner_e;
  owner_e owner, sel;

  wire ifu_wants = ifu_req.ar_valid || ifu_req.aw_valid || ifu_req.w_valid;
  wire lsu_wants = lsu_req.ar_valid || lsu_req.aw_valid || lsu_req.w_valid;

  // Memory accesses come first: they belong to an older instruction than any fetch.
  always_comb begin
    if (owner != OWN_NONE) sel = owner;
    else if (lsu_wants)    sel = OWN_LSU;
    else if (ifu_wants)    sel = OWN_IFU;
    else                   sel = OWN_NONE;
  end

  always_comb begin
    out_req = '0;
    ifu_rsp = '0;
    lsu_rsp = '0;
    unique case (sel)
      OWN_IFU: begin out_req = ifu_req; ifu_rsp = out_rsp; end
      OWN_LSU: begin out_req = lsu_req; lsu_rsp = out_rsp; end
      default: ;
    endcase
  end

  wire done = (out_rsp.b_valid && out_req.b_ready) ||
              (out_rsp.r_valid && out_req.r_ready && out_rsp.r.last);

  always_ff @(posedge clk) begin
    if (reset)     owner <= OWN_NONE;
    else if (done) owner <= OWN_NONE;
    else           owner <= sel;
  end

endmodule
