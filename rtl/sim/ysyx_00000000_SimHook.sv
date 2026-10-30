// Simulation-only: reports every retired instruction to the C++ environment.
module ysyx_00000000_SimHook
  import ysyx_00000000_pkg::*;
(
  input logic    clock,
  input logic    retire_valid,
  input mem2wb_t retire_bits
);

  import "DPI-C" function void sim_retire(
    input int pc, input byte rd, input byte rd_wen, input int wdata, input byte trap,
    input byte ebreak, input byte skip, input byte mem_access, input int mem_addr);

  always_ff @(posedge clock) begin
    if (retire_valid)
      sim_retire(retire_bits.pc, {4'd0, retire_bits.rd}, {7'd0, retire_bits.rd_wen}, retire_bits.wdata,
                 {7'd0, retire_bits.trap}, {7'd0, retire_bits.ebreak}, {7'd0, retire_bits.skip},
                 {7'd0, retire_bits.mem_access}, retire_bits.mem_addr);
  end

endmodule
