module LSU #(DATA_LEN = 32) (
    input clk,
    input reset,
    input inst_valid,
    input mem_en,
    input mem_we,
    input [DATA_LEN-1:0] mem_addr,
    input [DATA_LEN-1:0] mem_wdata,
    input [3:0] mem_wmask,
    output [DATA_LEN-1:0] mem_rdata,
    output inst_done,

    output reqValid,
    input reqReady,
    output [DATA_LEN-1:0] addr,
    output wen,
    output [DATA_LEN-1:0] wdata,
    output [3:0] wmask,
    input rrespValid,
    output rrespReady,
    input [DATA_LEN-1:0] rdata,
    input wrespValid,
    output wrespReady
);

    localparam [1:0] LSU_IDLE  = 2'd0;
    localparam [1:0] LSU_RWAIT = 2'd1;
    localparam [1:0] LSU_WWAIT = 2'd2;

    reg [1:0] state, next_state;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [7:0] lfsr_out;  // only the low bits pick the delay
    /* verilator lint_on UNUSEDSIGNAL */
    // Random 0-7 cycles before reqValid rises, to exercise the slave under
    // arbitrary request timing. Once raised, reqValid holds until handshake.
    reg [2:0] req_delay;

    // Issue only from IDLE, so a request is sent once per instruction even
    // though inst_valid stays high until inst_done. While waiting for
    // reqReady the request stays stable: the IFU holds the instruction and
    // no state commits before inst_done.
    assign reqValid = !reset && state == LSU_IDLE && inst_valid && mem_en && req_delay == 0;

    // Reload per instruction; count down only while a memory access is pending.
    always @(posedge clk) begin
        if (reset)          req_delay <= 0;
        else if (inst_done) req_delay <= lfsr_out[2:0];
        else if (state == LSU_IDLE && inst_valid && mem_en && req_delay != 0)
            req_delay <= req_delay - 1;
    end

    LFSR #(8'hc3) lfsr (
        .clk(clk),
        .reset(reset),
        .out(lfsr_out)
    );

    always @(*) begin
        case (state)
            LSU_IDLE:  next_state = !(reqValid && reqReady) ? LSU_IDLE :
                                    mem_we ? LSU_WWAIT : LSU_RWAIT;
            LSU_RWAIT: next_state = rrespValid ? LSU_IDLE : LSU_RWAIT;
            LSU_WWAIT: next_state = wrespValid ? LSU_IDLE : LSU_WWAIT;
            default:   next_state = LSU_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (reset) state <= LSU_IDLE;
        else       state <= next_state;
    end

    assign addr  = mem_addr;
    assign wen   = mem_we;
    assign wdata = mem_wdata;
    assign wmask = mem_wmask;
    assign rrespReady = (state == LSU_RWAIT);
    assign wrespReady = (state == LSU_WWAIT);

    // Not latched: load data is consumed in the handshake cycle, which is
    // also the commit cycle.
    assign mem_rdata = rdata;

    assign inst_done = (inst_valid && !mem_en)
                    || (state == LSU_RWAIT && rrespValid)
                    || (state == LSU_WWAIT && wrespValid);
endmodule
