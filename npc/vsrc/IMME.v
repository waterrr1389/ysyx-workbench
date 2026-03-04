module IMME # (DATA_LEN = 32) (
  input [2:0] inst_type,
  /* verilator lint_off UNUSEDSIGNAL */
  input [DATA_LEN-1:0] inst,
  /* verilator lint_on UNUSEDSIGNAL */
  output [DATA_LEN-1:0] imm
);

  MuxKeyWithDefault # (5, 3, 32) Mux0 (imm, inst_type, 32'b0, {
    3'b000, {{20{inst[31]}}, inst[31:20]}, // I
    3'b001, {{20{inst[31]}}, inst[31:25], inst[11:7]}, // S
    3'b010, {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0}, // B
    3'b011, {inst[31:12], 12'b0}, // U
    3'b100, {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0}  // J
  });

endmodule
