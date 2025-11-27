module top(
    input [3:0] a,
    input [3:0] b,
    input [2:0] sel,
    output reg OF,
    output reg CF,
    output reg [3:0] out
);
    wire[4:0] sub_tmp;
    wire sub_OF;
    wire[3:0] sub_b = ~b;
    assign sub_tmp = a + sub_b + 1;
    assign sub_OF = (a[3] == sub_b[3]) & (sub_tmp[3] != a[3]);

    always@(*) begin
        out = 4'b0000;
        CF = 1'b0;
        OF = 1'b0;

        case(sel)
            3'b000: begin
                {CF, out} = a + b;
                OF = (a[3] == b[3]) & (out[3] != a[3]);
            end 
            3'b001: begin
                out = sub_tmp[3:0];
                OF = sub_OF;
                CF = ~sub_tmp[4];
            end
            3'b010: begin
                out = ~a;
            end
            3'b011: begin
                out = a & b;
            end
            3'b100: begin
                out = a | b;
            end
            3'b101: begin
                out = a ^ b;
            end
            3'b110: begin
                if ((sub_tmp[3] ^ sub_OF) == 1'b1) begin
                    out = 4'b0001;              
                end else begin
                    out = 4'b0000;
                end
            end
            3'b111: begin
                if (a == b) begin
                    out = 4'b0001;
                end else begin
                    out = 4'b0000;
                end
            end
        endcase
    end

endmodule