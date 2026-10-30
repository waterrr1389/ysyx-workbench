// Simulation-only: reports retired instructions and memory-port handshakes to the C++ environment.
module ysyx_00000000_SimHook
  import ysyx_00000000_pkg::*;
(
  input logic        clock,
  input logic        reset,
  input logic        retire_valid,
  input mem2wb_t     retire_bits,
  input logic        imem_req_fire,
  input logic [31:0] imem_req_addr,
  input logic        imem_resp_fire,
  input logic        dmem_req_fire,
  input logic        dmem_req_wen,
  input logic [31:0] dmem_req_addr,
  input logic        dmem_resp_fire
);

  import "DPI-C" function void sim_retire(
    input int pc, input byte rd, input byte rd_wen, input int wdata, input byte trap,
    input byte ebreak, input byte skip, input byte mem_access, input int mem_addr, input byte cls);

  import "DPI-C" function void sim_mem_event(input byte events, input int imem_addr, input int dmem_addr);

  always_ff @(posedge clock) begin
    if (retire_valid)
      sim_retire(retire_bits.pc, {4'd0, retire_bits.rd}, {7'd0, retire_bits.rd_wen}, retire_bits.wdata,
                 {7'd0, retire_bits.trap}, {7'd0, retire_bits.ebreak}, {7'd0, retire_bits.skip},
                 {7'd0, retire_bits.mem_access}, retire_bits.mem_addr, {5'd0, retire_bits.cls});
  end

  // One call per cycle with any event, so idle cycles cost nothing.
  wire [4:0] events = {dmem_resp_fire, dmem_req_wen, dmem_req_fire, imem_resp_fire, imem_req_fire};
  always_ff @(posedge clock) begin
    if (!reset && events != 5'd0) sim_mem_event({3'd0, events}, imem_req_addr, dmem_req_addr);
  end

endmodule
