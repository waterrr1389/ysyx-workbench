// Types shared by every module: the AXI4 link and the payloads passed between stages.
package npc_pkg;

  typedef logic [31:0] word_t;

  localparam word_t RESET_PC = 32'h8000_0000;
  localparam int    NR_GPR   = 16;  // RV32E

  // ---------------------------------------------------------------------------
  // AXI4. Every master here keeps at most one transaction outstanding and uses
  // single-beat transfers (len 0, INCR), but the full channel fields are carried
  // so the same ports connect to ysyxSoC unchanged.
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    RESP_OKAY   = 2'b00,
    RESP_EXOKAY = 2'b01,
    RESP_SLVERR = 2'b10,
    RESP_DECERR = 2'b11
  } axi_resp_e;

  localparam logic [1:0] BURST_INCR = 2'b01;

  typedef struct packed {
    logic [3:0] id;
    word_t      addr;
    logic [7:0] len;
    logic [2:0] size;
    logic [1:0] burst;
  } axi_a_t;

  typedef struct packed {
    word_t      data;
    logic [3:0] strb;
    logic       last;
  } axi_w_t;

  typedef struct packed {
    logic [3:0] id;
    axi_resp_e  resp;
  } axi_b_t;

  typedef struct packed {
    logic [3:0] id;
    word_t      data;
    axi_resp_e  resp;
    logic       last;
  } axi_r_t;

  // Master-to-slave half of a link: every valid, every payload, and the response readies.
  typedef struct packed {
    logic   aw_valid;
    axi_a_t aw;
    logic   w_valid;
    axi_w_t w;
    logic   b_ready;
    logic   ar_valid;
    axi_a_t ar;
    logic   r_ready;
  } axi_req_t;

  // Slave-to-master half of a link.
  typedef struct packed {
    logic   aw_ready;
    logic   w_ready;
    logic   b_valid;
    axi_b_t b;
    logic   ar_ready;
    logic   r_valid;
    axi_r_t r;
  } axi_rsp_t;

  // ---------------------------------------------------------------------------
  // Decoded control
  // ---------------------------------------------------------------------------
  typedef enum logic [3:0] {
    ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
    ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR,  ALU_AND
  } alu_op_e;

  typedef enum logic [1:0] { OP1_RS1, OP1_PC, OP1_ZERO } op1_sel_e;
  typedef enum logic [1:0] { OP2_RS2, OP2_IMM, OP2_ZERO } op2_sel_e;

  // How the next PC is formed.
  typedef enum logic [1:0] { FLOW_SEQ, FLOW_BRANCH, FLOW_JAL, FLOW_JALR } flow_e;

  // funct3 of the branch instructions, so decode copies the field directly.
  typedef enum logic [2:0] {
    BR_EQ = 3'b000, BR_NE = 3'b001, BR_LT = 3'b100,
    BR_GE = 3'b101, BR_LTU = 3'b110, BR_GEU = 3'b111
  } br_cond_e;

  typedef enum logic [3:0] {
    MEM_NONE,
    MEM_LB, MEM_LH, MEM_LW, MEM_LBU, MEM_LHU,
    MEM_SB, MEM_SH, MEM_SW
  } mem_op_e;

  typedef enum logic [1:0] { CSR_NONE, CSR_RW, CSR_RS, CSR_RC } csr_op_e;

  // Instructions whose effect is decided at commit.
  typedef enum logic [2:0] {
    SYS_NONE, SYS_ECALL, SYS_EBREAK, SYS_MRET, SYS_ILLEGAL, SYS_FETCH_FAULT
  } sys_e;

  typedef enum logic [11:0] {
    CSR_MSTATUS = 12'h300,
    CSR_MTVEC   = 12'h305,
    CSR_MEPC    = 12'h341,
    CSR_MCAUSE  = 12'h342
  } csr_addr_e;

  // ---------------------------------------------------------------------------
  // Stage payloads. Each is the content of the register a stage hands to the next.
  // ---------------------------------------------------------------------------
  typedef struct packed {
    word_t pc;
    word_t inst;
    logic  fault;  // the fetch got an error response; inst is meaningless
  } if2id_t;

  typedef struct packed {
    word_t      pc;
    word_t      rs1;
    word_t      rs2;
    word_t      imm;
    logic [3:0] rd;
    logic       rd_wen;
    alu_op_e    alu_op;
    op1_sel_e   op1_sel;
    op2_sel_e   op2_sel;
    flow_e      flow;
    br_cond_e   br_cond;
    mem_op_e    mem_op;
    csr_op_e    csr_op;
    logic [11:0] csr_addr;
    sys_e       sys;
  } id2ex_t;

  typedef struct packed {
    word_t      pc;
    word_t      npc;       // next PC unless the instruction traps
    word_t      result;    // rd value, memory address, or CSR write operand
    word_t      store_data;
    logic [3:0] rd;
    logic       rd_wen;
    mem_op_e    mem_op;
    csr_op_e    csr_op;
    logic [11:0] csr_addr;
    sys_e       sys;
  } ex2ls_t;

  typedef struct packed {
    word_t      pc;
    word_t      npc;
    word_t      result;    // rd value; for CSR instructions, the write operand
    logic [3:0] rd;
    logic       rd_wen;
    csr_op_e    csr_op;
    logic [11:0] csr_addr;
    sys_e       sys;
    logic       bus_error; // the load or store got an error response
  } ls2wb_t;

  function automatic logic is_store(mem_op_e op);
    return op inside {MEM_SB, MEM_SH, MEM_SW};
  endfunction

endpackage
