module shiftright(
    input [7:0] in,
    input [2:0] sel,
    input sin,
    input rst,
    input clk,
    output reg [7:0]out
);
    always@(posedge clk or posedge rst) begin
        if (rst) begin
            out <= 8'h01;
        end else begin
            case(sel)
                3'b000: out <= 8'b00000000;
                3'b001: out <= in;
                3'b010: out <= {1'b0, out[7:1]};
                3'b011: out <= {out[6:0], 1'b0};
                3'b100: out <= {out[7], out[7:1]};
                3'b101: out <= {sin, out[7:1]};
                3'b110: out <= {out[0], out[7:1]};
                3'b111: out <= {out[6:0], out[7]};
                default: out <= out;
            endcase
        end
    end

endmodule