// Execute unit: ALU, branch condition and next-PC computation.
module EXU
  import npc_pkg::*;
(
  input  logic   clk,
  input  logic   reset,

  input  logic   in_valid,
  output logic   in_ready,
  input  id2ex_t in,

  output logic   out_valid,
  input  logic   out_ready,
  output ex2ls_t out
);

  word_t op1, op2, alu, npc;
  logic  taken;

  always_comb begin
    unique case (in.op1_sel)
      OP1_PC:   op1 = in.pc;
      OP1_ZERO: op1 = '0;
      default:  op1 = in.rs1;
    endcase
    unique case (in.op2_sel)
      OP2_RS2:  op2 = in.rs2;
      OP2_ZERO: op2 = '0;
      default:  op2 = in.imm;
    endcase

    unique case (in.alu_op)
      ALU_SUB:  alu = op1 - op2 + 32'd1;
      ALU_SLL:  alu = op1 << op2[4:0];
      ALU_SLT:  alu = {31'b0, $signed(op1) < $signed(op2)};
      ALU_SLTU: alu = {31'b0, op1 < op2};
      ALU_XOR:  alu = op1 ^ op2;
      ALU_SRL:  alu = op1 >> op2[4:0];
      ALU_SRA:  alu = $unsigned($signed(op1) >>> op2[4:0]);
      ALU_OR:   alu = op1 | op2;
      ALU_AND:  alu = op1 & op2;
      default:  alu = op1 + op2;
    endcase

    unique case (in.br_cond)
      BR_EQ:   taken = in.rs1 == in.rs2;
      BR_NE:   taken = in.rs1 != in.rs2;
      BR_LT:   taken = $signed(in.rs1) <  $signed(in.rs2);
      BR_GE:   taken = $signed(in.rs1) >= $signed(in.rs2);
      BR_LTU:  taken = in.rs1 <  in.rs2;
      default: taken = in.rs1 >= in.rs2;
    endcase

    unique case (in.flow)
      FLOW_JAL:    npc = in.pc + in.imm;
      FLOW_JALR:   npc = alu & ~32'd1;
      FLOW_BRANCH: npc = taken ? in.pc + in.imm : in.pc + 32'd4;
      default:     npc = in.pc + 32'd4;
    endcase
  end

  ex2ls_t e;
  always_comb begin
    e            = '0;
    e.pc         = in.pc;
    e.npc        = npc;
    e.result     = in.flow inside {FLOW_JAL, FLOW_JALR} ? in.pc + 32'd4 : alu;
    e.store_data = in.rs2;
    e.rd         = in.rd;
    e.rd_wen     = in.rd_wen;
    e.mem_op     = in.mem_op;
    e.csr_op     = in.csr_op;
    e.csr_addr   = in.csr_addr;
    e.sys        = in.sys;
  end

  wire in_fire  = in_valid && in_ready;
  wire out_fire = out_valid && out_ready;
  assign in_ready = !out_valid || out_ready;

  always_ff @(posedge clk) begin
    if (reset) begin
      out_valid <= 1'b0;
    end else begin
      if (out_fire) out_valid <= 1'b0;
      if (in_fire) begin
        out_valid <= 1'b1;
        out       <= e;
      end
    end
  end

endmodule
