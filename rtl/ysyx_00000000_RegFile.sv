// x1..x15 of RV32E; x0 reads as zero. Reads are asynchronous and do not see a same-cycle write.
module ysyx_00000000_RegFile (
  input  logic        clock,
  input  logic        wen,
  input  logic [3:0]  waddr,
  input  logic [31:0] wdata,
  input  logic [3:0]  raddr1,
  output logic [31:0] rdata1,
  input  logic [3:0]  raddr2,
  output logic [31:0] rdata2
);

  logic [31:0] regs [1:15];

  always_ff @(posedge clock) begin
    if (wen && waddr != 4'd0) regs[waddr] <= wdata;
  end

  assign rdata1 = raddr1 == 4'd0 ? 32'd0 : regs[raddr1];
  assign rdata2 = raddr2 == 4'd0 ? 32'd0 : regs[raddr2];

endmodule
