module OP1 # (DATA_LEN = 32) (
  input  [DATA_LEN-1:0] rs1,
  input [DATA_LEN-1:0] pc,
  input [1:0] op1_sel,
  output [DATA_LEN-1:0] op1
);
  MuxKeyWithDefault # (3, 2, 32) Decoder (
    op1,
    op1_sel,
    32'b0,
    {
      2'b00, rs1,
      2'b01, pc,
      2'b10, 32'b0 
    }
  );
  
endmodule
