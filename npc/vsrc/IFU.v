module IFU #(DATA_LEN = 32) (
    input clk,
    input reset,
    input [DATA_LEN-1:0] pc,
    input inst_done,
    output [DATA_LEN-1:0] inst,
    output inst_valid,

    output arvalid,
    input arready,
    output [DATA_LEN-1:0] araddr,

    input rvalid,
    output rready,
    input [DATA_LEN-1:0] rdata,
    input [1:0] rresp
);

    localparam [1:0] IFU_IDLE = 2'd0;
    localparam [1:0] IFU_AR   = 2'd1;
    localparam [1:0] IFU_R    = 2'd2;
    localparam [1:0] IFU_HOLD = 2'd3;

    reg [1:0] state, next_state;
    reg [DATA_LEN-1:0] ifu_rdata;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [7:0] lfsr_out;
    /* verilator lint_on UNUSEDSIGNAL */
    // Random issue delay exercises the slave.
    reg [2:0] req_delay;

    wire ar_fire = arvalid && arready;
    wire r_fire  = rvalid && rready;

    always @(posedge clk) begin
        if (reset) state <= IFU_IDLE;
        else       state <= next_state;
    end

    always @(posedge clk) begin
        if (reset)                               req_delay <= 0;
        else if (state == IFU_HOLD && inst_done) req_delay <= lfsr_out[2:0];
        else if (state == IFU_IDLE && req_delay != 0) req_delay <= req_delay - 1;
    end

    LFSR #(8'h5a) lfsr (
        .clk(clk),
        .reset(reset),
        .out(lfsr_out)
    );

    assign inst = ifu_rdata;
endmodule
