// Merges the fetch master (read only) and the LSU master onto one AXI4 port.
// The read channel is held by one master from AR handshake until the last R beat; the LSU wins ties.
// Only the LSU writes, so the write channels pass straight through.
module ysyx_00000000_AXIArbiter
  import ysyx_00000000_pkg::*;
(
  input  logic   clock,
  input  logic   reset,

  input  logic   if_ar_valid,
  output logic   if_ar_ready,
  input  axi_a_t if_ar_bits,
  output logic   if_r_valid,
  input  logic   if_r_ready,
  output axi_r_t if_r_bits,

  input  logic   ls_ar_valid,
  output logic   ls_ar_ready,
  input  axi_a_t ls_ar_bits,
  output logic   ls_r_valid,
  input  logic   ls_r_ready,
  output axi_r_t ls_r_bits,
  input  logic   ls_aw_valid,
  output logic   ls_aw_ready,
  input  axi_a_t ls_aw_bits,
  input  logic   ls_w_valid,
  output logic   ls_w_ready,
  input  axi_w_t ls_w_bits,
  output logic   ls_b_valid,
  input  logic   ls_b_ready,
  output axi_b_t ls_b_bits,

  output logic   ar_valid,
  input  logic   ar_ready,
  output axi_a_t ar_bits,
  input  logic   r_valid,
  output logic   r_ready,
  input  axi_r_t r_bits,
  output logic   aw_valid,
  input  logic   aw_ready,
  output axi_a_t aw_bits,
  output logic   w_valid,
  input  logic   w_ready,
  output axi_w_t w_bits,
  input  logic   b_valid,
  output logic   b_ready,
  input  axi_b_t b_bits
);

  logic busy;
  logic owner_ls;
  logic ar_hold;      // an AR is being offered but not yet accepted: keep the choice stable
  logic ar_hold_ls;

  wire pick_ls = ar_hold ? ar_hold_ls : ls_ar_valid;

  always_ff @(posedge clock) begin
    if (reset) ar_hold <= 1'b0;
    else       ar_hold <= ar_valid && !ar_ready;
    ar_hold_ls <= pick_ls;
  end

  assign ar_valid    = !busy && (if_ar_valid || ls_ar_valid);
  assign ar_bits     = pick_ls ? ls_ar_bits : if_ar_bits;
  assign ls_ar_ready = !busy && pick_ls && ar_ready;
  assign if_ar_ready = !busy && !pick_ls && ar_ready;

  assign if_r_valid = busy && !owner_ls && r_valid;
  assign ls_r_valid = busy &&  owner_ls && r_valid;
  assign if_r_bits  = r_bits;
  assign ls_r_bits  = r_bits;
  assign r_ready    = busy && (owner_ls ? ls_r_ready : if_r_ready);

  always_ff @(posedge clock) begin
    if (reset) begin
      busy <= 1'b0;
    end else if (!busy) begin
      if (ar_valid && ar_ready) begin
        busy     <= 1'b1;
        owner_ls <= pick_ls;
      end
    end else if (r_valid && r_ready && r_bits.last) begin
      busy <= 1'b0;
    end
  end

  assign aw_valid    = ls_aw_valid;
  assign ls_aw_ready = aw_ready;
  assign aw_bits     = ls_aw_bits;
  assign w_valid     = ls_w_valid;
  assign ls_w_ready  = w_ready;
  assign w_bits      = ls_w_bits;
  assign ls_b_valid  = b_valid;
  assign b_ready     = ls_b_ready;
  assign ls_b_bits   = b_bits;

endmodule
