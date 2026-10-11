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
    reg [DATA_LEN-1:0] addr_q;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [7:0] lfsr_out;
    /* verilator lint_on UNUSEDSIGNAL */
    
    // Wait 0-7 extra cycles before starting the next fetch.
    reg [2:0] req_delay;

    wire ar_fire = arvalid && arready;
    wire r_fire  = rvalid && rready;

    always @(posedge clk) begin
        if (reset) state <= IFU_IDLE;
        else       state <= next_state;
    end

    // Save the PC before sending the request. Keep the instruction until it finishes.
    always @(posedge clk) begin
        if (reset) begin
            addr_q <= 0;
            ifu_rdata <= 0;
        end else begin
            if (state == IFU_IDLE && req_delay == 0)
                addr_q <= pc;
            if (r_fire) begin
                assert (rresp == 2'b00)
                    else $fatal(1, "IFU read response is not OKAY");
                ifu_rdata <= rdata;
            end
        end
    end

    always @(posedge clk) begin
        if (reset) req_delay <= 0;
        else if (state == IFU_HOLD && inst_done) req_delay <= lfsr_out[2:0];
        else if (state == IFU_IDLE && req_delay != 0) req_delay <= req_delay - 1;
    end

    always @(*) begin
        next_state = state;
        case (state)
            IFU_IDLE: begin
                if (req_delay == 0)
                    next_state = IFU_AR;
            end
            IFU_AR: begin
                if (ar_fire)
                    next_state = IFU_R;
            end
            IFU_R: begin
                if (r_fire)
                    next_state = IFU_HOLD;
            end
            IFU_HOLD: begin
                if (inst_done)
                    next_state = IFU_IDLE;
            end
            default: begin
                next_state = IFU_IDLE;
            end
        endcase
    end

    LFSR #(8'h5a) lfsr (
        .clk(clk),
        .reset(reset),
        .out(lfsr_out)
    );

    assign inst = ifu_rdata;
    assign inst_valid = !reset && state == IFU_HOLD;
    assign arvalid = !reset && state == IFU_AR;
    assign araddr = addr_q;
    assign rready = !reset && state == IFU_R;
endmodule
