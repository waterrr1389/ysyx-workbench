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

    output reg arvalid,
    input arready,
    output [DATA_LEN-1:0] araddr,

    input rvalid,
    output reg rready,
    input [DATA_LEN-1:0] rdata,
    input [1:0] rresp,

    output reg awvalid,
    input awready,
    output [DATA_LEN-1:0] awaddr,

    output reg wvalid,
    input wready,
    output [DATA_LEN-1:0] wdata,
    output [3:0] wstrb,

    input bvalid,
    output reg bready,
    input [1:0] bresp
);

    localparam [2:0] LSU_IDLE = 3'd0;
    localparam [2:0] LSU_AW_W = 3'd1;  // Send both the write address and data.
    localparam [2:0] LSU_AW   = 3'd2;  // Data accepted; still waiting to send the address.
    localparam [2:0] LSU_W    = 3'd3;  // Address accepted; still waiting to send the data.
    localparam [2:0] LSU_B    = 3'd4;
    localparam [2:0] LSU_AR   = 3'd5;
    localparam [2:0] LSU_R    = 3'd6;

    reg [2:0] state, next_state;
    reg [DATA_LEN-1:0] addr_q;
    reg [DATA_LEN-1:0] wdata_q;
    reg [3:0] wstrb_q;
    reg [DATA_LEN-1:0] rdata_q;
    reg done_q;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [7:0] lfsr_out;
    /* verilator lint_on UNUSEDSIGNAL */
    // Wait 0-7 extra cycles before sending a request to vary its timing.
    reg [2:0] req_delay;

    wire ar_fire = arvalid && arready;
    wire r_fire  = rvalid && rready;
    wire aw_fire = awvalid && awready;
    wire w_fire  = wvalid && wready;
    wire b_fire  = bvalid && bready;
    wire start_req = state == LSU_IDLE && !done_q && inst_valid && mem_en && req_delay == 0;

    always @(posedge clk) begin
        if (reset) state <= LSU_IDLE;
        else       state <= next_state;
    end

    // Finish after the response is saved. Do not send the same request again
    // while the CPU is using this pulse to advance to the next instruction.
    always @(posedge clk) begin
        if (reset) done_q <= 1'b0;
        else       done_q <= r_fire || b_fire;
    end

    // Save the address and data before sending the request.
    // Keep them unchanged while the slave is not ready.
    always @(posedge clk) begin
        if (reset) begin
            addr_q <= 0;
            wdata_q <= 0;
            wstrb_q <= 0;
            rdata_q <= 0;
        end else begin
            if (start_req) begin
                addr_q <= mem_addr;
                if (mem_we) begin
                    wdata_q <= mem_wdata;
                    wstrb_q <= mem_wmask;
                end
            end
            if (r_fire) begin
                assert (rresp == 2'b00)
                    else $fatal(1, "LSU read response is not OKAY");
                rdata_q <= rdata;
            end
            if (b_fire) begin
                assert (bresp == 2'b00)
                    else $fatal(1, "LSU write response is not OKAY");
            end
        end
    end

    // Pick a new delay whenever an instruction finishes.
    // Count down only when a load or store is waiting to start.
    always @(posedge clk) begin
        if (reset)          req_delay <= 0;
        else if (inst_done) req_delay <= lfsr_out[2:0];
        else if (state == LSU_IDLE && inst_valid && mem_en && req_delay != 0)
            req_delay <= req_delay - 1;
    end

    always @(*) begin
        next_state = state;
        case (state)
            LSU_IDLE: begin
                if (start_req)
                    next_state = mem_we ? LSU_AW_W : LSU_AR;
            end
            LSU_AW_W: begin
                if (aw_fire && w_fire)
                    next_state = LSU_B;
                else if (aw_fire)
                    next_state = LSU_W;
                else if (w_fire)
                    next_state = LSU_AW;
            end
            LSU_AW: begin
                if (aw_fire)
                    next_state = LSU_B;
            end
            LSU_W: begin
                if (w_fire)
                    next_state = LSU_B;
            end
            LSU_B: begin
                if (b_fire)
                    next_state = LSU_IDLE;
            end
            LSU_AR: begin
                if (ar_fire)
                    next_state = LSU_R;
            end
            LSU_R: begin
                if (r_fire)
                    next_state = LSU_IDLE;
            end
            default: begin
                next_state = LSU_IDLE;
            end
        endcase
    end

    always @(*) begin
        arvalid = 1'b0;
        rready = 1'b0;
        awvalid = 1'b0;
        wvalid = 1'b0;
        bready = 1'b0;

        if (!reset) begin
            case (state)
                LSU_AW_W: begin
                    awvalid = 1'b1;
                    wvalid = 1'b1;
                end
                LSU_AW: begin
                    awvalid = 1'b1;
                end
                LSU_W: begin
                    wvalid = 1'b1;
                end
                LSU_B: begin
                    bready = 1'b1;
                end
                LSU_AR: begin
                    arvalid = 1'b1;
                end
                LSU_R: begin
                    rready = 1'b1;
                end
                default: begin
                end
            endcase
        end
    end

    assign araddr = addr_q;
    assign awaddr = addr_q;
    assign wdata = wdata_q;
    assign wstrb = wstrb_q;

    assign mem_rdata = rdata_q;
    assign inst_done = !reset && inst_valid &&
                       state == LSU_IDLE && (!mem_en || done_q);

    LFSR #(8'hc3) lfsr (
        .clk(clk),
        .reset(reset),
        .out(lfsr_out)
    );
endmodule
