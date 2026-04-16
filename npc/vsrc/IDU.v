`include "alu_ops.vh"
`include "ctrl_defs.vh"

module IDU #(DATA_LEN = 32, REG_ADDR_LEN = 5) (
    input [DATA_LEN-1:0] inst,
    output [REG_ADDR_LEN-1:0] rs1,
    output [REG_ADDR_LEN-1:0] rs2,
    output [REG_ADDR_LEN-1:0] rd,
    output [3:0] sel,
    output [2:0] inst_type,
    output reg_wen,
    output [1:0] op1_sel,
    output [1:0] op2_sel,
    output [1:0] wb_src,
    output [1:0] pc_src,
    output [2:0] branch_op,
    output mem_en,
    output mem_we,
    output [1:0] mem_size,
    output mem_unsigned
);

    wire [6:0] opcode = inst[6:0];
    wire [2:0] funct3 = inst[14:12];
    wire [6:0] funct7 = inst[31:25];
    
    wire is_load = opcode == 7'b0000011;

    assign rs1 = inst[19:15];
    assign rs2 = inst[24:20];
    assign rd  = inst[11:7];

    wire [1:0] alu_decode_class;
    wire [15:0] ctrl_bundle;
    localparam [1:0] ALU_DEC_FORCE_ADD = 2'b00;
    localparam [1:0] ALU_DEC_RTYPE     = 2'b01;
    localparam [1:0] ALU_DEC_ITYPE     = 2'b10;
    localparam [1:0] ALU_DEC_EBREAK    = 2'b11;

    // 控制字格式:
    // {op1_sel[1:0], op2_sel[1:0], wb_src[1:0], pc_src[1:0], inst_type[2:0],
    //  reg_wen, mem_en, mem_we, alu_decode_class[1:0]}
    MuxKeyWithDefault #(10, 7, 16) MainDecoder (
        ctrl_bundle,
        opcode,
        16'b00_00_00_00_000_0_0_0_00,
        {
            7'b0010011, 16'b00_01_00_00_000_1_0_0_10, // I-type ALU
            7'b0110011, 16'b00_00_00_00_000_1_0_0_01, // R-type ALU
            7'b0000011, 16'b00_01_10_00_000_1_1_0_00, // Load
            7'b0100011, 16'b00_01_00_00_001_0_1_1_00, // Store
            7'b1101111, 16'b01_01_01_01_100_1_0_0_00, // Jal
            7'b1100111, 16'b00_01_01_01_000_1_0_0_00, // Jalr
            7'b1100011, 16'b01_01_00_10_010_0_0_0_00, // Branch
            7'b0110111, 16'b10_01_00_00_011_1_0_0_00, // Lui
            7'b0010111, 16'b01_01_00_00_011_1_0_0_00, // Auipc
            7'b1110011, 16'b00_00_00_00_000_0_0_0_11  // EBREAK
        }
    );

    assign {op1_sel, op2_sel, wb_src, pc_src, inst_type,
        reg_wen, mem_en, mem_we, alu_decode_class} = ctrl_bundle;

    MuxKeyWithDefault #(6, 3, 3) BranchOpMux (
        branch_op, // 作为输出传入ALU,根据指令类型判断是否需要跳转
        funct3,
        `BR_NONE,
        {
            3'b000, `BR_BEQ,
            3'b001, `BR_BNE,
            3'b100, `BR_BLT,
            3'b101, `BR_BGE,
            3'b110, `BR_BLTU,
            3'b111, `BR_BGEU
        }
    );

    wire [1:0] load_mem_size;
    wire load_mem_unsigned;
    wire [1:0] store_mem_size;

    MuxKeyWithDefault #(5, 3, 2) LoadSizeMux (
        load_mem_size,
        funct3,
        `MEM_SIZE_W,
        {
            3'b000, `MEM_SIZE_B,
            3'b001, `MEM_SIZE_H,
            3'b010, `MEM_SIZE_W,
            3'b100, `MEM_SIZE_B,
            3'b101, `MEM_SIZE_H
        }
    );

    MuxKeyWithDefault #(5, 3, 1) LoadUnsignedMux (
        load_mem_unsigned,
        funct3,
        1'b0,
        {
            3'b000, 1'b0,
            3'b001, 1'b0,
            3'b010, 1'b0,
            3'b100, 1'b1, // lbu
            3'b101, 1'b1  // lhu

        }
    );

    MuxKeyWithDefault #(3, 3, 2) StoreSizeMux (
        store_mem_size,
        funct3,
        `MEM_SIZE_W,
        {
            3'b000, `MEM_SIZE_B,
            3'b001, `MEM_SIZE_H,
            3'b010, `MEM_SIZE_W
        }
    );

    // Load/Store 共用 mem_size，按当前指令类型选择
    assign mem_size = is_load ? load_mem_size : store_mem_size;
    // 对于Load来说，有无符号取决于具体指令
    // 对于Store来说，无符号
    assign mem_unsigned = is_load ? load_mem_unsigned : 1'b0;

    wire [3:0] r_type_add_sub;
    MuxKeyWithDefault #(2, 1, 4) RTypeAddSubMux (
        r_type_add_sub,
        funct7[5],
        `ALU_ADD,
        {
            1'b0, `ALU_ADD,
            1'b1, `ALU_SUB
        }
    );

    wire [3:0] r_type_srl_sra;
    MuxKeyWithDefault #(2, 1, 4) RTypeShiftMux (
        r_type_srl_sra,
        funct7[5],
        `ALU_SRL,
        {
            1'b0, `ALU_SRL,
            1'b1, `ALU_SRA
        }
    );

    wire [3:0] i_type_srli_srai;
    MuxKeyWithDefault #(2, 1, 4) ITypeShiftMux (
        i_type_srli_srai,
        funct7[5],
        `ALU_SRL,
        {
            1'b0, `ALU_SRL,
            1'b1, `ALU_SRA
        }
    );

    wire [3:0] alu_ctrl_r;
    MuxKeyWithDefault #(8, 3, 4) RTypeMux (
        alu_ctrl_r,
        funct3,
        `ALU_ADD,
        {
            3'b000, r_type_add_sub,
            3'b001, `ALU_SLL,
            3'b010, `ALU_SLT,
            3'b011, `ALU_SLTU,
            3'b100, `ALU_XOR,
            3'b101, r_type_srl_sra,
            3'b110, `ALU_OR,
            3'b111, `ALU_AND
        }
    );

    wire [3:0] alu_ctrl_i;
    MuxKeyWithDefault #(8, 3, 4) ITypeMux (
        alu_ctrl_i,
        funct3,
        `ALU_ADD,
        {
            3'b000, `ALU_ADD,
            3'b010, `ALU_SLT,
            3'b011, `ALU_SLTU,
            3'b100, `ALU_XOR,
            3'b110, `ALU_OR,
            3'b111, `ALU_AND,
            3'b001, `ALU_SLL,
            3'b101, i_type_srli_srai
        }
    );

    MuxKeyWithDefault #(4, 2, 4) AluCtrlMux (
        sel,
        alu_decode_class,
        `ALU_ADD,
        {
            ALU_DEC_FORCE_ADD, `ALU_ADD,
            ALU_DEC_RTYPE, alu_ctrl_r,
            ALU_DEC_ITYPE, alu_ctrl_i,
            ALU_DEC_EBREAK, `ALU_EBREAK
        }
    );

endmodule
