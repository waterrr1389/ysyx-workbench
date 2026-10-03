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
    output inst_done
);

    import "DPI-C" function int pmem_read(input int raddr);
    import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

    localparam [0:0] LSU_IDLE = 1'b0;
    localparam [0:0] LSU_WAIT = 1'b1;

    reg [0:0] state, next_state;
    reg [DATA_LEN-1:0] lsu_rdata;

    // Issue only from IDLE, so a request is sent once per instruction even
    // though inst_valid stays high until inst_done.
    wire req = (state == LSU_IDLE) && inst_valid && mem_en;

    always @(*) begin
        case (state)
            LSU_IDLE: next_state = req ? LSU_WAIT : LSU_IDLE;
            LSU_WAIT: next_state = LSU_IDLE;
            default:  next_state = LSU_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (reset) state <= LSU_IDLE;
        else       state <= next_state;
    end

    // lsu_rdata is the one-cycle memory latency: sampled at the end of the
    // request cycle, valid during WAIT.
    always @(posedge clk) begin
        if (!reset && req && !mem_we) lsu_rdata <= pmem_read(mem_addr);
        else                          lsu_rdata <= 0;
    end

    always @(posedge clk) begin
        if (!reset && req && mem_we) pmem_write(mem_addr, mem_wdata, {4'b0, mem_wmask});
    end

    assign mem_rdata = lsu_rdata;
    // Non-memory instructions finish in the same cycle; memory ones in WAIT.
    assign inst_done = (inst_valid && !mem_en) || (state == LSU_WAIT);
endmodule
