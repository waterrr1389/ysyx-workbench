// LSU against any protocol-abiding slave and any upstream that holds its request
// until accepted.
module lsu_check
  import npc_pkg::*;
(
  input logic     clk,
  input logic     reset,
  input logic     in_valid,
  input ex2ls_t   in,
  input logic     out_ready,
  input axi_rsp_t bus_rsp
);

  logic     in_ready, out_valid;
  ls2wb_t   out;
  axi_req_t bus_req;

  LSU dut (.clk, .reset, .in_valid, .in_ready, .in, .out_valid, .out_ready, .out,
           .bus_req, .bus_rsp);

  axi_props #(.SLAVE_ASSUMED(1)) p_bus (.clk, .reset, .req(bus_req), .rsp(bus_rsp));

  logic init = 1'b1;
  always_ff @(posedge clk) init <= 1'b0;
  always_comb if (init) assume (reset);

  logic in_stalled, out_stalled;
  ex2ls_t in_q;
  ls2wb_t out_q;
  always_ff @(posedge clk) begin
    in_stalled  <= !reset && in_valid && !in_ready;
    out_stalled <= !reset && out_valid && !out_ready;
    in_q        <= in;
    out_q       <= out;
  end

  // Instructions in, results out: every accepted instruction produces exactly one result.
  logic [1:0] pending;
  always_ff @(posedge clk) begin
    if (reset) pending <= '0;
    else pending <= pending + 2'(in_valid && in_ready) - 2'(out_valid && out_ready);
  end

  always_comb begin
    if (!reset) begin
      if (in_stalled) assume (in_valid && in == in_q);
      if (out_stalled) assert (out_valid && out == out_q);
      assert (pending <= 2'd1);
      assert (!out_valid || pending == 2'd1);
      cover (out_valid && out_ready && out.bus_error);
      cover (bus_req.aw_valid && bus_req.w_valid);
    end
  end

endmodule
