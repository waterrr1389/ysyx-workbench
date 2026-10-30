// Instruction fetch: PC generation and the imem request/response handshake.
// At most one request is in flight; a redirect while it is in flight marks its response for dropping,
// since a bus transaction that has been issued cannot be withdrawn.
module ysyx_00000000_IFU
  import ysyx_00000000_pkg::*;
(
  input  logic        clock,
  input  logic        reset,

  input  logic        redirect_valid,
  input  logic [31:0] redirect_pc,

  output logic        imem_req_valid,
  input  logic        imem_req_ready,
  output logic [31:0] imem_req_addr,
  input  logic        imem_resp_valid,
  output logic        imem_resp_ready,
  input  logic [31:0] imem_resp_inst,
  input  logic        imem_resp_err,

  // Predictor lookup, combinational on the PC being requested.
  output logic [31:0] bp_pc,
  input  logic [31:0] bp_next,

  output logic        out_valid,
  input  logic        out_ready,
  output if2id_t      out_bits
);

  logic [31:0] pc;
  logic        inflight;
  logic        drop;
  logic [31:0] inf_pc;
  logic [31:0] inf_pred;

  wire resp_fire = imem_resp_valid && imem_resp_ready;
  wire req_fire  = imem_req_valid && imem_req_ready;

  assign bp_pc = pc;

  assign imem_req_valid  = (!inflight || resp_fire) && !redirect_valid;
  assign imem_req_addr   = pc;
  assign imem_resp_ready = inflight && (drop || redirect_valid || out_ready);

  assign out_valid          = inflight && imem_resp_valid && !drop;
  assign out_bits.pc        = inf_pc;
  assign out_bits.inst      = imem_resp_inst;
  assign out_bits.pred_next = inf_pred;
  assign out_bits.fetch_err = imem_resp_err;

  always_ff @(posedge clock) begin
    if (reset) begin
      pc       <= RESET_PC;
      inflight <= 1'b0;
      drop     <= 1'b0;
    end else begin
      if (req_fire) begin
        pc       <= bp_next;
        inf_pc   <= pc;
        inf_pred <= bp_next;
      end
      if (redirect_valid) pc <= redirect_pc;

      if (req_fire)       inflight <= 1'b1;
      else if (resp_fire) inflight <= 1'b0;

      if (resp_fire)                     drop <= 1'b0;
      else if (redirect_valid && inflight) drop <= 1'b1;
    end
  end

endmodule
