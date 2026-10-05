module IFU #(DATA_LEN = 32) (
    input clk,
    input reset,
    input [DATA_LEN-1:0] pc,
    input inst_done,
    output [DATA_LEN-1:0] inst,
    output inst_valid,

    output req_valid,
    output [DATA_LEN-1:0] req_addr,
    input rvalid,
    input [DATA_LEN-1:0] rdata
);

    localparam [1:0] IFU_IDLE = 2'd0;
    localparam [1:0] IFU_WAIT = 2'd1;
    localparam [1:0] IFU_HOLD = 2'd2;

    reg [1:0] state, next_state;
    reg [DATA_LEN-1:0] ifu_rdata;

    always @(*) begin
        case (state)
            IFU_IDLE: next_state = IFU_WAIT;
            IFU_WAIT: next_state = rvalid ? IFU_HOLD : IFU_WAIT;
            IFU_HOLD: next_state = inst_done ? IFU_IDLE : IFU_HOLD;
            default:  next_state = IFU_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (reset) state <= IFU_IDLE;
        else       state <= next_state;
    end

    // rdata is only valid in the rvalid cycle, so latch it there and hold it
    // through HOLD. Clear on retire so IDLE and WAIT decode to mem_en=0.
    always @(posedge clk) begin
        if (reset)                                     ifu_rdata <= 0;
        else if (state == IFU_WAIT && rvalid)          ifu_rdata <= rdata;
        else if (state == IFU_HOLD && inst_done)       ifu_rdata <= 0;
    end

    // No request during reset: PC is not reset until the same edge, so its
    // value would point outside pmem.
    assign req_valid = !reset && state == IFU_IDLE;
    assign req_addr = pc;

    assign inst = ifu_rdata;
    assign inst_valid = (state == IFU_HOLD);
endmodule
