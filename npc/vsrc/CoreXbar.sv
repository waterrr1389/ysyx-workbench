// Splits the core's single master: CLINT reads stay inside the core,
// every other access goes out on the external port.
module CoreXbar
  import npc_pkg::*;
(
  input  logic     clk,
  input  logic     reset,

  input  axi_req_t in_req,
  output axi_rsp_t in_rsp,

  output axi_req_t clint_req,
  input  axi_rsp_t clint_rsp,
  output axi_req_t out_req,
  input  axi_rsp_t out_rsp
);

  typedef enum logic [1:0] { TO_NONE, TO_CLINT, TO_OUT } route_e;

  // Locked from the cycle an address is presented, as in Xbar.
  route_e route, sel;
  always_comb begin
    if (route != TO_NONE)     sel = route;
    else if (in_req.ar_valid) sel = (in_req.ar.addr - CLINT_BASE < CLINT_SIZE) ? TO_CLINT : TO_OUT;
    else if (in_req.aw_valid) sel = TO_OUT;
    else                      sel = TO_NONE;
  end

  always_comb begin
    clint_req = '0;
    out_req   = '0;
    in_rsp    = '0;
    unique case (sel)
      TO_CLINT: begin clint_req = in_req; in_rsp = clint_rsp; end
      TO_OUT:   begin out_req   = in_req; in_rsp = out_rsp;   end
      default: ;
    endcase
  end

  wire done = (in_rsp.b_valid && in_req.b_ready) ||
              (in_rsp.r_valid && in_req.r_ready && in_rsp.r.last);

  always_ff @(posedge clk) begin
    if (reset || done) route <= TO_NONE;
    else               route <= sel;
  end

endmodule