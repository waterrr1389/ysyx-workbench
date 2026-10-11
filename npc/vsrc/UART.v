// AXI4-Lite slave with a single write-only TX register. The low byte of each
// write is printed as a character. The Xbar answers reads to this address
// range with DECERR, so the read channels never see a request.
module UART #(DATA_LEN = 32) (
    input clk,
    input reset,

    /* verilator lint_off UNUSEDSIGNAL */
    input arvalid,
    output arready,
    input [DATA_LEN-1:0] araddr,

    output rvalid,
    input rready,
    output [DATA_LEN-1:0] rdata,
    output [1:0] rresp,

    input awvalid,
    output awready,
    input [DATA_LEN-1:0] awaddr,  // only one register, so the address is not decoded

    input wvalid,
    output wready,
    input [DATA_LEN-1:0] wdata,
    input [3:0] wstrb,
    /* verilator lint_on UNUSEDSIGNAL */

    output bvalid,
    input bready,
    output [1:0] bresp
);

    localparam UART_IDLE = 1'b0;
    localparam UART_B    = 1'b1;

    reg state;

    // Take AW and W in the same cycle, so there is no half-received state.
    wire w_fire = !reset && state == UART_IDLE && awvalid && wvalid;
    wire b_fire = bvalid && bready;

    always @(posedge clk) begin
        if (reset) begin
            state <= UART_IDLE;
        end else begin
            case (state)
                UART_IDLE: if (w_fire) state <= UART_B;
                UART_B:    if (b_fire) state <= UART_IDLE;
            endcase
        end
    end

    // Print once per write, on the handshake edge.
    always @(posedge clk) begin
        if (w_fire && wstrb[0]) $write("%c", wdata[7:0]);
    end

    assign awready = w_fire;
    assign wready  = w_fire;
    assign bvalid  = !reset && state == UART_B;
    assign bresp   = 2'b00;  // OKAY

    assign arready = 1'b0;
    assign rvalid  = 1'b0;
    assign rdata   = {DATA_LEN{1'b0}};
    assign rresp   = 2'b00;
endmodule
