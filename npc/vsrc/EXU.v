`include "alu_ops.vh"

module EXU #(DATA_LEN = 1) (
    input [DATA_LEN-1:0] a,
    input [DATA_LEN-1:0] b,
    input [3:0] sel,
    output reg [DATA_LEN-1:0] out
);
    // 用补码形式实现减法 (a - b): a + (~b) + 1
    wire[DATA_LEN:0] sub_tmp;
    // 减法溢出标志(有符号, a - b)
    wire sub_OF;
    wire [4:0] shamt = b[4:0];
    wire[DATA_LEN-1:0] sub_b = ~b;
    wire signed_lt = sub_tmp[DATA_LEN-1] ^ sub_OF;
    wire unsigned_lt = $unsigned(a) < $unsigned(b);
    assign sub_tmp = a + sub_b + 1;
    assign sub_OF = (a[DATA_LEN-1] == sub_b[DATA_LEN-1]) & (sub_tmp[DATA_LEN-1] != a[DATA_LEN-1]);
    
    // 调用 C++ 侧 DPI 函数 (ebreak)
    import "DPI-C" function void npc_trap();

    always@(*) begin
        // 默认值 (out = 0)
        out = 0;

        // 根据 sel 选择 EXU 运算 (out = f(a, b))
        case(sel)
            // 加法 (a + b)
            `ALU_ADD: begin
                out = a + b;
            end 
            // 减法 (a - b)
            `ALU_SUB: begin
                out = sub_tmp[DATA_LEN-1:0];
            end
            // 按位取反 (~a)
            `ALU_NOT: begin
                out = ~a;
            end
            // 按位与 (a & b)
            `ALU_AND: begin
                out = a & b;
            end
            // 按位或 (a | b)
            `ALU_OR: begin
                out = a | b;
            end
            // 按位异或 (a ^ b)
            `ALU_XOR: begin
                out = a ^ b;
            end
            // 有符号小于比较(slt, a < b)
            // 结果编码为 0/1
            `ALU_SLT: begin
                if (signed_lt) begin
                    out = { {(DATA_LEN-1){1'b0}}, 1'b1};              
                end else begin
                    out = { DATA_LEN{1'b0} };
                end
            end
            // 相等比较(seq, a == b)
            // 结果编码为 0/1
            `ALU_SEQ: begin
                if (a == b) begin
                    out = { {(DATA_LEN-1){1'b0}}, 1'b1};
                end else begin
                    out = { DATA_LEN{1'b0} };
                end
            end
            // 写内存(SW-空指令）
            `ALU_STORE: begin

            end
            // Shift left
            `ALU_SLL: begin
                out = a << shamt;
            end
            // 逻辑右移
            `ALU_SRL: begin
                out = a >> shamt;
            end
            // 算术右移
            `ALU_SRA: begin
                out = $signed(a) >>> shamt;
            end
            // Load
            `ALU_BRANCH: begin
            end
            // 无符号数比较(sltu/sltiu, a < b)
            // 结果编码为 0/1
            `ALU_SLTU: begin
                if (unsigned_lt) begin
                    out = {{(DATA_LEN-1){1'b0}}, 1'b1};
                end else begin
                    out = {DATA_LEN{1'b0}};
                end
            end
            // ebreak 指令处理 (ebreak())
            `ALU_EBREAK: begin
                npc_trap();
            end
            // 默认输出 0 (out = 0)
            default: begin
                out = {DATA_LEN{1'b0}};
            end
        endcase
    end

endmodule
