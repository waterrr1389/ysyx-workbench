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

    // 控制字打包格式: {op1_sel[1:0], op2_sel[1:0], wb_sel, pc_sel, inst_type[2:0], reg_wen, alu_op_type[2:0]}
    MuxKeyWithDefault #(9, 7, 13) MainDecoder (
        ctrl_bundle,   
        opcode,        
        13'b00_00_0_0_000_0_000, // 默认不跳、写回ALU结果
        {
            // addi等
            7'b0010011, 13'b00_01_0_0_000_1_011,
            // R-Type
            7'b0110011, 13'b00_00_0_0_000_1_010,
            // LOAD
            7'b0000011, 13'b00_01_0_0_000_1_000,
            // STORE (sw)
            7'b0100011, 13'b00_01_0_0_001_0_000, 
            
            // 分支跳转类 
            // 注意: 我们把 JAL 和 JALR 的 alu_op_type 改成了 000 (走默认的 Force ADD逻辑)
            // JAL: op1=PC, op2=imm, wb=PC+4, pc=ALU结果
            7'b1101111, 13'b01_01_1_1_100_1_000, 
            // JALR: op1=rs1, op2=imm, wb=PC+4, pc=ALU结果
            7'b1100111, 13'b00_01_1_1_000_1_000, 
            
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
        4'b0000,
        {
            1'b0, 4'b0000, // 默认ADD
            1'b1, 4'b0001 // 若 funct7[5] 为 1，则是 SUB
        }
    );

    // 3.2 R-Type 基础译码：处理寄存器运算
    wire [3:0] alu_ctrl_r;
    MuxKeyWithDefault #(5, 3, 4) RTypeMux (
        alu_ctrl_r,
        funct3,        // 键：funct3
        4'b0000,       // 默认：ADD (涵盖了原先的 4'bxxxx 移位等状态，设为 0000 避免综合出 Latch)
        {
            3'b000, r_type_add_sub, // 动态路由到 ADD/SUB 结果
            3'b010, 4'b0110,        // SLT
            3'b100, 4'b0101,        // XOR
            3'b110, 4'b0100,        // OR
            3'b111, 4'b0011         // AND
        }
    );

    // 3.3 I-Type 基础译码：处理立即数运算
    wire [3:0] alu_ctrl_i;
    MuxKeyWithDefault #(4, 3, 4) ITypeMux (
        alu_ctrl_i,
        funct3,        // 键：funct3
        4'b0000,       // 默认：ADD
        {
            3'b010, 4'b0110,        // SLTI
            3'b100, 4'b0101,        // XORI
            3'b110, 4'b0100,        // ORI
            3'b111, 4'b0011         // ANDI
        }
    );

    wire [3:0] alu_ctrl_s;
    MuxKeyWithDefault #(1, 3, 4) BTypeMux(
        alu_ctrl_s,
        funct3,
        4'b0000, // 默认
        {
            3'b000, 4'b1000 // SW
        }
    );

    // 3.4 主 ALU 控制路由：根据 alu_op_type 挑选最终的 sel 输出
    MuxKeyWithDefault #(5, 3, 4) AluCtrlMux (
        sel,
        alu_op_type,   // 键：alu_op_type
        4'b0000,       // 默认：Force ADD (对应 000 / 100 等状态，Load/Store/LUI/AUIPC/JAL)
        {
            3'b001, 4'b0001,    // Branch: 强制 SUB
            3'b010, alu_ctrl_r, // 将输出路由至 R-Type 的译码结果
            3'b011, alu_ctrl_i, // 将输出路由至 I-Type 的译码结果
            3'b100, alu_ctrl_s, // 将输出路由至 S-Type 的译码结果
            3'b111, 4'b1111   // ebreak
        }
    );

endmodule
