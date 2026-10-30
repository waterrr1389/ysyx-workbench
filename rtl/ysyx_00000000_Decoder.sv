// RV32E + Zicsr + Zifencei decoder (M-mode only). Pure combinational.
module ysyx_00000000_Decoder
  import ysyx_00000000_pkg::*;
(
  input  logic [31:0] inst,
  output dec_t        dec
);

  wire [6:0] opcode = inst[6:0];
  wire [2:0] f3     = inst[14:12];
  wire [6:0] f7     = inst[31:25];

  wire [31:0] imm_i = {{20{inst[31]}}, inst[31:20]};
  wire [31:0] imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
  wire [31:0] imm_b = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
  wire [31:0] imm_u = {inst[31:12], 12'b0};
  wire [31:0] imm_j = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};

  wire [11:0] csr = inst[31:20];
  wire csr_known = csr == CSR_MSTATUS || csr == CSR_MTVEC || csr == CSR_MEPC ||
                   csr == CSR_MCAUSE  || csr == CSR_MVENDORID || csr == CSR_MARCHID;
  wire csr_ro    = csr[11:10] == 2'b11;

  alu_op_e op_alu;
  always_comb begin
    unique case (f3)
      3'b000: op_alu = (opcode == 7'b0110011 && f7[5]) ? ALU_SUB : ALU_ADD;
      3'b001: op_alu = ALU_SLL;
      3'b010: op_alu = ALU_SLT;
      3'b011: op_alu = ALU_SLTU;
      3'b100: op_alu = ALU_XOR;
      3'b101: op_alu = f7[5] ? ALU_SRA : ALU_SRL;
      3'b110: op_alu = ALU_OR;
      default: op_alu = ALU_AND;
    endcase
  end

  logic valid_op;
  always_comb begin
    dec          = '0;
    dec.rd       = inst[10:7];
    dec.rs1      = inst[18:15];
    dec.rs2      = inst[23:20];
    dec.funct3   = f3;
    dec.csr_addr = csr;
    dec.alu_op   = ALU_ADD;
    dec.asel     = ASEL_RS1;
    dec.bsel     = BSEL_IMM;
    dec.cf       = CF_NONE;
    dec.wbsel    = WB_ALU;
    dec.csr_op   = CSR_NONE;
    valid_op     = 1'b1;

    unique case (opcode)
      7'b0110111: begin // lui
        dec.rd_wen = 1'b1; dec.asel = ASEL_ZERO; dec.imm = imm_u;
      end
      7'b0010111: begin // auipc
        dec.rd_wen = 1'b1; dec.asel = ASEL_PC; dec.imm = imm_u;
      end
      7'b1101111: begin // jal
        dec.rd_wen = 1'b1; dec.asel = ASEL_PC; dec.bsel = BSEL_FOUR; dec.imm = imm_j; dec.cf = CF_JAL;
      end
      7'b1100111: begin // jalr
        dec.rd_wen = 1'b1; dec.asel = ASEL_PC; dec.bsel = BSEL_FOUR; dec.imm = imm_i; dec.cf = CF_JALR;
        dec.use_rs1 = 1'b1;
        valid_op = f3 == 3'b000;
      end
      7'b1100011: begin // branch
        dec.use_rs1 = 1'b1; dec.use_rs2 = 1'b1; dec.bsel = BSEL_RS2; dec.imm = imm_b; dec.cf = CF_BRANCH;
        dec.alu_op = f3[2] ? (f3[1] ? ALU_SLTU : ALU_SLT) : ALU_XOR;
        valid_op = f3[2:1] != 2'b01;
      end
      7'b0000011: begin // load
        dec.rd_wen = 1'b1; dec.use_rs1 = 1'b1; dec.imm = imm_i; dec.mem_ren = 1'b1; dec.wbsel = WB_MEM;
        valid_op = f3 == 3'b000 || f3 == 3'b001 || f3 == 3'b010 || f3 == 3'b100 || f3 == 3'b101;
      end
      7'b0100011: begin // store
        dec.use_rs1 = 1'b1; dec.use_rs2 = 1'b1; dec.imm = imm_s; dec.mem_wen = 1'b1;
        valid_op = f3 == 3'b000 || f3 == 3'b001 || f3 == 3'b010;
      end
      7'b0010011: begin // op-imm
        dec.rd_wen = 1'b1; dec.use_rs1 = 1'b1; dec.imm = imm_i; dec.alu_op = op_alu;
        if (f3 == 3'b000) dec.alu_op = ALU_ADD;
        if (f3 == 3'b001) valid_op = f7 == 7'b0;
        if (f3 == 3'b101) valid_op = f7 == 7'b0 || f7 == 7'b0100000;
      end
      7'b0110011: begin // op
        dec.rd_wen = 1'b1; dec.use_rs1 = 1'b1; dec.use_rs2 = 1'b1; dec.bsel = BSEL_RS2; dec.alu_op = op_alu;
        valid_op = f7 == 7'b0 || (f7 == 7'b0100000 && (f3 == 3'b000 || f3 == 3'b101));
      end
      7'b0001111: begin // fence, fence.i
        dec.fencei = f3 == 3'b001;
        valid_op = f3 == 3'b000 || f3 == 3'b001;
      end
      7'b1110011: begin // system
        if (f3 == 3'b000) begin
          dec.ecall  = inst == 32'h0000_0073;
          dec.ebreak = inst == 32'h0010_0073;
          dec.mret   = inst == 32'h3020_0073;
          valid_op   = dec.ecall || dec.ebreak || dec.mret || inst == 32'h1050_0073; // wfi as nop
        end else begin
          dec.rd_wen  = 1'b1;
          dec.wbsel   = WB_CSR;
          dec.csr_imm = f3[2];
          dec.imm     = {27'b0, inst[19:15]};
          dec.use_rs1 = !f3[2];
          dec.csr_op  = csr_op_e'(f3[1:0]);
          valid_op    = f3 != 3'b100 && csr_known &&
                        !(csr_ro && (f3[1:0] == 2'b01 || inst[19:15] != 5'b0));
        end
      end
      default: valid_op = 1'b0;
    endcase

    // RV32E has 16 registers; naming x16..x31 is illegal.
    if ((dec.rd_wen && inst[11]) || (dec.use_rs1 && inst[19]) || (dec.use_rs2 && inst[24]))
      valid_op = 1'b0;

    if (dec.rd == 4'd0) dec.rd_wen = 1'b0;

    dec.illegal = !valid_op;
    if (!valid_op) begin
      dec.rd_wen  = 1'b0;
      dec.mem_ren = 1'b0;
      dec.mem_wen = 1'b0;
      dec.csr_op  = CSR_NONE;
      dec.cf      = CF_NONE;
      dec.fencei  = 1'b0;
      dec.mret    = 1'b0;
      dec.ecall   = 1'b0;
      dec.ebreak  = 1'b0;
    end
  end

endmodule
