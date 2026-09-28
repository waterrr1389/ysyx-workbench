module IFU #(DATA_LEN = 32) (
    input clk,
    input reset,
    input [DATA_LEN-1:0] pc,
    output [DATA_LEN-1:0] inst,
    output inst_valid
);

    import "DPI-C" function int pmem_read(input int raddr);

    localparam [0:0] IFU_IDLE = 1'b0;
    localparam [0:0] IFU_WAIT = 1'b1;

    reg [0:0] state, next_state;
    reg [DATA_LEN-1:0] ifu_rdata;

    always @(*) begin
        case (state)
            IFU_IDLE: next_state = IFU_WAIT;
            IFU_WAIT: next_state = IFU_IDLE;
            default:  next_state = IFU_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (reset) state <= IFU_IDLE;
        else       state <= next_state;
    end

    // Read only while issuing the request. Skipping reset matters: PC is not
    // reset until this same edge, so reading then would hit an out-of-pmem address.
    always @(posedge clk) begin
        if (!reset && state == IFU_IDLE) ifu_rdata <= pmem_read(pc);
        else                             ifu_rdata <= 0;
    end

    assign inst = ifu_rdata;
    assign inst_valid = (state == IFU_WAIT);
endmodule
