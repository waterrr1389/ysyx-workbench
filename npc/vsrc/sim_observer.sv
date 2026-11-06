`ifdef NPC_SIM
// This single-core notification carries no state back into the core.
package npc_observer_pkg;
  event snapshot;
endpackage

module CommitObserver
  import npc_pkg::*;
(
  input logic clk, reset, commit,
  input word_t commit_pc, mstatus, mtvec, mepc, mcause
);
  import "DPI-C" function void npc_report_commit(
    input bit initial_state, input int pc, input int nr_gpr,
    input int priv, input int mstatus, input int mtvec,
    input int mepc, input int mcause
  );

  bit pending;
  bit reset_seen;
  word_t retired_pc;

  // Preserve the event before the pipeline withdraws valid at this edge.
  always @(posedge clk) begin
    pending <= !reset && commit;
    if (!reset && commit) retired_pc <= commit_pc;
  end

  // The falling edge observes completed nonblocking register and CSR writes.
  // Reset release reports the real reset state without an extra execution edge.
  always @(negedge clk or negedge reset) begin
    if (reset) reset_seen = 1;
    else if (reset_seen || pending) begin
      npc_report_commit(reset_seen, retired_pc, NR_GPR, 3,
                        mstatus, mtvec, mepc, mcause);
      -> npc_observer_pkg::snapshot;
      reset_seen = 0;
    end
  end
endmodule

module GprObserver
  import npc_pkg::*;
(input word_t regs [1:NR_GPR-1]);
  import "DPI-C" function void npc_report_gpr(input int index, input int value);
  always @(npc_observer_pkg::snapshot) begin
    npc_report_gpr(0, 0);
    for (int i = 1; i < NR_GPR; i++) npc_report_gpr(i, regs[i]);
  end
endmodule

module PcObserver
  import npc_pkg::*;
(input word_t pc);
  import "DPI-C" function void npc_report_pc(input int pc);
  always @(npc_observer_pkg::snapshot) npc_report_pc(pc);
endmodule

bind WBU CommitObserver sim_commit (
  .clk, .reset, .commit, .commit_pc(in.pc), .mstatus, .mtvec, .mepc, .mcause
);
bind RegFile GprObserver sim_gpr (.regs);
bind IFU PcObserver sim_pc (.pc);
`endif
