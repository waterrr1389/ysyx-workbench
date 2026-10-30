module ysyx_00000000_ALU
  import ysyx_00000000_pkg::*;
(
  input  alu_op_e     op,
  input  logic [31:0] a,
  input  logic [31:0] b,
  output logic [31:0] res
);

  // One shared adder serves ADD, SUB and both comparisons.
  wire        sub   = op != ALU_ADD;
  wire [32:0] sum   = {1'b0, a} + {1'b0, sub ? ~b : b} + {32'd0, sub};
  wire        ltu   = !sum[32];
  wire        lt    = (a[31] ^ b[31]) ? a[31] : sum[31];
  wire [4:0]  shamt = b[4:0];

  always_comb begin
    unique case (op)
      ALU_ADD, ALU_SUB: res = sum[31:0];
      ALU_SLL:  res = a << shamt;
      ALU_SLT:  res = {31'd0, lt};
      ALU_SLTU: res = {31'd0, ltu};
      ALU_XOR:  res = a ^ b;
      ALU_SRL:  res = a >> shamt;
      ALU_SRA:  res = $signed(a) >>> shamt;
      ALU_OR:   res = a | b;
      default:  res = a & b;
    endcase
  end

endmodule
