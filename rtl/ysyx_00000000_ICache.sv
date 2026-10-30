// Instruction memory side of the core: serves imem requests through an AXI4 read master.
// No storage yet: every fetch is a single-beat read.
module ysyx_00000000_ICache
  import ysyx_00000000_pkg::*;
(
  input  logic        clock,
  input  logic        reset,

  input  logic        req_valid,
  output logic        req_ready,
  input  logic [31:0] req_addr,
  output logic        resp_valid,
  input  logic        resp_ready,
  output logic [31:0] resp_inst,
  output logic        resp_err,
  input  logic        fencei,

  output logic        ar_valid,
  input  logic        ar_ready,
  output axi_a_t      ar_bits,
  input  logic        r_valid,
  output logic        r_ready,
  input  axi_r_t      r_bits
);

  typedef enum logic [1:0] { S_IDLE, S_AR, S_R, S_RESP } state_e;
  state_e      state;
  logic [31:0] addr;

  assign req_ready  = state == S_IDLE || (state == S_RESP && resp_ready);
  assign resp_valid = state == S_RESP;
  assign ar_valid   = state == S_AR;
  assign r_ready    = state == S_R;

  assign ar_bits.id    = 4'd0;
  assign ar_bits.addr  = {addr[31:2], 2'b00};
  assign ar_bits.len   = 8'd0;
  assign ar_bits.size  = 3'd2;
  assign ar_bits.burst = AXI_BURST_INCR;

  always_ff @(posedge clock) begin
    if (reset) begin
      state <= S_IDLE;
    end else begin
      unique case (state)
        S_IDLE: if (req_valid) state <= S_AR;
        S_AR:   if (ar_ready)  state <= S_R;
        S_R:    if (r_valid)   state <= S_RESP;
        S_RESP: if (resp_ready) state <= req_valid ? S_AR : S_IDLE;
        default: state <= S_IDLE;
      endcase
    end
    if (req_valid && req_ready) addr <= req_addr;
    if (state == S_R && r_valid) begin
      resp_inst <= r_bits.data;
      resp_err  <= r_bits.resp != 2'b00;
    end
  end

  wire unused = &{1'b0, fencei, r_bits.id, r_bits.last};

endmodule
