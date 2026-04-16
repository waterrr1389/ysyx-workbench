`ifndef NPC_CTRL_DEFS_VH
`define NPC_CTRL_DEFS_VH

`define WB_SRC_ALU     2'b00
`define WB_SRC_PC4     2'b01
`define WB_SRC_LOAD    2'b10

`define PC_SRC_SEQ     2'b00
`define PC_SRC_TARGET  2'b01
`define PC_SRC_BRANCH  2'b10

`define BR_NONE        3'b000
`define BR_BEQ         3'b001
`define BR_BNE         3'b010
`define BR_BLT         3'b011
`define BR_BGE         3'b100
`define BR_BLTU        3'b101
`define BR_BGEU        3'b110

`define MEM_SIZE_B     2'b00
`define MEM_SIZE_H     2'b01
`define MEM_SIZE_W     2'b10

`endif
