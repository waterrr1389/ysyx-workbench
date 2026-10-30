// Writeback: holds one retired instruction per cycle; always ready.
module ysyx_00000000_WBU
  import ysyx_00000000_pkg::*;
(
  input  logic        clock,
  input  logic        reset,

  input  logic        in_valid,
  input  mem2wb_t     in_bits,

  output fwd_t        fwd,

  output logic        rf_wen,
  output logic [3:0]  rf_waddr,
  output logic [31:0] rf_wdata,

  output logic        retire_valid,
  output mem2wb_t     retire_bits
);

  logic    valid;
  mem2wb_t r;

  always_ff @(posedge clock) begin
    if (reset) valid <= 1'b0;
    else       valid <= in_valid;
    if (in_valid) r <= in_bits;
  end

  assign rf_wen   = valid && r.rd_wen;
  assign rf_waddr = r.rd;
  assign rf_wdata = r.wdata;

  assign fwd.valid = rf_wen;
  assign fwd.rd    = r.rd;
  assign fwd.ready = 1'b1;
  assign fwd.data  = r.wdata;

  assign retire_valid = valid;
  assign retire_bits  = r;

endmodule
