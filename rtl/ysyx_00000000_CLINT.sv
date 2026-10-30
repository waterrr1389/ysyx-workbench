// Core-local timer: a read-only 64-bit mtime at base + 0xbff8, incremented every cycle.
module ysyx_00000000_CLINT (
  input  logic        clock,
  input  logic        reset,

  input  logic        req_valid,
  output logic        req_ready,
  input  logic [31:0] req_addr,
  output logic        resp_valid,
  output logic [31:0] resp_rdata,
  output logic        resp_err
);

  logic [63:0] mtime;

  assign req_ready = 1'b1;
  assign resp_err  = 1'b0;

  always_ff @(posedge clock) begin
    if (reset) mtime <= 64'd0;
    else       mtime <= mtime + 64'd1;
    resp_valid <= !reset && req_valid;
    if (req_valid) resp_rdata <= req_addr[2] ? mtime[63:32] : mtime[31:0];
  end

endmodule
