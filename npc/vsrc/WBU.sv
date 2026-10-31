// Write-back unit and the single commit point. An instruction takes effect here
// and nowhere else: the register write, CSR updates, traps, and the next PC.
module WBU
  import npc_pkg::*;
(
  input  logic       clk,
  input  logic       reset,

  input  logic       in_valid,
  output logic       in_ready,
  input  ls2wb_t     in,

  output logic       commit,
  output logic       rf_wen,
  output logic [3:0] rf_waddr,
  output word_t      rf_wdata,

  output logic       redirect_valid,
  output word_t      redirect_pc,

  output word_t      mstatus,
  output word_t      mtvec,
  output word_t      mepc,
  output word_t      mcause
);

  import "DPI-C" function void npc_trap();
  import "DPI-C" function void npc_abort_at(input string reason);

  localparam word_t CAUSE_ECALL_M = 32'd11;

  assign in_ready = 1'b1;
  assign commit   = in_valid;

  word_t csr_old, csr_new;
  always_comb begin
    unique case (in.csr_addr)
      CSR_MSTATUS: csr_old = mstatus;
      CSR_MTVEC:   csr_old = mtvec;
      CSR_MEPC:    csr_old = mepc;
      default:     csr_old = mcause;
    endcase
    unique case (in.csr_op)
      CSR_RS:  csr_new = csr_old | in.result;
      CSR_RC:  csr_new = csr_old & ~in.result;
      default: csr_new = in.result;
    endcase
  end

  // Without interrupts, mstatus.MIE/MPIE stacking on traps has no observable
  // effect, and the reference model does not do it either; traps only set mepc and mcause.
  wire trap = in.sys == SYS_ECALL;
  wire csr_write = in.csr_op != CSR_NONE;

  assign rf_wen   = commit && in.rd_wen && !in.bus_error;
  assign rf_waddr = in.rd;
  assign rf_wdata = csr_write ? csr_old : in.result;

  assign redirect_valid = commit;
  always_comb begin
    unique case (in.sys)
      SYS_ECALL: redirect_pc = mtvec;
      SYS_MRET:  redirect_pc = mepc;
      default:   redirect_pc = in.npc;
    endcase
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      mstatus <= 32'h0000_1800;  // MPP = M, the only privilege level
      mtvec   <= '0;
      mepc    <= '0;
      mcause  <= '0;
    end else if (commit) begin
      if (trap) begin
        mepc   <= in.pc;
        mcause <= CAUSE_ECALL_M;
      end else if (csr_write) begin
        unique case (in.csr_addr)
          CSR_MSTATUS: mstatus <= csr_new;
          CSR_MTVEC:   mtvec   <= csr_new;
          CSR_MEPC:    mepc    <= csr_new;
          default:     mcause  <= csr_new;
        endcase
      end
    end
  end

  // Conditions the core cannot handle yet end the simulation with a named reason.
  always_ff @(posedge clk) begin
    if (!reset && commit) begin
      unique case (in.sys)
        SYS_EBREAK:      npc_trap();
        SYS_ILLEGAL:     npc_abort_at("illegal-inst");
        SYS_FETCH_FAULT: npc_abort_at("fetch-fault");
        default:         if (in.bus_error) npc_abort_at("bus-error");
      endcase
    end
  end

endmodule
