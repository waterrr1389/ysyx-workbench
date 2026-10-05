module IFU #(DATA_LEN = 32) (
    input clk,
    input reset,
    input [DATA_LEN-1:0] pc,
    input inst_done,
    output [DATA_LEN-1:0] inst,
    output inst_valid,

    output reqValid,
    input reqReady,
    output [DATA_LEN-1:0] addr,
    input rrespValid,
    output rrespReady,
    input [DATA_LEN-1:0] rdata
);

    localparam [1:0] IFU_IDLE = 2'd0;
    localparam [1:0] IFU_WAIT = 2'd1;
    localparam [1:0] IFU_HOLD = 2'd2;

    reg [1:0] state, next_state;
    reg [DATA_LEN-1:0] ifu_rdata;

    always @(*) begin
        case (state)
            IFU_IDLE: next_state = reqReady ? IFU_WAIT : IFU_IDLE;
            IFU_WAIT: next_state = rrespValid ? IFU_HOLD : IFU_WAIT;
            IFU_HOLD: next_state = inst_done ? IFU_IDLE : IFU_HOLD;
            default:  next_state = IFU_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (reset) state <= IFU_IDLE;
        else       state <= next_state;
    end

    // rdata is only valid in the handshake cycle, so latch it there and hold
    // it through HOLD. Clear on retire so IDLE and WAIT decode to mem_en=0.
    always @(posedge clk) begin
        if (reset)                               ifu_rdata <= 0;
        else if (state == IFU_WAIT && rrespValid) ifu_rdata <= rdata;
        else if (state == IFU_HOLD && inst_done)  ifu_rdata <= 0;
    end

    // No request during reset: PC is not reset until the same edge, so its
    // value would point outside pmem. While waiting for reqReady the request
    // stays stable: PC only changes on inst_done, which cannot happen in IDLE.
    assign reqValid = !reset && state == IFU_IDLE;
    assign addr = pc;
    assign rrespReady = (state == IFU_WAIT);

    assign inst = ifu_rdata;
    assign inst_valid = (state == IFU_HOLD);
endmodule
