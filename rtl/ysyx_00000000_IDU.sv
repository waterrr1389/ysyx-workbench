// Decode, register read, operand forwarding and RAW hazard stall.
module ysyx_00000000_IDU
  import ysyx_00000000_pkg::*;
(
  input  logic        clock,
  input  logic        reset,
  input  logic        flush,

  input  logic        in_valid,
  output logic        in_ready,
  input  if2id_t      in_bits,

  output logic [3:0]  rf_raddr1,
  output logic [3:0]  rf_raddr2,
  input  logic [31:0] rf_rdata1,
  input  logic [31:0] rf_rdata2,

  // Ordered from youngest to oldest.
  input  fwd_t        fwd_ex,
  input  fwd_t        fwd_mem,
  input  fwd_t        fwd_wb,

  output logic        out_valid,
  input  logic        out_ready,
  output id2ex_t      out_bits
);

  logic   valid;
  if2id_t r;

  assign in_ready = !valid || (out_valid && out_ready);

  always_ff @(posedge clock) begin
    if (reset || flush) valid <= 1'b0;
    else if (in_ready)  valid <= in_valid;
    if (in_ready && in_valid) r <= in_bits;
  end

  dec_t dec;
  ysyx_00000000_Decoder u_dec (.inst(r.inst), .dec(dec));

  assign rf_raddr1 = dec.rs1;
  assign rf_raddr2 = dec.rs2;

  // Returns {stall, value} for one source operand.
  function automatic logic [32:0] operand(input logic [3:0] rs, input logic [31:0] rf_val,
                                          input fwd_t ex, input fwd_t mem, input fwd_t wb);
    if (rs == 4'd0)                        return {1'b0, 32'd0};
    else if (ex.valid  && ex.rd  == rs)    return {!ex.ready,  ex.data};
    else if (mem.valid && mem.rd == rs)    return {!mem.ready, mem.data};
    else if (wb.valid  && wb.rd  == rs)    return {1'b0, wb.data};
    else                                   return {1'b0, rf_val};
  endfunction

  wire [32:0] op1 = operand(dec.rs1, rf_rdata1, fwd_ex, fwd_mem, fwd_wb);
  wire [32:0] op2 = operand(dec.rs2, rf_rdata2, fwd_ex, fwd_mem, fwd_wb);

  exc_t exc;
  always_comb begin
    exc = '0;
    if (r.fetch_err)      begin exc.valid = 1'b1; exc.cause = EXC_INST_FAULT; end
    else if (dec.illegal) begin exc.valid = 1'b1; exc.cause = EXC_ILLEGAL;    end
    else if (dec.ecall)   begin exc.valid = 1'b1; exc.cause = EXC_ECALL_M;    end
    else if (dec.ebreak)  begin exc.valid = 1'b1; exc.cause = EXC_BREAKPOINT; end
  end

  wire stall = (dec.use_rs1 && op1[32]) || (dec.use_rs2 && op2[32]);

  assign out_valid = valid && !stall;

  always_comb begin
    out_bits.pc        = r.pc;
    out_bits.pred_next = r.pred_next;
    out_bits.rs1_val   = op1[31:0];
    out_bits.rs2_val   = op2[31:0];
    out_bits.imm       = dec.imm;
    out_bits.rd        = dec.rd;
    out_bits.rd_wen    = dec.rd_wen;
    out_bits.alu_op    = dec.alu_op;
    out_bits.asel      = dec.asel;
    out_bits.bsel      = dec.bsel;
    out_bits.cf        = dec.cf;
    out_bits.funct3    = dec.funct3;
    out_bits.mem_ren   = dec.mem_ren;
    out_bits.mem_wen   = dec.mem_wen;
    out_bits.wbsel     = dec.wbsel;
    out_bits.csr_op    = dec.csr_op;
    out_bits.csr_imm   = dec.csr_imm;
    out_bits.csr_addr  = dec.csr_addr;
    out_bits.mret      = dec.mret;
    out_bits.fencei    = dec.fencei;
    out_bits.ebreak    = dec.ebreak && !r.fetch_err;
    out_bits.exc       = exc;
    if (r.fetch_err) begin
      // The instruction word is meaningless; make it a no-op that only carries the exception.
      out_bits.rd_wen  = 1'b0;
      out_bits.mem_ren = 1'b0;
      out_bits.mem_wen = 1'b0;
      out_bits.csr_op  = CSR_NONE;
      out_bits.cf      = CF_NONE;
      out_bits.mret    = 1'b0;
      out_bits.fencei  = 1'b0;
    end
  end

endmodule
