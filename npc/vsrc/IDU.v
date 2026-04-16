`include "alu_ops.vh"

module IDU #(DATA_LEN = 32, REG_ADDR_LEN = 5) (
    input [DATA_LEN-1:0] inst,
    output [REG_ADDR_LEN-1:0] rs1,
    output [REG_ADDR_LEN-1:0] rs2,
    output [REG_ADDR_LEN-1:0] rd,
    output [3:0] sel,         // EXU 的具体操作码
    output [2:0] inst_type,   // ImmGen 的类型
    output reg_wen,           // RegFile 的写使能
    output [1:0] op1_sel,     // OP1 模块的选择信号
    output [1:0] op2_sel,     // OP2 模块的选择信号
    output       wb_sel,      // 写回选择: 0 选 ALU计算结果, 1 选 PC+4
    output       pc_sel       // PC更新选择: 0 选 PC+4(顺序执行), 1 选 ALU计算结果(发生跳转)
); 

    // 1. 字段提取
    wire [6:0] opcode = inst[6:0];
    wire [2:0] funct3 = inst[14:12];
    /* verilator lint_off UNUSEDSIGNAL */
    wire [6:0] funct7 = inst[31:25];
    /* verilator lint_on UNUSEDSIGNAL */
    assign rs1 = inst[19:15];
    assign rs2 = inst[24:20];
    assign rd  = inst[11:7];

    // 2. 主译码器 (Main Decoder)
    wire [2:0] alu_op_type;
    wire [12:0] ctrl_bundle;
    localparam [2:0] ALU_CLASS_ADD     = 3'b000;
    localparam [2:0] ALU_CLASS_BRANCH  = 3'b001;
    localparam [2:0] ALU_CLASS_RTYPE   = 3'b010;
    localparam [2:0] ALU_CLASS_ITYPE   = 3'b011;
    localparam [2:0] ALU_CLASS_STORE   = 3'b100;
    localparam [2:0] ALU_CLASS_EBREAK  = 3'b111;

    // 控制字打包格式: {op1_sel[1:0], op2_sel[1:0], wb_sel, pc_sel, inst_type[2:0], reg_wen, alu_op_type[2:0]}
    MuxKeyWithDefault #(10, 7, 13) MainDecoder (
        ctrl_bundle,   
        opcode,        
        13'b00_00_0_0_000_0_000, // 默认不跳、写回ALU结果
        {
            // I-Type
            // addi, slti, sltiu, xori, ori, andi...
            // op1 - Reg - 00u
            // op2 - imm - 01
            7'b0010011, 13'b00_01_0_0_000_1_011,

            // R-Type
            // add, sub, sll, slt, sltu, xor, srl, sra, or, and
            7'b0110011, 13'b00_00_0_0_000_1_010,

            // LOAD
            7'b0000011, 13'b00_01_0_0_000_1_000,

            // STORE
            7'b0100011, 13'b00_01_0_0_001_0_000,
            
            // 分支跳转类 
            // 注意: 我们把 JAL 和 JALR 的 alu_op_type 改成了 000 (走默认的 Force ADD逻辑)
            // JAL: op1=PC, op2=imm, wb=PC+4, pc=ALU结果
            7'b1101111, 13'b01_01_1_1_100_1_000, 
            // JALR: op1=rs1, op2=imm, wb=PC+4, pc=ALU结果
            7'b1100111, 13'b00_01_1_1_000_1_000, 

            // B-Type
            7'b1100011, 13'b01_01_0_1_010_0_001,

            // 高位立即数
            7'b0110111, 13'b10_01_0_0_011_1_000, // LUI
            7'b0010111, 13'b01_01_0_0_011_1_000, // AUIPC
            
            // ebreak
            7'b1110011, 13'b00_00_0_0_000_0_111
        }
    );

    // 解包控制字，把 op1_sel 和 op2_sel 解出来
    assign {op1_sel, op2_sel, wb_sel, pc_sel, inst_type, reg_wen, alu_op_type} = ctrl_bundle;

    // 3. ALU 译码器 (ALU Decoder) - 纯 MuxKey 级联实现

    // 3.1 R-Type 特判：当 funct3 == 3'b000 时，根据 funct7[5] 决定 ADD 或 SUB
    wire [3:0] r_type_add_sub;
    MuxKeyWithDefault #(2, 1, 4) RTypeAddSubMux (
        r_type_add_sub,
        funct7[5],     // 键：funct7 的第 5 位
        `ALU_ADD,
        {
            1'b0, `ALU_ADD, // 默认ADD
            1'b1, `ALU_SUB // 若 funct7[5] 为 1，则是 SUB
        }
    );

    // 
    wire [3:0] r_type_srl_sra;
    MuxKeyWithDefault #(2, 1, 4) RTypeShiftMux (
        r_type_srl_sra,
        funct7[5],     // 键：funct7 的第 5 位
        `ALU_ADD,
        {
            1'b0, `ALU_SRL,
            1'b1, `ALU_SRA 
        }
    );

    // 3.1 I-Type 特判：当 funct3 == 3'b000 时，根据 funct7[5] 决定 ADD 或 SUB
    wire [3:0] i_type_srli_srai;
    MuxKeyWithDefault #(2, 1, 4) ITypeShiftMux (
        i_type_srli_srai,
        funct7[5],     // 键：funct7 的第 5 位
        `ALU_ADD,
        {
            1'b0, `ALU_SRL, // 逻辑右移
            1'b1, `ALU_SRA  // 算术右移 
        }
    );

    // 3.2 R-Type 基础译码：处理寄存器运算
    wire [3:0] alu_ctrl_r;
    MuxKeyWithDefault #(8, 3, 4) RTypeMux (
        alu_ctrl_r,
        funct3,        // 键：funct3
        `ALU_ADD,      // 默认：ADD
        {
            3'b000, r_type_add_sub, // 动态路由到 ADD/SUB 结果
            3'b001, `ALU_SLL,       // SLL
            3'b010, `ALU_SLT,       // SLT
            3'b011, `ALU_SLTU,      // SLTU
            3'b100, `ALU_XOR,       // XOR
            3'b101, r_type_srl_sra, // 动态路由至 sra/srl
            3'b110, `ALU_OR,        // OR
            3'b111, `ALU_AND        // AND
        }
    );

    // 3.3 I-Type ：立即数运算
    wire [3:0] alu_ctrl_i;
    MuxKeyWithDefault #(8, 3, 4) ITypeMux (
        alu_ctrl_i,
        funct3,        // 键：funct3
        `ALU_ADD,      // 默认：ADD
        {
            3'b000, `ALU_ADD,       // ADDI
            3'b010, `ALU_SLT,       // SLTI
            3'b011, `ALU_SLTU,      // SLTIU
            3'b100, `ALU_XOR,       // XORI
            3'b110, `ALU_OR,        // ORI
            3'b111, `ALU_AND,       // ANDI
            3'b001, `ALU_SLL,       // SLLI
            3'b101, i_type_srli_srai  // SRLI, SRAI
        }
    );

    wire [3:0] alu_ctrl_b;
    MuxKeyWithDefault #(1, 3, 4) BTypeMux(
        alu_ctrl_b,
        funct3,
        `ALU_ADD, // 默认
        {
            3'b000, `ALU_BRANCH
        }
    );

    wire [3:0] alu_ctrl_s;
    MuxKeyWithDefault #(1, 3, 4) STypeMux(
        alu_ctrl_s,
        funct3,
        `ALU_ADD, // 默认
        {
            3'b000, `ALU_STORE // SW
        }
    );

    // 3.4 主 ALU 控制路由：根据 alu_op_type 挑选最终的 sel 输出
    MuxKeyWithDefault #(6, 3, 4) AluCtrlMux (
        sel,
        alu_op_type,   // 键：alu_op_type
        `ALU_ADD,      // 默认：Force ADD (对应 load/store/lui/auipc/jal)
        {
            ALU_CLASS_ADD, `ALU_ADD,
            ALU_CLASS_BRANCH, alu_ctrl_b,
            ALU_CLASS_RTYPE, alu_ctrl_r,
            ALU_CLASS_ITYPE, alu_ctrl_i,
            ALU_CLASS_STORE, alu_ctrl_s,
            ALU_CLASS_EBREAK, `ALU_EBREAK
        }
    );

endmodule
