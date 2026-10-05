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

    output req_valid,
    output [DATA_LEN-1:0] req_addr,
    output req_wen,
    output [DATA_LEN-1:0] req_wdata,
    output [3:0] req_wmask,
    input rvalid,
    input [DATA_LEN-1:0] rdata,
    input bvalid
);

    localparam [1:0] LSU_IDLE  = 2'd0;
    localparam [1:0] LSU_RWAIT = 2'd1;
    localparam [1:0] LSU_WWAIT = 2'd2;

    reg [1:0] state, next_state;

    // Issue only from IDLE, so a request is sent once per instruction even
    // though inst_valid stays high until inst_done.
    assign req_valid = !reset && state == LSU_IDLE && inst_valid && mem_en;

    always @(*) begin
        case (state)
            LSU_IDLE:  next_state = !req_valid ? LSU_IDLE :
                                    mem_we     ? LSU_WWAIT : LSU_RWAIT;
            LSU_RWAIT: next_state = rvalid ? LSU_IDLE : LSU_RWAIT;
            LSU_WWAIT: next_state = bvalid ? LSU_IDLE : LSU_WWAIT;
            default:   next_state = LSU_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (reset) state <= LSU_IDLE;
        else       state <= next_state;
    end

    assign req_addr  = mem_addr;
    assign req_wen   = mem_we;
    assign req_wdata = mem_wdata;
    assign req_wmask = mem_wmask;

    // Not latched: load data is consumed in the rvalid cycle, which is also
    // the commit cycle.
    assign mem_rdata = rdata;

    assign inst_done = (inst_valid && !mem_en)
                    || (state == LSU_RWAIT && rvalid)
                    || (state == LSU_WWAIT && bvalid);
endmodule
