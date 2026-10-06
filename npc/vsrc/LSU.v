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

    output arvalid,
    input arready,
    output [DATA_LEN-1:0] araddr,

    input rvalid,
    output rready,
    input [DATA_LEN-1:0] rdata,
    input [1:0] rresp,

    output awvalid,
    input awready,
    output [DATA_LEN-1:0] awaddr,

    output wvalid,
    input wready,
    output [DATA_LEN-1:0] wdata,
    output [3:0] wstrb,

    input bvalid,
    output bready,
    input [1:0] bresp
);

    localparam [2:0] LSU_IDLE = 3'd0;
    localparam [2:0] LSU_AW_W = 3'd1;  // both AW and W pending
    localparam [2:0] LSU_AW   = 3'd2;  // W done, AW pending
    localparam [2:0] LSU_W    = 3'd3;  // AW done, W pending
    localparam [2:0] LSU_B    = 3'd4;
    localparam [2:0] LSU_AR   = 3'd5;
    localparam [2:0] LSU_R    = 3'd6;

    reg [2:0] state, next_state;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [7:0] lfsr_out;
    /* verilator lint_on UNUSEDSIGNAL */
    // Random issue delay exercises the slave.
    reg [2:0] req_delay;

    wire ar_fire = arvalid && arready;
    wire r_fire  = rvalid && rready;
    wire aw_fire = awvalid && awready;
    wire w_fire  = wvalid && wready;
    wire b_fire  = bvalid && bready;

    always @(posedge clk) begin
        if (reset) state <= LSU_IDLE;
        else       state <= next_state;
    end

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
endmodule
