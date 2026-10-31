// The memory system (Arbiter, Xbar, SRAM, UART) under two unconstrained masters
// that only obey the protocol. Every internal link, and each master's view of
// its responses, must obey it too; a response routed to the wrong master breaks
// that master's slave-side properties.
module bus_check
  import npc_pkg::*;
(
  input logic     clk,
  input logic     reset,
  input axi_req_t ifu_req,
  input axi_req_t lsu_req
);

  axi_rsp_t ifu_rsp, lsu_rsp, mem_rsp, sram_rsp, uart_rsp;
  axi_req_t mem_req, sram_req, uart_req;

  Arbiter u_arbiter (.clk, .reset, .ifu_req, .ifu_rsp, .lsu_req, .lsu_rsp,
                     .out_req(mem_req), .out_rsp(mem_rsp));
  Xbar    u_xbar    (.clk, .reset, .in_req(mem_req), .in_rsp(mem_rsp),
                     .sram_req, .sram_rsp, .uart_req, .uart_rsp);
  SRAM    u_sram    (.clk, .reset, .req(sram_req), .rsp(sram_rsp));
  UART    u_uart    (.clk, .reset, .req(uart_req), .rsp(uart_rsp));

  axi_props #(.MASTER_ASSUMED(1)) p_ifu  (.clk, .reset, .req(ifu_req),  .rsp(ifu_rsp));
  axi_props #(.MASTER_ASSUMED(1)) p_lsu  (.clk, .reset, .req(lsu_req),  .rsp(lsu_rsp));
  axi_props                       p_mem  (.clk, .reset, .req(mem_req),  .rsp(mem_rsp));
  axi_props                       p_sram (.clk, .reset, .req(sram_req), .rsp(sram_rsp));
  axi_props                       p_uart (.clk, .reset, .req(uart_req), .rsp(uart_rsp));

  logic init = 1'b1;
  always_ff @(posedge clk) init <= 1'b0;
  always_comb if (init) assume (reset);

  // Reachability: each master completes a read and a write, and an unmapped
  // address gets its error. If one stops being reached, the assumptions are too strong.
  always_comb begin
    if (!reset) begin
      cover (ifu_rsp.r_valid && ifu_req.r_ready);
      cover (lsu_rsp.b_valid && lsu_req.b_ready && lsu_rsp.b.resp == RESP_OKAY);
      cover (lsu_rsp.r_valid && lsu_req.r_ready && lsu_rsp.r.resp == RESP_DECERR);
      cover (uart_rsp.b_valid && uart_req.b_ready);
    end
  end

endmodule
