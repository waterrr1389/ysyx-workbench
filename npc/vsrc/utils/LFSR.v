// 8-bit maximal-length Fibonacci LFSR (taps 8,6,5,4), advancing every cycle.
// SEED must be non-zero: the all-zero state never leaves itself.
module LFSR #(SEED = 8'h01) (
    input clk,
    input reset,
    output reg [7:0] out
);
    wire feedback = out[7] ^ out[5] ^ out[4] ^ out[3];

    always @(posedge clk) begin
        if (reset) out <= SEED;
        else       out <= {out[6:0], feedback};
    end
endmodule
