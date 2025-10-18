module top (
    input [7:0] in,
    output reg [2:0] out,
    output s,
    output reg [6:0] digital
);
    wire [2:0] encoder_out;
    wire encoder_s;
    
    encoder en1 (
        .in(in), 
        .out(encoder_out), 
        .s(encoder_s)
    );

    bcd7seg bcd1 (
        .b({1'b0, encoder_out}), 
        .h(digital)
    );

    assign out = encoder_out;
    assign s   = encoder_s;

endmodule


module bcd7seg (
    input  [3:0] b,
    output reg [6:0] h 
);
    always @(*) begin
        case (b)
            //低电平有效
            4'd0: h = 7'b1000000; // 0
            4'd1: h = 7'b1111001; // 1
            4'd2: h = 7'b0100100; // 2
            4'd3: h = 7'b0110000; // 3
            4'd4: h = 7'b0011001; // 4
            4'd5: h = 7'b0010010; // 5
            4'd6: h = 7'b0000010; // 6
            4'd7: h = 7'b1111000; // 7
            4'd8: h = 7'b0000000; // 8
            4'd9: h = 7'b0010000; // 9
            default: h = 7'b0000000;
        endcase
    end

endmodule

// module decoder(
//     input [2:0] in,
//     output reg [15:0] out
// );
//     always@(*) begin
//         case(in)
//             3'b000: out = 16'b00000000;
//             3'b001: out = 16'b00000010;
//             3'b010: out = 16'b00000100;
//             3'b011: out = 16'b00001000;
//             3'b100: out = 16'b00010000;
//             3'b101: out = 16'b00100000;
//             3'b110: out = 16'b01000000;
//             3'b111: out = 16'b10000000;
//             default: out = 16'b0;
//         endcase 
//     end

// endmodule

//优先编码器
module encoder(
    input [7:0] in,
    output reg [2:0] out,
    output s
);
    always@(*) begin
        casez(in[7:0])
            8'b1zzzzzzz: out = 3'b111;
            8'b01zzzzzz: out = 3'b110;
            8'b001zzzzz: out = 3'b101;
            8'b0001zzzz: out = 3'b100;
            8'b00001zzz: out = 3'b011;
            8'b000001zz: out = 3'b010;
            8'b0000001z: out = 3'b001;
            8'b00000001: out = 3'b000;
            default: out = 3'b000;
        endcase
    end

    assign s = |in;
endmodule