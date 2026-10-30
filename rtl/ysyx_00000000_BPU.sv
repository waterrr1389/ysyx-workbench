// Branch predictor. Lookup is combinational on the fetch PC; updates come from EXU when a control-flow
// instruction resolves. The current policy is static not-taken.
module ysyx_00000000_BPU
  import ysyx_00000000_pkg::*;
(
  input  logic        clock,
  input  logic        reset,

  input  logic [31:0] lookup_pc,
  output logic [31:0] lookup_next,

  input  logic        update_valid,
  input  cf_e         update_cf,
  input  logic [31:0] update_pc,
  input  logic        update_taken,
  input  logic [31:0] update_target
);

  assign lookup_next = lookup_pc + 32'd4;

  wire unused = &{1'b0, clock, reset, update_valid, update_cf, update_pc, update_taken, update_target};

endmodule
