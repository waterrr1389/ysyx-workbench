// Execute: ALU, control-flow resolution and misprediction redirect.
module ysyx_00000000_EXU
  import ysyx_00000000_pkg::*;
(
  input  logic        clock,
  input  logic        reset,
  input  logic        flush,

  input  logic        in_valid,
  output logic        in_ready,
  input  id2ex_t      in_bits,

  output fwd_t        fwd,

  // Taken when the instruction leaves EXU and its actual next PC differs from the predicted one.
  output logic        redirect_valid,
  output logic [31:0] redirect_pc,

  output logic        bp_update_valid,
  output cf_e         bp_update_cf,
  output logic [31:0] bp_update_pc,
  output logic        bp_update_taken,
  output logic [31:0] bp_update_target,

  output logic        out_valid,
  input  logic        out_ready,
  output ex2mem_t     out_bits
);

  logic   valid;
  id2ex_t r;

  wire fire = valid && out_ready;
  assign in_ready = !valid || out_ready;

  always_ff @(posedge clock) begin
    if (reset || flush) valid <= 1'b0;
    else if (in_ready)  valid <= in_valid;
    if (in_ready && in_valid) r <= in_bits;
  end

  logic [31:0] a, b;
  always_comb begin
    unique case (r.asel)
      ASEL_PC:   a = r.pc;
      ASEL_ZERO: a = 32'd0;
      default:   a = r.rs1_val;
    endcase
    unique case (r.bsel)
      BSEL_RS2:  b = r.rs2_val;
      BSEL_FOUR: b = 32'd4;
      default:   b = r.imm;
    endcase
  end

  logic [31:0] res;
  ysyx_00000000_ALU u_alu (.op(r.alu_op), .a(a), .b(b), .res(res));

  wire br_taken = r.funct3[2] ? (res[0] ^ r.funct3[0]) : ((res == 32'd0) ^ r.funct3[0]);
  wire taken    = r.cf == CF_JAL || r.cf == CF_JALR || (r.cf == CF_BRANCH && br_taken);

  wire [31:0] target_raw = (r.cf == CF_JALR ? r.rs1_val : r.pc) + r.imm;
  wire [31:0] target     = {target_raw[31:1], target_raw[0] & (r.cf != CF_JALR)};
  wire [31:0] seq_pc     = r.pc + 32'd4;
  wire [31:0] actual     = taken ? target : seq_pc;

  wire misalign = taken && target[1];

  exc_t exc;
  always_comb begin
    exc = r.exc;
    if (!r.exc.valid && misalign) begin
      exc.valid = 1'b1;
      exc.cause = EXC_INST_MISALIGN;
    end
  end

  assign redirect_valid = fire && !exc.valid && actual != r.pred_next;
  assign redirect_pc    = actual;

  assign bp_update_valid  = fire && r.cf != CF_NONE && !exc.valid;
  assign bp_update_cf     = r.cf;
  assign bp_update_pc     = r.pc;
  assign bp_update_taken  = taken;
  assign bp_update_target = target;

  assign fwd.valid = valid && r.rd_wen && !exc.valid;
  assign fwd.rd    = r.rd;
  assign fwd.ready = r.wbsel == WB_ALU;
  assign fwd.data  = res;

  assign out_valid = valid;

  always_comb begin
    out_bits.pc       = r.pc;
    out_bits.result   = res;
    out_bits.src      = r.mem_wen ? r.rs2_val : (r.csr_imm ? r.imm : r.rs1_val);
    out_bits.rd       = r.rd;
    out_bits.rd_wen   = r.rd_wen && !exc.valid;
    out_bits.funct3   = r.funct3;
    out_bits.mem_ren  = r.mem_ren;
    out_bits.mem_wen  = r.mem_wen;
    out_bits.wbsel    = r.wbsel;
    out_bits.csr_op   = r.csr_op;
    out_bits.csr_addr = r.csr_addr;
    out_bits.mret     = r.mret;
    out_bits.fencei   = r.fencei;
    out_bits.ebreak   = r.ebreak;
    out_bits.exc      = exc;
  end

endmodule
