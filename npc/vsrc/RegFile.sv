// RV32E integer registers: two combinational reads, one write. x0 reads as zero.
module RegFile
  import npc_pkg::*;
(
  input  logic       clk,
  input  logic [3:0] raddr1,
  output word_t      rdata1,
  input  logic [3:0] raddr2,
  output word_t      rdata2,
  input  logic       wen,
  input  logic [3:0] waddr,
  input  word_t      wdata
);

  word_t regs [1:NR_GPR-1];

  always_ff @(posedge clk) begin
    if (wen && waddr != 4'd0) regs[waddr] <= wdata;
  end

  assign rdata1 = raddr1 == 4'd0 ? '0 : regs[raddr1];
  assign rdata2 = raddr2 == 4'd0 ? '0 : regs[raddr2];

endmodule
