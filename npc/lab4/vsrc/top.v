module top(
    input [7:0] in,
    input clk,
    input rst,
    input [2:0] sel,
    output [6:0] out1,
    output [6:0] out2
);  
    wire [7:0] seg;

    shiftright sr1(
        .in(in), 
        .sel(sel), 
        .rst(rst),
        .sin(seg[4] ^ seg[3] ^ seg[2] ^ seg[0]),
        .clk(clk), 
        .out(seg)
    );
    
    hex7seg seg0(
        .hex_in (seg[3:0]),
        .seg_out (out1)
    );
    
    hex7seg seg1(
        .hex_in (seg[7:4]),
        .seg_out (out2)
    );

endmodule