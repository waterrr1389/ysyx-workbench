// The pipeline. Memory is reached only through the imem and dmem ports.
module ysyx_00000000_Core
  import ysyx_00000000_pkg::*;
(
  input  logic        clock,
  input  logic        reset,

  output logic        imem_req_valid,
  input  logic        imem_req_ready,
  output logic [31:0] imem_req_addr,
  input  logic        imem_resp_valid,
  output logic        imem_resp_ready,
  input  logic [31:0] imem_resp_inst,
  input  logic        imem_resp_err,
  output logic        imem_fencei,

  output logic        dmem_req_valid,
  input  logic        dmem_req_ready,
  output logic [31:0] dmem_req_addr,
  output logic        dmem_req_wen,
  output logic [1:0]  dmem_req_size,
  output logic [31:0] dmem_req_wdata,
  output logic [3:0]  dmem_req_wstrb,
  input  logic        dmem_resp_valid,
  input  logic [31:0] dmem_resp_rdata,
  input  logic        dmem_resp_err,

  output logic        retire_valid,
  output mem2wb_t     retire_bits
);

  logic        ex_redirect, mem_redirect;
  logic [31:0] ex_redirect_pc, mem_redirect_pc;

  // MEU is older than EXU, so its redirect wins.
  wire        redirect    = ex_redirect || mem_redirect;
  wire [31:0] redirect_pc = mem_redirect ? mem_redirect_pc : ex_redirect_pc;

  logic        if_valid, id_in_ready;  if2id_t  if_bits;
  logic        id_valid, ex_in_ready;  id2ex_t  id_bits;
  logic        ex_valid, mem_in_ready; ex2mem_t ex_bits;
  logic        mem_valid;              mem2wb_t mem_bits;
  fwd_t        fwd_ex, fwd_mem, fwd_wb;

  logic [31:0] bp_pc, bp_next;
  logic        bp_upd_valid, bp_upd_taken;
  cf_e         bp_upd_cf;
  logic [31:0] bp_upd_pc, bp_upd_target;

  logic [3:0]  rf_raddr1, rf_raddr2, rf_waddr;
  logic [31:0] rf_rdata1, rf_rdata2, rf_wdata;
  logic        rf_wen;

  // The BTB size can be overridden for design space exploration.
`ifndef BPU_ENTRIES
`define BPU_ENTRIES 8
`endif
`ifndef BPU_SPAN_W
`define BPU_SPAN_W 16
`endif
  ysyx_00000000_BPU #(.ENTRIES(`BPU_ENTRIES), .SPAN_W(`BPU_SPAN_W)) u_bpu (
    .clock, .reset,
    .lookup_pc(bp_pc), .lookup_next(bp_next),
    .update_valid(bp_upd_valid), .update_cf(bp_upd_cf), .update_pc(bp_upd_pc),
    .update_taken(bp_upd_taken), .update_target(bp_upd_target)
  );

  ysyx_00000000_IFU u_ifu (
    .clock, .reset,
    .redirect_valid(redirect), .redirect_pc,
    .imem_req_valid, .imem_req_ready, .imem_req_addr,
    .imem_resp_valid, .imem_resp_ready, .imem_resp_inst, .imem_resp_err,
    .bp_pc, .bp_next,
    .out_valid(if_valid), .out_ready(id_in_ready), .out_bits(if_bits)
  );

  ysyx_00000000_IDU u_idu (
    .clock, .reset, .flush(redirect),
    .in_valid(if_valid), .in_ready(id_in_ready), .in_bits(if_bits),
    .rf_raddr1, .rf_raddr2, .rf_rdata1, .rf_rdata2,
    .fwd_ex, .fwd_mem, .fwd_wb,
    .out_valid(id_valid), .out_ready(ex_in_ready), .out_bits(id_bits)
  );

  ysyx_00000000_EXU u_exu (
    .clock, .reset, .flush(redirect),
    .in_valid(id_valid), .in_ready(ex_in_ready), .in_bits(id_bits),
    .fwd(fwd_ex),
    .redirect_valid(ex_redirect), .redirect_pc(ex_redirect_pc),
    .bp_update_valid(bp_upd_valid), .bp_update_cf(bp_upd_cf), .bp_update_pc(bp_upd_pc),
    .bp_update_taken(bp_upd_taken), .bp_update_target(bp_upd_target),
    .out_valid(ex_valid), .out_ready(mem_in_ready), .out_bits(ex_bits)
  );

  ysyx_00000000_MEU u_meu (
    .clock, .reset,
    .in_valid(ex_valid), .in_ready(mem_in_ready), .in_bits(ex_bits),
    .fwd(fwd_mem),
    .redirect_valid(mem_redirect), .redirect_pc(mem_redirect_pc), .fencei(imem_fencei),
    .dmem_req_valid, .dmem_req_ready, .dmem_req_addr, .dmem_req_wen, .dmem_req_size,
    .dmem_req_wdata, .dmem_req_wstrb, .dmem_resp_valid, .dmem_resp_rdata, .dmem_resp_err,
    .out_valid(mem_valid), .out_bits(mem_bits)
  );

  ysyx_00000000_WBU u_wbu (
    .clock, .reset,
    .in_valid(mem_valid), .in_bits(mem_bits),
    .fwd(fwd_wb),
    .rf_wen, .rf_waddr, .rf_wdata,
    .retire_valid, .retire_bits
  );

  ysyx_00000000_RegFile u_rf (
    .clock,
    .wen(rf_wen), .waddr(rf_waddr), .wdata(rf_wdata),
    .raddr1(rf_raddr1), .rdata1(rf_rdata1),
    .raddr2(rf_raddr2), .rdata2(rf_rdata2)
  );

endmodule
