module top(
    input clk,
    input reset,
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
    wire [7:0]  data;
    reg         nextdata_n;

    ps2_keyboard inst_ps2_keyboard(
        .clk(clk), .reset(reset), .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .data(data), .ready(ready), .nextdata_n(nextdata_n), .overflow(overflow)
    );

    parameter S0 = 1'b0;
    parameter S1 = 1'b1;

    reg state, nextstate;

    //state register
    always@(posedge clk) begin
        if(reset) begin
            state <= S0;
        end else begin
            state <= nextstate;
        end
    end

    //next state logic
    always@(*) begin
       case (state) 
        S0: begin
            if (ready) begin
                nextstate = S1;
            end else begin
                nextstate = S0;
            end
        end
        S1: begin 
            nextstate = S0;
        end
        default: nextstate = S0;
       endcase
    end

    //output logic - S1时读取,S0空闲
    assign nextdata_n = (state == S1) ? 1'b0 : 1'b1;

    reg[7:0] buffer[2:0];
    //press count logic
    reg[7:0] key_press_count;

    always@(posedge clk) begin
        if (state == S1) begin
            buffer <=  {buffer[1:0], data};    
        end
    end

    wire release_detected = (buffer[1] == 8'hF0) && (buffer[0] == buffer[2]);

    reg release_detected_dly;
    always @(posedge clk) begin
        if (reset) release_detected_dly <= 1'b0;
        else       release_detected_dly <= release_detected;
    end

    wire count_event = release_detected && !release_detected_dly;

    //计数器只响应这个脉冲事件
    always @(posedge clk) begin
        if (reset) begin
            key_press_count <= 8'h00;
        end else begin
            if (count_event) begin // 只在事件发生时计数
                key_press_count <= key_press_count + 1;

            end
        end
    end

    wire[7:0] ascii;
    MuxKeyWithDefault #(4, 8, 8) i0 (.out(ascii), .key(buffer[0]), .default_out(0), 
    .lut({ 
        8'h1c, 8'h61, //a
        8'h1b, 8'h73, //w
        8'h23, 8'h64,  //d
        8'h1d, 8'h77 //s
    }));

    reg key_is_pressed;

    always @(posedge clk) begin
        if (reset) begin
            key_is_pressed <= 1'b0;
        // 当检测到按键释放时，清除标志
        end else if (release_detected) begin
            key_is_pressed <= 1'b0;
        // 当接收到新的数据，且它不是释放码的前缀F0时，认为是按键按下
        end else if (state == S1 && data != 8'hF0) begin
            key_is_pressed <= 1'b1;
        end
    end

    wire [7:0] d1, d2;
    assign d1 = buffer[0]; // 显示ASCII码的高低位
    assign d2 = ascii; // 另外两个数码管显示00

    // 3. 根据 key_is_pressed 状态来决定数码管的输入
    //    当 key_is_pressed 为1时，显示正常数据 (d1, d2)
    //    当 key_is_pressed 为0时 (按键松开), 输入 4'hF 来熄灭数码管
    //    注意：假设你的 hex7seg 模块在输入为 4'hF 时会熄灭
    hex7seg seg0_inst(.hex_in(key_is_pressed ? d1[3:0]   : 4'hF), .seg_out(seg0));
    hex7seg seg1_inst(.hex_in(key_is_pressed ? d1[7:4]   : 4'hF), .seg_out(seg1));
    hex7seg seg2_inst(.hex_in(key_is_pressed ? d2[3:0]   : 4'hF), .seg_out(seg2));
    hex7seg seg3_inst(.hex_in(key_is_pressed ? d2[7:4]   : 4'hF), .seg_out(seg3));

    hex7seg seg4_inst(.hex_in(key_press_count[3:0]), .seg_out(seg4));
    hex7seg seg5_inst(.hex_in(key_press_count[7:4]), .seg_out(seg5));

endmodule