// -----------------------------------------------------------------------------
// Module: scan_code_shifter
// Description: 一个三级8位移位寄存器，用于存储最新的三个PS/2扫描码。
//              当 new_data_valid 为高时，在时钟上升沿进行移位操作。
// -----------------------------------------------------------------------------
module scan_code_shifter (
    input               clk,
    input               clrn,
    input               new_data_valid, // 移位使能信号，当有新数据时为高
    input        [7:0]  new_data_in,    // 新的8位扫描码输入

    output  reg  [7:0]  code_out_0,     // 最新的扫描码 (用于最右侧显示)
    output  reg  [7:0]  code_out_1,     // 第二新的扫描码
    output  reg  [7:0]  code_out_2      // 最老的扫描码 (用于最左侧显示)
);

    always @(posedge clk or negedge clrn) begin
        if (!clrn) begin
            // 复位时，清空所有历史记录
            code_out_0 <= 8'h00;
            code_out_1 <= 8'h00;
            code_out_2 <= 8'h00;
        end else begin
            // 只有在 new_data_valid 信号为高时（即接收到新键码时）才进行移位
            if (new_data_valid) begin
                code_out_2 <= code_out_1;   // 最老的 <= 第二新的
                code_out_1 <= code_out_0;   // 第二新的 <= 最新的
                code_out_0 <= new_data_in;  // 最新的 <= 外部新输入
            end
            // 如果 new_data_valid 为低，所有寄存器保持不变
        end
    end

endmodule