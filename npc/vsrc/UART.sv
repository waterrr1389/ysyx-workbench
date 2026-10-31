// Write-only transmit register: the byte on lane 0 of every write goes to the
// harness, which prints it.
// The Xbar answers reads of this range itself, so the read channels stay idle.
module UART
  import npc_pkg::*;
(
  input  logic     clk,
  input  logic     reset,
  input  axi_req_t req,
  output axi_rsp_t rsp
);

`ifndef FORMAL
  import "DPI-C" function void uart_putc(input byte c);
`endif

  logic  b_valid;
  logic [3:0] b_id;

  // AW and W are taken in the same cycle, so there is no half-received state.
  wire take = req.aw_valid && req.w_valid && !b_valid;

  always_comb begin
    rsp          = '0;
    rsp.aw_ready = take;
    rsp.w_ready  = take;
    rsp.b_valid  = b_valid;
    rsp.b        = '{id: b_id, resp: RESP_OKAY};
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      b_valid <= 1'b0;
    end else begin
      if (take) begin
        b_valid <= 1'b1;
        b_id    <= req.aw.id;
`ifndef FORMAL
        if (req.w.strb[0]) uart_putc(req.w.data[7:0]);
`endif
      end else if (req.b_ready) begin
        b_valid <= 1'b0;
      end
    end
  end

endmodule
