module top(
    input clk,
    input reset,
    input ps2_clk,
    input ps2_data,
    output overflow,
    output[5:0] dot,
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


    parameter S0 = 2'b00; // 初始状态
    parameter S1 = 2'b01; // 接收到ready信号，读取数据
    parameter S2 = 2'b10; // 读取完毕,拉低nextdata_n一个周期

    reg [1:0] state, nextstate;

    always@(posedge clk) begin
        if(reset) state <= S0;
        else      state <= nextstate;
    end

    // 状态转移逻辑(Mealey型状态机)
    always@(*) begin
        case (state) 
        S0: if (ready) nextstate = S1; else nextstate = S0;
        S1: nextstate = S2;
        S2: nextstate = S0;
        default: nextstate = S0;
        endcase
    end

    // 接收到ready信号后, 进入状态S1, 读取数据,确认读取完毕后,进入状态S2,将nextdata_n置0一个周期
    assign nextdata_n = (state == S2) ? 1'b0 : 1'b1;

    reg[7:0] buffer[2:0];
    reg[7:0] key_press_count;

    always@(posedge clk) begin
        if (reset) begin
            buffer[0] <= 8'h00;
            buffer[1] <= 8'h00;
            buffer[2] <= 8'h00;
        end
        else if (state == S1) begin
            buffer[2] <= buffer[1];
            buffer[1] <= buffer[0];
            buffer[0] <= data;
        end
    end


    reg key_is_pressed;
    always @(posedge clk) begin
        if (reset) begin
            key_is_pressed <= 1'b0;
        end
        // S2状态表示S1刚刚完成接收, buffer[0] 和 buffer[1] 都是最新的
        else if (state == S2) begin
            if (buffer[1] == 8'hF0) begin
                // 上一个字节是F0, 表示当前字节(buffer[0])是断码的第二字节
                // 按键已松开
                key_is_pressed <= 1'b0;
            end
            else if (buffer[0] != 8'hF0) begin
                // 当前字节不是F0, 且上一个字节也不是F0
                // 这是一个通码, 按键被按下
                key_is_pressed <= 1'b1;
            end
            // 如果 buffer[0] == 8'hF0, 什么也不做, 等待断码的第二个字节
        end
    end

    //count logic
    wire release_detected = (buffer[1] == 8'hF0);
    reg release_detected_dly;

    always @(posedge clk) begin
        if (reset) release_detected_dly <= 1'b0;
        else       release_detected_dly <= release_detected;
    end

    //上一个周期为0,说明按下;该周期为1,count_event转为1,说明检测到一次松开
    wire count_event = release_detected && !release_detected_dly;
    
    always @(posedge clk) begin
        if (reset) key_press_count <= 8'h00;
        else if (count_event) key_press_count <= key_press_count + 1;
    end


    //display logic
    wire[7:0] ascii;
    MuxKeyWithDefault #(4, 8, 8) i0 (.out(ascii), .key(buffer[0]), .default_out(0), 
    .lut({ 
        8'h1c, 8'h61, //a
        8'h1b, 8'h73, //w
        8'h23, 8'h64,  //d
        8'h1d, 8'h77 //s
    }));
    
    
    wire seg_en = key_is_pressed;

    hex7seg seg0_inst(.en(seg_en), .hex_in(buffer[0][3:0]), .seg_out(seg0));
    hex7seg seg1_inst(.en(seg_en), .hex_in(buffer[0][7:4]), .seg_out(seg1));
    hex7seg seg2_inst(.en(seg_en), .hex_in(ascii[3:0]), .seg_out(seg2));
    hex7seg seg3_inst(.en(seg_en), .hex_in(ascii[7:4]), .seg_out(seg3));

    hex7seg seg4_inst(.en(1'b1), .hex_in(key_press_count[3:0]), .seg_out(seg4));
    hex7seg seg5_inst(.en(1'b1), .hex_in(key_press_count[7:4]), .seg_out(seg5));

endmodule