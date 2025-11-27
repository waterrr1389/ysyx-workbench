module EXU #(DATA_LEN = 1) (
    input [DATA_LEN-1:0] a,
    input [DATA_LEN-1:0] b,
    input [3:0] sel,
    output reg [DATA_LEN-1:0] out
);
    wire[DATA_LEN:0] sub_tmp;
    wire sub_OF;
    wire[DATA_LEN-1:0] sub_b = ~b;
    assign sub_tmp = a + sub_b + 1;
    assign sub_OF = (a[DATA_LEN-1] == sub_b[DATA_LEN-1]) & (sub_tmp[DATA_LEN-1] != a[DATA_LEN-1]);
    
    import "DPI-C" function void ebreak();

    always@(*) begin
        out = 0;

        case(sel)
            4'b0000: begin
                out = a + b;
            end 
            4'b0001: begin
                out = sub_tmp[DATA_LEN-1:0];
            end
            4'b0010: begin
                out = ~a;
            end
            4'b0011: begin
                out = a & b;
            end
            4'b0100: begin
                out = a | b;
            end
            4'b0101: begin
                out = a ^ b;
            end
            4'b0110: begin
                if ((sub_tmp[DATA_LEN-1] ^ sub_OF) == 1'b1) begin
                    out = { {(DATA_LEN-1){1'b0}}, 1'b1};              
                end else begin
                    out = { DATA_LEN{1'b0} };
                end
            end
            4'b0111: begin
                if (a == b) begin
                    out = { {(DATA_LEN-1){1'b0}}, 1'b1};
                end else begin
                    out = { DATA_LEN{1'b0} };
                end
            end
            4'b1000: begin
                ebreak();
            end
            default: begin
                out = {DATA_LEN{1'b0}};
            end
        endcase
    end

endmodule
