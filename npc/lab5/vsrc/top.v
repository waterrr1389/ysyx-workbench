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

    assign dot = 6'b1;
    
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

    always@(posedge clk) begin
        if(reset) state <= S0;
        else      state <= nextstate;
    end

    always@(*) begin
        case (state) 
        S0: if (ready) nextstate = S1; else nextstate = S0;
        S1: nextstate = S0;
        default: nextstate = S0;
        endcase
    end

    assign nextdata_n = (state == S1) ? 1'b0 : 1'b1;
    reg[7:0] buffer[2:0];
    reg[7:0] key_press_count;

    always@(posedge clk) begin
        if (state == S1) buffer <=  {buffer[1:0], data};   
    end

    //count logic
    //上一个数据是F0,说明是断码,此时键盘松开
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
    
    
    wire seg_en = !release_detected;

    hex7seg seg0_inst(.en(seg_en), .hex_in(buffer[0][3:0]), .seg_out(seg0));
    hex7seg seg1_inst(.en(seg_en), .hex_in(buffer[0][7:4]), .seg_out(seg1));
    hex7seg seg2_inst(.en(seg_en), .hex_in(ascii[3:0]), .seg_out(seg2));
    hex7seg seg3_inst(.en(seg_en), .hex_in(ascii[7:4]), .seg_out(seg3));

    hex7seg seg4_inst(.en(1'b1), .hex_in(key_press_count[3:0]), .seg_out(seg4));
    hex7seg seg5_inst(.en(1'b1), .hex_in(key_press_count[7:4]), .seg_out(seg5));

endmodule