// IFU against any protocol-abiding slave and a commit point that redirects only
// after the fetched instruction has been handed on.
module ifu_check
  import npc_pkg::*;
(
  input logic     clk,
  input logic     reset,
  input logic     out_ready,
  input logic     redirect_valid,
  input word_t    redirect_pc,
  input axi_rsp_t bus_rsp
);

  logic     out_valid;
  if2id_t   out;
  word_t    pc;
  axi_req_t bus_req;

  IFU dut (.clk, .reset, .out_valid, .out_ready, .out, .redirect_valid, .redirect_pc, .pc,
           .bus_req, .bus_rsp);

  axi_props #(.SLAVE_ASSUMED(1)) p_bus (.clk, .reset, .req(bus_req), .rsp(bus_rsp));

  logic init = 1'b1;
  always_ff @(posedge clk) init <= 1'b0;
  always_comb if (init) assume (reset);

  // The instruction has left IFU and not yet committed.
  logic handed_on;
  always_ff @(posedge clk) begin
    if (reset || redirect_valid)     handed_on <= 1'b0;
    else if (out_valid && out_ready) handed_on <= 1'b1;
  end
  always_comb if (!reset) assume (!redirect_valid || handed_on);

  logic out_stalled;
  if2id_t out_q;
  always_ff @(posedge clk) begin
    out_stalled <= !reset && out_valid && !out_ready;
    out_q       <= out;
  end

  always_comb begin
    if (!reset) begin
      // IFU only reads, and its output holds while IDU is not ready.
      assert (!bus_req.aw_valid && !bus_req.w_valid);
      if (out_stalled) assert (out_valid && out == out_q);
      cover (handed_on && redirect_valid);
    end
  end

endmodule
