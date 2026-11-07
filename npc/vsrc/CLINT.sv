// Core-local timer: a read-only 64-bit mtime that counts cycles.
// Only the read channels are used; the core's router never sends writes here.
module CLINT
  import npc_pkg::*;
(
  input  logic     clk,
  input  logic     reset,
  input  axi_req_t req,
  output axi_rsp_t rsp
);

  logic [63:0] mtime;
  logic        r_valid;
  axi_r_t      r;

  // One read in flight: a new address is taken only after the last response left.
  wire take = req.ar_valid && !r_valid;

  always_comb begin
    rsp          = '0;
    rsp.ar_ready = take;
    rsp.r_valid  = r_valid;
    rsp.r        = r;
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      mtime   <= '0;
      r_valid <= 1'b0;
    end else begin
      mtime <= mtime + 64'd1;
      if (take) begin
        r_valid <= 1'b1;
        r <= '{id: req.ar.id, data: req.ar.addr[2] ? mtime[63:32] : mtime[31:0],
               resp: RESP_OKAY, last: 1'b1};
      end else if (req.r_ready) begin
        r_valid <= 1'b0;
      end
    end
  end

endmodule