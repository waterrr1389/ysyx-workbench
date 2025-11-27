module RegisterFile #(ADDR_WIDTH = 1, DATA_WIDTH = 1) (
  input clk,
  input [DATA_WIDTH-1:0] wdata,
  input [ADDR_WIDTH-1:0] waddr,
  input [ADDR_WIDTH-1:0] raddr1,
  input [ADDR_WIDTH-1:0] raddr2,
  input wen,
  output [DATA_WIDTH-1:0] out1,
  output [DATA_WIDTH-1:0] out2
);
  // import "DPI-C" function void display_reg(input int regs[]);
  reg [DATA_WIDTH-1:0] rf [2**ADDR_WIDTH-1:0];
  always @(posedge clk) begin
    if (wen) begin 
      rf[waddr] <= wdata;
      $display("$%d=%x\n", waddr, wdata);
    end
    // display_reg(rf);
  end

  wire check_zero1 = |raddr1;
  wire check_zero2 = |raddr2;


  MuxKey #(2, 1, DATA_WIDTH) mux1 (out1, check_zero1, {
    1'b0, 32'b0,
    1'b1, rf[raddr1]
  });

  MuxKey #(2, 1, DATA_WIDTH)  mux2 (out2, check_zero2, {
    1'b0, 32'b0,
    1'b1, rf[raddr2]
  });

endmodule
