// AXI4 protocol properties for one link, as used in this design: single-beat
// transfers and at most one transaction in flight on the link.
//
// Properties of what the master drives are assumed when MASTER_ASSUMED is set
// (the master side is outside the design under test) and asserted otherwise;
// likewise for the slave with SLAVE_ASSUMED.
module axi_props
  import npc_pkg::*;
#(
  parameter bit MASTER_ASSUMED = 1'b0,
  parameter bit SLAVE_ASSUMED  = 1'b0
) (
  input logic     clk,
  input logic     reset,
  input axi_req_t req,
  input axi_rsp_t rsp
);

  logic past_valid = 1'b0;
  always_ff @(posedge clk) past_valid <= 1'b1;

  wire aw_fire = req.aw_valid && rsp.aw_ready;
  wire w_fire  = req.w_valid  && rsp.w_ready;
  wire b_fire  = rsp.b_valid  && req.b_ready;
  wire ar_fire = req.ar_valid && rsp.ar_ready;
  wire r_fire  = rsp.r_valid  && req.r_ready;

  // Parts of the transaction in flight: accepted requests not yet answered.
  logic wr_aw, wr_w, rd;
  always_ff @(posedge clk) begin
    if (reset) begin
      wr_aw <= 1'b0; wr_w <= 1'b0; rd <= 1'b0;
    end else begin
      if (aw_fire) wr_aw <= 1'b1;
      if (w_fire)  wr_w  <= 1'b1;
      if (b_fire)  begin wr_aw <= 1'b0; wr_w <= 1'b0; end
      if (ar_fire) rd <= 1'b1;
      if (r_fire)  rd <= 1'b0;
    end
  end

  // Master: valid holds until ready with a stable payload; one transaction at a time.
  logic m_ok;
  always_comb begin
    m_ok = 1'b1;
    if (req.aw_valid && (req.aw.len != 8'd0 || wr_aw || rd || req.ar_valid)) m_ok = 1'b0;
    if (req.w_valid  && (!req.w.last || wr_w || rd || req.ar_valid))       m_ok = 1'b0;
    if (req.ar_valid && (req.ar.len != 8'd0 || wr_aw || wr_w || rd))       m_ok = 1'b0;
  end

  // Slave: a response follows its whole request and holds until ready.
  logic s_ok;
  always_comb begin
    s_ok = 1'b1;
    if (rsp.b_valid && !(wr_aw && wr_w))    s_ok = 1'b0;
    if (rsp.r_valid && (!rd || !rsp.r.last)) s_ok = 1'b0;
  end

  // What was stalled last cycle, and with which payload. A stalled request or
  // response must be presented again, unchanged.
  logic   aw_st, w_st, ar_st, b_st, r_st;
  axi_a_t aw_q, ar_q;
  axi_w_t w_q;
  axi_b_t b_q;
  axi_r_t r_q;
  always_ff @(posedge clk) begin
    aw_st <= !reset && req.aw_valid && !rsp.aw_ready;
    w_st  <= !reset && req.w_valid  && !rsp.w_ready;
    ar_st <= !reset && req.ar_valid && !rsp.ar_ready;
    b_st  <= !reset && rsp.b_valid  && !req.b_ready;
    r_st  <= !reset && rsp.r_valid  && !req.r_ready;
    aw_q <= req.aw; w_q <= req.w; ar_q <= req.ar; b_q <= rsp.b; r_q <= rsp.r;
  end
  wire m_stable = (!aw_st || (req.aw_valid && req.aw == aw_q)) &&
                  (!w_st  || (req.w_valid  && req.w  == w_q))  &&
                  (!ar_st || (req.ar_valid && req.ar == ar_q));
  wire s_stable = (!b_st || (rsp.b_valid && rsp.b == b_q)) &&
                  (!r_st || (rsp.r_valid && rsp.r == r_q));

  always_comb begin
    if (past_valid && !reset) begin
      if (MASTER_ASSUMED) begin assume (m_ok); assume (m_stable); end
      else                begin assert (m_ok); assert (m_stable); end
      if (SLAVE_ASSUMED)  begin assume (s_ok); assume (s_stable); end
      else                begin assert (s_ok); assert (s_stable); end
    end
  end

endmodule
