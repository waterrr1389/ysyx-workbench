/* verilator lint_off UNUSEDSIGNAL */
module IDU #(DATA_LEN = 1, REG_ADDR = 1) (
    input [DATA_LEN-1:0] inst,
    output [REG_ADDR-1:0] rs1,
    output [REG_ADDR-1:0] rs2,
    output [REG_ADDR-1:0] rd,
    output [3:0] sel,
    output reg_wen,
    output imm_or_reg,
    output [11:0] imm
); 
    // opcode 字段
    parameter OPCODE_LENGTH = 7;
    wire [OPCODE_LENGTH-1:0] opcode;
    assign opcode = inst[6:0];

    // // funct3字段
    // wire [2:0] funct3;
    // assign funct3 = inst[14:12];

    // 寄存器操作数
    assign rs1 = inst[19:15];
    assign rs2 = 5'b00000;
    assign rd = inst[11:7];

    //  
    assign imm = inst[31:20];   

    // 根据funct3和opcode进行两次选择器译码
    // param: output, key, defualt_value
    MuxKeyWithDefault # (2, 7, 4) Mux0 (sel, opcode, 4'b0, {
        7'b0010011, 4'b0000,
        7'b1110011, 4'b1000 
    });

    //MuxKeyWithDefault # (1, 7, 3) Mux1 (sel, funct3, 3'b0, {
        //7'b0010011, 3'b000 
    //});
    

    assign reg_wen = 1'b1;
    assign imm_or_reg = 1'b1;

endmodule
/* verilator lint_on UNUSEDSIGNAL */
