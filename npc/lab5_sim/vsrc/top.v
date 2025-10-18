module top(
    input clk,
    input clrn,
    input ps2_clk,
    input ps2_data,
    output overflow,
    output [6:0] seg0,
    output [6:0] seg1,
    output [6:0] seg2,
    output [6:0] seg3,
    output [6:0] seg4,
    output [6:0] seg5
);
    wire        ready;
    reg         nextdata_n;
    wire [7:0]  data;

    reg         reading_ack;      // 标志位，为1表示正处于“等待对方响应”状态
    wire        new_data_pulse;   // 将为shifter模块生成一个单周期的使能脉冲

    wire [7:0]  history_code_0, history_code_1, history_code_2;



    ps2_keyboard inst_ps2_keyboard(
        .clk(clk), .clrn(clrn), .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .data(data), .ready(ready), .nextdata_n(nextdata_n), .overflow(overflow)
    );

    scan_code_shifter inst_shifter(
        .clk(clk), .clrn(clrn),
        .new_data_valid(new_data_pulse), // 使用单周期使能脉冲
        .new_data_in(data),              // 直接连接到原始数据线
        .code_out_0(history_code_0),
        .code_out_1(history_code_1),
        .code_out_2(history_code_2)
    );


    assign new_data_pulse = ready && !reading_ack;

    always @(posedge clk or negedge clrn) begin
        if (!clrn) begin
            nextdata_n <= 1'b1;
            reading_ack <= 1'b0;
        end else begin
            reading_ack <= 1'b0;
            nextdata_n <= 1'b1;

            if (new_data_pulse) begin
                nextdata_n <= 1'b0;
                reading_ack <= 1'b1;
            end
        end
    end

    hex7seg hex7seg0( .hex_in (history_code_0[3:0]), .seg_out (seg0) );
    hex7seg hex7seg1( .hex_in (history_code_0[7:4]), .seg_out (seg1) );
    hex7seg hex7seg2( .hex_in (history_code_1[3:0]), .seg_out (seg2) );
    hex7seg hex7seg3( .hex_in (history_code_1[7:4]), .seg_out (seg3) );
    hex7seg hex7seg4( .hex_in (history_code_2[3:0]), .seg_out (seg4) );
    hex7seg hex7seg5( .hex_in (history_code_2[7:4]), .seg_out (seg5) );

endmodule