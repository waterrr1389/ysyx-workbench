// Decode unit: turns an instruction into control fields and reads its source registers.
module IDU
  import npc_pkg::*;
(
  input  logic       clk,
  input  logic       reset,

  input  logic       in_valid,
  output logic       in_ready,
  input  if2id_t     in,

  output logic       out_valid,
  input  logic       out_ready,
  output id2ex_t     out,

  output logic [3:0] rs1_addr,
  input  word_t      rs1_data,
  output logic [3:0] rs2_addr,
  input  word_t      rs2_data
);

  localparam logic [6:0] OPC_LUI    = 7'b0110111;
  localparam logic [6:0] OPC_AUIPC  = 7'b0010111;
  localparam logic [6:0] OPC_JAL    = 7'b1101111;
  localparam logic [6:0] OPC_JALR   = 7'b1100111;
  localparam logic [6:0] OPC_BRANCH = 7'b1100011;
  localparam logic [6:0] OPC_LOAD   = 7'b0000011;
  localparam logic [6:0] OPC_STORE  = 7'b0100011;
  localparam logic [6:0] OPC_OPIMM  = 7'b0010011;
  localparam logic [6:0] OPC_OP     = 7'b0110011;
  localparam logic [6:0] OPC_FENCE  = 7'b0001111;
  localparam logic [6:0] OPC_SYSTEM = 7'b1110011;

  wire word_t      inst   = in.inst;
  wire logic [6:0] opcode = inst[6:0];
  wire logic [2:0] funct3 = inst[14:12];
  wire logic [6:0] funct7 = inst[31:25];

  wire word_t imm_i = {{20{inst[31]}}, inst[31:20]};
  wire word_t imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
  wire word_t imm_b = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
  wire word_t imm_u = {inst[31:12], 12'b0};
  wire word_t imm_j = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
  wire word_t zimm  = {27'b0, inst[19:15]};

  // Register fields are 5 bits; RV32E has 16 registers, so bit 4 set is illegal.
  assign rs1_addr = inst[18:15];
  assign rs2_addr = inst[23:20];

  id2ex_t d;
  logic   uses_rs1, uses_rs2, legal;

  // R-type and shift-immediate ALU operation from funct3 and funct7[5].
  function automatic alu_op_e alu_from_funct(logic [2:0] f3, logic f7_5, logic is_reg);
    unique case (f3)
      3'b000: return (is_reg && f7_5) ? ALU_SUB : ALU_ADD;
      3'b001: return ALU_SLL;
      3'b010: return ALU_SLT;
      3'b011: return ALU_SLTU;
      3'b100: return ALU_XOR;
      3'b101: return f7_5 ? ALU_SRA : ALU_SRL;
      3'b110: return ALU_OR;
      default: return ALU_AND;
    endcase
  endfunction

  always_comb begin
    d          = '0;
    d.pc       = in.pc;
    d.rs1      = rs1_data;
    d.rs2      = rs2_data;
    d.rd       = inst[10:7];
    d.alu_op   = ALU_ADD;
    d.op1_sel  = OP1_RS1;
    d.op2_sel  = OP2_IMM;
    d.flow     = FLOW_SEQ;
    d.br_cond  = br_cond_e'(funct3);
    d.mem_op   = MEM_NONE;
    d.csr_op   = CSR_NONE;
    d.csr_addr = inst[31:20];
    d.sys      = SYS_NONE;
    uses_rs1   = 1'b0;
    uses_rs2   = 1'b0;
    legal      = 1'b1;

    unique case (opcode)
      OPC_LUI:   begin d.imm = imm_u; d.op1_sel = OP1_ZERO; d.rd_wen = 1'b1; end
      OPC_AUIPC: begin d.imm = imm_u; d.op1_sel = OP1_PC;   d.rd_wen = 1'b1; end
      OPC_JAL:   begin d.imm = imm_j; d.flow = FLOW_JAL;    d.rd_wen = 1'b1; end
      OPC_JALR: begin
        d.imm = imm_i; d.flow = FLOW_JALR; d.rd_wen = 1'b1; uses_rs1 = 1'b1;
        legal = funct3 == 3'b000;
      end
      OPC_BRANCH: begin
        d.imm = imm_b; d.flow = FLOW_BRANCH; uses_rs1 = 1'b1; uses_rs2 = 1'b1;
        legal = funct3 inside {BR_EQ, BR_NE, BR_LT, BR_GE, BR_LTU, BR_GEU};
      end
      OPC_LOAD: begin
        d.imm = imm_i; d.rd_wen = 1'b1; uses_rs1 = 1'b1;
        unique case (funct3)
          3'b000:  d.mem_op = MEM_LB;
          3'b001:  d.mem_op = MEM_LH;
          3'b010:  d.mem_op = MEM_LW;
          3'b100:  d.mem_op = MEM_LBU;
          3'b101:  d.mem_op = MEM_LHU;
          default: legal = 1'b0;
        endcase
      end
      OPC_STORE: begin
        d.imm = imm_s; uses_rs1 = 1'b1; uses_rs2 = 1'b1;
        unique case (funct3)
          3'b000:  d.mem_op = MEM_SB;
          3'b001:  d.mem_op = MEM_SH;
          3'b010:  d.mem_op = MEM_SW;
          default: legal = 1'b0;
        endcase
      end
      OPC_OPIMM: begin
        d.imm = imm_i; d.rd_wen = 1'b1; uses_rs1 = 1'b1;
        d.alu_op = alu_from_funct(funct3, inst[30], 1'b0);
        // Shift immediates must have funct7 0, or 0100000 for srai.
        if (funct3 == 3'b001) legal = funct7 == 7'b0;
        if (funct3 == 3'b101) legal = funct7 inside {7'b0000000, 7'b0100000};
      end
      OPC_OP: begin
        d.op2_sel = OP2_RS2; d.rd_wen = 1'b1; uses_rs1 = 1'b1; uses_rs2 = 1'b1;
        d.alu_op = alu_from_funct(funct3, inst[30], 1'b1);
        legal = funct7 == 7'b0 || (funct7 == 7'b0100000 && funct3 inside {3'b000, 3'b101});
      end
      // No caches and one instruction at a time: fence and fence.i have nothing to order.
      OPC_FENCE: legal = funct3 inside {3'b000, 3'b001};
      OPC_SYSTEM: begin
        if (funct3 == 3'b000) begin
          unique case (inst)
            32'h0000_0073: d.sys = SYS_ECALL;
            32'h0010_0073: d.sys = SYS_EBREAK;
            32'h3020_0073: d.sys = SYS_MRET;
            default:       legal = 1'b0;
          endcase
        end else begin
          // The CSR write operand goes through the ALU as rs1 + 0 or 0 + zimm.
          d.rd_wen = 1'b1;
          d.imm    = zimm;
          unique case (funct3[1:0])
            2'b01:   d.csr_op = CSR_RW;
            2'b10:   d.csr_op = CSR_RS;
            2'b11:   d.csr_op = CSR_RC;
            default: legal = 1'b0;
          endcase
          if (funct3[2]) begin d.op1_sel = OP1_ZERO; d.op2_sel = OP2_IMM; end
          else begin d.op1_sel = OP1_RS1; d.op2_sel = OP2_ZERO; uses_rs1 = 1'b1; end
          legal = legal && inst[31:20] inside {CSR_MSTATUS, CSR_MTVEC, CSR_MEPC, CSR_MCAUSE};
        end
      end
      default: legal = 1'b0;
    endcase

    if ((uses_rs1 && inst[19]) || (uses_rs2 && inst[24]) || (d.rd_wen && inst[11])) legal = 1'b0;
    if (in.fault) d.sys = SYS_FETCH_FAULT;
    else if (!legal) d.sys = SYS_ILLEGAL;
    // A trapping instruction must not write anything.
    if (d.sys inside {SYS_FETCH_FAULT, SYS_ILLEGAL}) begin
      d.rd_wen = 1'b0; d.mem_op = MEM_NONE; d.csr_op = CSR_NONE; d.flow = FLOW_SEQ;
    end
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
        out       <= d;
      end
    end
  end

endmodule
