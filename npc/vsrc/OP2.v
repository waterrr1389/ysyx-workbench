module OP2 # (DATA_LEN = 32) (
  input  [DATA_LEN-1:0] rs2,
  input [DATA_LEN-1:0] imm,
  input [1:0] op2_sel,
  output [DATA_LEN-1:0] op2
);
  MuxKeyWithDefault # (2, 2, 32) Decoder (
    op2,
    op2_sel,
    32'b0,
    {
      2'b00, rs2,
      2'b01, imm 
    }
  );

endmodule
