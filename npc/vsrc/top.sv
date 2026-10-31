// Simulation top: the core, its two bus masters, and the memory system.
module top
  import npc_pkg::*;
(
  input  logic  clk,
  input  logic  reset,
  // pc is the architectural PC: the next instruction to commit. commit is high in
  // the cycle an instruction commits; after that edge pc holds its successor.
  output word_t pc,
  output logic  commit,
  output word_t mstatus,
  output word_t mtvec,
  output word_t mepc,
  output word_t mcause
);

  logic   if_valid, if_ready;  if2id_t if_out;
  logic   id_valid, id_ready;  id2ex_t id_out;
  logic   ex_valid, ex_ready;  ex2ls_t ex_out;
  logic   ls_valid, ls_ready;  ls2wb_t ls_out;

  logic       redirect_valid;
  word_t      redirect_pc;
  logic [3:0] rs1_addr, rs2_addr, rf_waddr;
  word_t      rs1_data, rs2_data, rf_wdata;
  logic       rf_wen;

  axi_req_t ifu_req, lsu_req, mem_req, sram_req, uart_req;
  axi_rsp_t ifu_rsp, lsu_rsp, mem_rsp, sram_rsp, uart_rsp;

  IFU u_ifu (
    .clk, .reset,
    .out_valid(if_valid), .out_ready(if_ready), .out(if_out),
    .redirect_valid, .redirect_pc, .pc,
    .bus_req(ifu_req), .bus_rsp(ifu_rsp)
  );

  IDU u_idu (
    .clk, .reset,
    .in_valid(if_valid), .in_ready(if_ready), .in(if_out),
    .out_valid(id_valid), .out_ready(id_ready), .out(id_out),
    .rs1_addr, .rs1_data, .rs2_addr, .rs2_data
  );

  RegFile u_rf (
    .clk,
    .raddr1(rs1_addr), .rdata1(rs1_data),
    .raddr2(rs2_addr), .rdata2(rs2_data),
    .wen(rf_wen), .waddr(rf_waddr), .wdata(rf_wdata)
  );

  EXU u_exu (
    .clk, .reset,
    .in_valid(id_valid), .in_ready(id_ready), .in(id_out),
    .out_valid(ex_valid), .out_ready(ex_ready), .out(ex_out)
  );

  LSU u_lsu (
    .clk, .reset,
    .in_valid(ex_valid), .in_ready(ex_ready), .in(ex_out),
    .out_valid(ls_valid), .out_ready(ls_ready), .out(ls_out),
    .bus_req(lsu_req), .bus_rsp(lsu_rsp)
  );

  WBU u_wbu (
    .clk, .reset,
    .in_valid(ls_valid), .in_ready(ls_ready), .in(ls_out),
    .commit, .rf_wen, .rf_waddr, .rf_wdata,
    .redirect_valid, .redirect_pc,
    .mstatus, .mtvec, .mepc, .mcause
  );

  Arbiter u_arbiter (
    .clk, .reset,
    .ifu_req, .ifu_rsp, .lsu_req, .lsu_rsp,
    .out_req(mem_req), .out_rsp(mem_rsp)
  );

  Xbar u_xbar (
    .clk, .reset,
    .in_req(mem_req), .in_rsp(mem_rsp),
    .sram_req, .sram_rsp, .uart_req, .uart_rsp
  );

  SRAM u_sram (.clk, .reset, .req(sram_req), .rsp(sram_rsp));
  UART u_uart (.clk, .reset, .req(uart_req), .rsp(uart_rsp));

endmodule
