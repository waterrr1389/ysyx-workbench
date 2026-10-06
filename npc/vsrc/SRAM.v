module SRAM #(DATA_LEN = 32) (
    input clk,
    input reset,

    input arvalid,
    output arready,
    input [DATA_LEN-1:0] araddr,

    output rvalid,
    input rready,
    output reg [DATA_LEN-1:0] rdata,
    output [1:0] rresp,

    input awvalid,
    output awready,
    input [DATA_LEN-1:0] awaddr,

    input wvalid,
    output wready,
    input [DATA_LEN-1:0] wdata,
    input [3:0] wstrb,

    output bvalid,
    input bready,
    output [1:0] bresp
);

    import "DPI-C" function int pmem_read(input int raddr);
    import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

    localparam [2:0] SRAM_IDLE = 3'd0;
    localparam [2:0] SRAM_AW   = 3'd1;  // AW received, waiting for W
    localparam [2:0] SRAM_W    = 3'd2;  // W received, waiting for AW
    localparam [2:0] SRAM_R    = 3'd3;
    localparam [2:0] SRAM_B    = 3'd4;

    reg [2:0] state, next_state;

    reg [DATA_LEN-1:0] awaddr_q;
    reg [DATA_LEN-1:0] wdata_q;
    reg [3:0] wstrb_q;

    wire ar_fire = arvalid && arready;
    wire r_fire  = rvalid && rready;
    wire aw_fire = awvalid && awready;
    wire w_fire  = wvalid && wready;
    wire b_fire  = bvalid && bready;

    always @(posedge clk) begin
        if (reset) state <= SRAM_IDLE;
        else       state <= next_state;
    end

    assign rresp = 2'b00;  // OKAY
    assign bresp = 2'b00;  // OKAY
endmodule
