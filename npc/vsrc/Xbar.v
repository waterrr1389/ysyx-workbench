// AXI4-Lite crossbar from one master port to the SRAM and the UART, chosen by
// address. Unmapped addresses, and reads of the write-only UART, are answered
// here with DECERR.
//
// One transaction at a time, which the Arbiter guarantees: IDLE holds every
// READY low until a request arrives, the decoded route is latched on that
// edge, and the channels are then passed through until the response
// handshake. VALIDs come only from the state and the other side's VALIDs,
// never from READY, so no combinational loop can form.
module Xbar (
    input clk,
    input reset,

    input arvalid,
    output reg arready,
    input [31:0] araddr,
    output reg rvalid,
    input rready,
    output reg [31:0] rdata,
    output reg [1:0] rresp,
    input awvalid,
    output reg awready,
    input [31:0] awaddr,
    input wvalid,
    output reg wready,
    input [31:0] wdata,
    input [3:0] wstrb,
    output reg bvalid,
    input bready,
    output reg [1:0] bresp,

    output sram_arvalid,
    input sram_arready,
    output [31:0] sram_araddr,
    input sram_rvalid,
    output sram_rready,
    input [31:0] sram_rdata,
    input [1:0] sram_rresp,
    output sram_awvalid,
    input sram_awready,
    output [31:0] sram_awaddr,
    output sram_wvalid,
    input sram_wready,
    output [31:0] sram_wdata,
    output [3:0] sram_wstrb,
    input sram_bvalid,
    output sram_bready,
    input [1:0] sram_bresp,

    /* verilator lint_off UNUSEDSIGNAL */
    output uart_arvalid,
    input uart_arready,
    output [31:0] uart_araddr,
    input uart_rvalid,
    output uart_rready,
    input [31:0] uart_rdata,
    input [1:0] uart_rresp,
    /* verilator lint_on UNUSEDSIGNAL */
    output uart_awvalid,
    input uart_awready,
    output [31:0] uart_awaddr,
    output uart_wvalid,
    input uart_wready,
    output [31:0] uart_wdata,
    output [3:0] uart_wstrb,
    input uart_bvalid,
    output uart_bready,
    input [1:0] uart_bresp
);

    localparam [31:0] SRAM_BASE = 32'h8000_0000;
    localparam [31:0] SRAM_SIZE = 32'h0200_0000;
    localparam [31:0] UART_BASE = 32'h1000_0000;
    localparam [31:0] UART_SIZE = 32'h0000_0008;

    localparam [1:0] XBAR_IDLE  = 2'd0;
    localparam [1:0] XBAR_READ  = 2'd1;
    localparam [1:0] XBAR_WRITE = 2'd2;

    localparam [1:0] ROUTE_SRAM = 2'd0;
    localparam [1:0] ROUTE_UART = 2'd1;
    localparam [1:0] ROUTE_ERR  = 2'd2;

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_DECERR = 2'b11;

    reg [1:0] state;
    reg [1:0] route;
    // ROUTE_ERR only: the request has been taken and DECERR is now offered.
    reg err_resp;

    wire in_sram = araddr - SRAM_BASE < SRAM_SIZE;
    wire aw_in_sram = awaddr - SRAM_BASE < SRAM_SIZE;
    wire aw_in_uart = awaddr - UART_BASE < UART_SIZE;

    wire [1:0] read_route  = in_sram ? ROUTE_SRAM : ROUTE_ERR;
    wire [1:0] write_route = aw_in_sram ? ROUTE_SRAM :
                             aw_in_uart ? ROUTE_UART : ROUTE_ERR;

    wire reading = !reset && state == XBAR_READ;
    wire writing = !reset && state == XBAR_WRITE;
    wire r_fire  = rvalid && rready;
    wire b_fire  = bvalid && bready;

    always @(posedge clk) begin
        if (reset) begin
            state <= XBAR_IDLE;
        end else begin
            case (state)
                XBAR_IDLE: begin
                    // A write waits until both AW and W are offered.
                    if (arvalid) begin
                        state <= XBAR_READ;
                        route <= read_route;
                    end else if (awvalid && wvalid) begin
                        state <= XBAR_WRITE;
                        route <= write_route;
                    end
                end
                XBAR_READ:  if (r_fire) state <= XBAR_IDLE;
                XBAR_WRITE: if (b_fire) state <= XBAR_IDLE;
                default:    state <= XBAR_IDLE;
            endcase
        end
    end

    always @(posedge clk) begin
        if (reset || r_fire || b_fire) err_resp <= 1'b0;
        else if (route == ROUTE_ERR && (arready && arvalid || awready && awvalid))
            err_resp <= 1'b1;
    end

    assign sram_arvalid = reading && route == ROUTE_SRAM && arvalid;
    assign sram_araddr  = araddr;
    assign sram_rready  = reading && route == ROUTE_SRAM && rready;
    assign sram_awvalid = writing && route == ROUTE_SRAM && awvalid;
    assign sram_awaddr  = awaddr;
    assign sram_wvalid  = writing && route == ROUTE_SRAM && wvalid;
    assign sram_wdata   = wdata;
    assign sram_wstrb   = wstrb;
    assign sram_bready  = writing && route == ROUTE_SRAM && bready;

    // Reads never reach the UART.
    assign uart_arvalid = 1'b0;
    assign uart_araddr  = araddr;
    assign uart_rready  = 1'b0;
    assign uart_awvalid = writing && route == ROUTE_UART && awvalid;
    assign uart_awaddr  = awaddr;
    assign uart_wvalid  = writing && route == ROUTE_UART && wvalid;
    assign uart_wdata   = wdata;
    assign uart_wstrb   = wstrb;
    assign uart_bready  = writing && route == ROUTE_UART && bready;

    always @(*) begin
        arready = 1'b0;
        rvalid  = 1'b0;
        rdata   = 32'b0;
        rresp   = RESP_OKAY;
        awready = 1'b0;
        wready  = 1'b0;
        bvalid  = 1'b0;
        bresp   = RESP_OKAY;

        if (reading) begin
            case (route)
                ROUTE_SRAM: begin
                    arready = sram_arready;
                    rvalid  = sram_rvalid;
                    rdata   = sram_rdata;
                    rresp   = sram_rresp;
                end
                default: begin
                    arready = !err_resp;
                    rvalid  = err_resp;
                    rresp   = RESP_DECERR;
                end
            endcase
        end else if (writing) begin
            case (route)
                ROUTE_SRAM: begin
                    awready = sram_awready;
                    wready  = sram_wready;
                    bvalid  = sram_bvalid;
                    bresp   = sram_bresp;
                end
                ROUTE_UART: begin
                    awready = uart_awready;
                    wready  = uart_wready;
                    bvalid  = uart_bvalid;
                    bresp   = uart_bresp;
                end
                default: begin
                    // Take AW and W together, as IDLE saw both offered.
                    awready = !err_resp && awvalid && wvalid;
                    wready  = !err_resp && awvalid && wvalid;
                    bvalid  = err_resp;
                    bresp   = RESP_DECERR;
                end
            endcase
        end
    end
endmodule
