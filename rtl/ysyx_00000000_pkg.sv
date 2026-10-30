package ysyx_00000000_pkg;

  localparam logic [31:0] RESET_PC = 32'h3000_0000;

  typedef enum logic [3:0] {
    ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU, ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR, ALU_AND
  } alu_op_e;

  typedef enum logic [1:0] { ASEL_RS1, ASEL_PC, ASEL_ZERO } asel_e;
  typedef enum logic [1:0] { BSEL_RS2, BSEL_IMM, BSEL_FOUR } bsel_e;

  // Result source of an instruction; anything but WB_ALU is only ready after MEU.
  typedef enum logic [1:0] { WB_ALU, WB_MEM, WB_CSR } wbsel_e;

  typedef enum logic [1:0] { CSR_NONE, CSR_RW, CSR_RS, CSR_RC } csr_op_e;

  typedef enum logic [1:0] { CF_NONE, CF_BRANCH, CF_JAL, CF_JALR } cf_e;

  // Instruction class reported at retirement for performance counters only.
  typedef enum logic [2:0] {
    IC_ALU, IC_BRANCH, IC_JUMP, IC_LOAD, IC_STORE, IC_CSR, IC_SYSTEM
  } inst_class_e;

  localparam logic [3:0] EXC_INST_MISALIGN = 4'd0;
  localparam logic [3:0] EXC_INST_FAULT    = 4'd1;
  localparam logic [3:0] EXC_ILLEGAL       = 4'd2;
  localparam logic [3:0] EXC_BREAKPOINT    = 4'd3;
  localparam logic [3:0] EXC_LOAD_MISALIGN = 4'd4;
  localparam logic [3:0] EXC_LOAD_FAULT    = 4'd5;
  localparam logic [3:0] EXC_STORE_MISALIGN= 4'd6;
  localparam logic [3:0] EXC_STORE_FAULT   = 4'd7;
  localparam logic [3:0] EXC_ECALL_M       = 4'd11;

  localparam logic [11:0] CSR_MSTATUS   = 12'h300;
  localparam logic [11:0] CSR_MTVEC     = 12'h305;
  localparam logic [11:0] CSR_MEPC      = 12'h341;
  localparam logic [11:0] CSR_MCAUSE    = 12'h342;
  localparam logic [11:0] CSR_MVENDORID = 12'hf11;
  localparam logic [11:0] CSR_MARCHID   = 12'hf12;

  // AXI4 channel payloads (32-bit data, 4-bit id); valid/ready travel beside them.
  typedef struct packed {
    logic [3:0]  id;
    logic [31:0] addr;
    logic [7:0]  len;
    logic [2:0]  size;
    logic [1:0]  burst;
  } axi_a_t;

  typedef struct packed {
    logic [31:0] data;
    logic [3:0]  strb;
    logic        last;
  } axi_w_t;

  typedef struct packed {
    logic [3:0]  id;
    logic [1:0]  resp;
  } axi_b_t;

  typedef struct packed {
    logic [3:0]  id;
    logic [31:0] data;
    logic [1:0]  resp;
    logic        last;
  } axi_r_t;

  localparam logic [1:0] AXI_BURST_INCR = 2'b01;

  typedef struct packed {
    logic [31:0] imm;
    logic [3:0]  rd;
    logic        rd_wen;
    logic [3:0]  rs1;
    logic [3:0]  rs2;
    logic        use_rs1;
    logic        use_rs2;
    alu_op_e     alu_op;
    asel_e       asel;
    bsel_e       bsel;
    cf_e         cf;
    logic [2:0]  funct3;
    logic        mem_ren;
    logic        mem_wen;
    wbsel_e      wbsel;
    csr_op_e     csr_op;
    logic        csr_imm;
    logic [11:0] csr_addr;
    logic        mret;
    logic        fencei;
    logic        ebreak;
    logic        ecall;
    logic        illegal;
  } dec_t;

  // A forwarding source as seen from IDU: an older in-flight instruction that will write `rd`.
  typedef struct packed {
    logic        valid;      // valid instruction with a register result
    logic [3:0]  rd;
    logic        ready;      // `data` already holds the final result
    logic [31:0] data;
  } fwd_t;

  typedef struct packed {
    logic [31:0] pc;
    logic [31:0] inst;
    logic [31:0] pred_next;
    logic        fetch_err;
  } if2id_t;

  // Exception carried with an instruction; taken only in MEU.
  typedef struct packed {
    logic       valid;
    logic [3:0] cause;
  } exc_t;

  typedef struct packed {
    logic [31:0] pc;
    logic [31:0] pred_next;
    logic [31:0] rs1_val;
    logic [31:0] rs2_val;
    logic [31:0] imm;
    logic [3:0]  rd;
    logic        rd_wen;
    alu_op_e     alu_op;
    asel_e       asel;
    bsel_e       bsel;
    cf_e         cf;
    logic [2:0]  funct3;     // branch condition / memory size and sign
    logic        mem_ren;
    logic        mem_wen;
    wbsel_e      wbsel;
    csr_op_e     csr_op;
    logic        csr_imm;    // source is zimm (rs1 field) instead of rs1 value
    logic [11:0] csr_addr;
    logic        mret;
    logic        fencei;
    logic        ebreak;
    exc_t        exc;
  } id2ex_t;

  typedef struct packed {
    logic [31:0] pc;
    logic [31:0] result;     // ALU result, or memory address
    logic [31:0] src;        // store data, or CSR source operand
    logic [3:0]  rd;
    logic        rd_wen;
    logic [2:0]  funct3;
    logic        mem_ren;
    logic        mem_wen;
    wbsel_e      wbsel;
    csr_op_e     csr_op;
    logic [11:0] csr_addr;
    logic        mret;
    logic        fencei;
    logic        ebreak;
    exc_t        exc;
    cf_e         cf;         // performance counters only
  } ex2mem_t;

  typedef struct packed {
    logic [31:0] pc;
    logic [3:0]  rd;
    logic        rd_wen;
    logic [31:0] wdata;
    // Retirement information for the simulation environment.
    logic        trap;       // took an exception (including ebreak)
    logic        ebreak;
    logic        skip;       // result differs from the reference model by design (ID CSRs)
    logic        mem_access;
    logic [31:0] mem_addr;   // lets the environment tell device accesses from memory accesses
    inst_class_e cls;
  } mem2wb_t;

endpackage
