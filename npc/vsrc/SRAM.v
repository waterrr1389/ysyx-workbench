// SimpleBus slave backed by pmem. The access happens on the request
// handshake edge; DELAY extra cycles are then spent in BUSY before the
// response is offered.
module SRAM #(DATA_LEN = 32, DELAY = 0) (
    input clk,
    input reset,

    input reqValid,
    output reqReady,
    input [DATA_LEN-1:0] addr,
    input wen,
    input [DATA_LEN-1:0] wdata,
    input [3:0] wmask,
    output rrespValid,
    input rrespReady,
    output reg [DATA_LEN-1:0] rdata,
    output wrespValid,
    input wrespReady
);

    import "DPI-C" function int pmem_read(input int raddr);
    import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

    localparam [1:0] SRAM_IDLE = 2'd0;
    localparam [1:0] SRAM_BUSY = 2'd1;
    localparam [1:0] SRAM_RESP = 2'd2;

    reg [1:0] state, next_state;
    reg [7:0] delay_cnt;
    // Selects the response channel; the rest of the request is consumed on
    // the handshake edge and need not be kept.
    reg resp_is_write;

    wire req_fire  = !reset && reqValid && reqReady;
    wire resp_fire = resp_is_write ? wrespReady : rrespReady;

    always @(*) begin
        case (state)
            SRAM_IDLE: next_state = !req_fire ? SRAM_IDLE :
                                    DELAY == 0 ? SRAM_RESP : SRAM_BUSY;
            SRAM_BUSY: next_state = delay_cnt == 1 ? SRAM_RESP : SRAM_BUSY;
            SRAM_RESP: next_state = resp_fire ? SRAM_IDLE : SRAM_RESP;
            default:   next_state = SRAM_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (reset) state <= SRAM_IDLE;
        else       state <= next_state;
    end

    always @(posedge clk) begin
        if (req_fire)                delay_cnt <= DELAY[7:0];
        else if (state == SRAM_BUSY) delay_cnt <= delay_cnt - 1;
    end

    // rdata must stay stable through RESP until rrespReady.
    always @(posedge clk) begin
        if (req_fire) begin
            resp_is_write <= wen;
            if (wen) pmem_write(addr, wdata, {4'b0, wmask});
            else     rdata <= pmem_read(addr);
        end
    end

    assign reqReady   = (state == SRAM_IDLE);
    assign rrespValid = (state == SRAM_RESP) && !resp_is_write;
    assign wrespValid = (state == SRAM_RESP) && resp_is_write;
endmodule
