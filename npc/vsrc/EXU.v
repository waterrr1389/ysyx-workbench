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
    wire[DATA_LEN-1:0] sub_b = ~b;
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
            4'b0000: begin
                out = a + b;
            end 
            // 减法 (a - b)
            4'b0001: begin
                out = sub_tmp[DATA_LEN-1:0];
            end
            // 按位取反 (~a)
            4'b0010: begin
                out = ~a;
            end
            // 按位与 (a & b)
            4'b0011: begin
                out = a & b;
            end
            // 按位或 (a | b)
            4'b0100: begin
                out = a | b;
            end
            // 按位异或 (a ^ b)
            4'b0101: begin
                out = a ^ b;
            end
            // 有符号小于比较(slt, a < b)
            // 结果编码为 0/1
            4'b0110: begin
                if ((sub_tmp[DATA_LEN-1] ^ sub_OF) == 1'b1) begin
                    out = { {(DATA_LEN-1){1'b0}}, 1'b1};              
                end else begin
                    out = { DATA_LEN{1'b0} };
                end
            end
            // 相等比较(seq, a == b)
            // 结果编码为 0/1
            4'b0111: begin
                if (a == b) begin
                    out = { {(DATA_LEN-1){1'b0}}, 1'b1};
                end else begin
                    out = { DATA_LEN{1'b0} };
                end
            end
            // 写内存(SW-空指令）
                4'b1000: begin
            end
            // ebreak 指令处理 (ebreak())
            4'b1111: begin
                npc_trap();
            end
            // 默认输出 0 (out = 0)
            default: begin
                out = {DATA_LEN{1'b0}};
            end
        endcase
    end

endmodule
