module Arbiter (
    input  logic        clk,
    input  logic        reset,

    input  logic        ifu_arvalid,
    output logic        ifu_arready,
    input  logic [31:0] ifu_araddr,
    output logic        ifu_rvalid,
    input  logic        ifu_rready,
    output logic [31:0] ifu_rdata,
    output logic [1:0]  ifu_rresp,

    input  logic        lsu_arvalid,
    output logic        lsu_arready,
    input  logic [31:0] lsu_araddr,
    output logic        lsu_rvalid,
    input  logic        lsu_rready,
    output logic [31:0] lsu_rdata,
    output logic [1:0]  lsu_rresp,
    input  logic        lsu_awvalid,
    output logic        lsu_awready,
    input  logic [31:0] lsu_awaddr,
    input  logic        lsu_wvalid,
    output logic        lsu_wready,
    input  logic [31:0] lsu_wdata,
    input  logic [3:0]  lsu_wstrb,
    output logic        lsu_bvalid,
    input  logic        lsu_bready,
    output logic [1:0]  lsu_bresp,

    output logic        s_arvalid,
    input  logic        s_arready,
    output logic [31:0] s_araddr,
    input  logic        s_rvalid,
    output logic        s_rready,
    input  logic [31:0] s_rdata,
    input  logic [1:0]  s_rresp,
    output logic        s_awvalid,
    input  logic        s_awready,
    output logic [31:0] s_awaddr,
    output logic        s_wvalid,
    input  logic        s_wready,
    output logic [31:0] s_wdata,
    output logic [3:0]  s_wstrb,
    input  logic        s_bvalid,
    output logic        s_bready,
    input  logic [1:0]  s_bresp
);
    typedef struct packed {
        logic        arvalid;
        logic [31:0] araddr;
        logic        rready;
    } read_req_t;

    typedef struct packed {
        logic        arready;
        logic        rvalid;
        logic [31:0] rdata;
        logic [1:0]  rresp;
    } read_rsp_t;

    typedef struct packed {
        logic        awvalid;
        logic [31:0] awaddr;
        logic        wvalid;
        logic [31:0] wdata;
        logic [3:0]  wstrb;
        logic        bready;
    } write_req_t;

    typedef struct packed {
        logic       awready;
        logic       wready;
        logic       bvalid;
        logic [1:0] bresp;
    } write_rsp_t;

    typedef enum logic [1:0] {
        IDLE,
        IFU_READ,
        LSU_READ,
        LSU_WRITE
    } state_t;

    state_t state, route;
    read_req_t ifu_req, lsu_read_req, s_read_req;
    read_rsp_t ifu_rsp, lsu_read_rsp, s_read_rsp;
    write_req_t lsu_write_req, s_write_req;
    write_rsp_t lsu_write_rsp, s_write_rsp;

    // Retain ownership through the response, including split AW/W handshakes.
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
        end else begin
            case (route)
                IFU_READ, LSU_READ:
                    state <= (s_read_rsp.rvalid && s_read_req.rready)
                             ? IDLE : route;
                LSU_WRITE:
                    state <= (s_write_rsp.bvalid && s_write_req.bready)
                             ? IDLE : route;
                default:
                    state <= IDLE;
            endcase
        end
    end

    assign ifu_req = '{arvalid: ifu_arvalid, araddr: ifu_araddr, rready: ifu_rready};
    assign lsu_read_req = '{arvalid: lsu_arvalid, araddr: lsu_araddr, rready: lsu_rready};
    assign lsu_write_req = '{
        awvalid: lsu_awvalid, awaddr: lsu_awaddr,
        wvalid: lsu_wvalid, wdata: lsu_wdata, wstrb: lsu_wstrb,
        bready: lsu_bready
    };
    assign s_read_rsp = '{arready: s_arready, rvalid: s_rvalid, rdata: s_rdata, rresp: s_rresp};
    assign s_write_rsp = '{awready: s_awready, wready: s_wready, bvalid: s_bvalid, bresp: s_bresp};

    assign ifu_arready = ifu_rsp.arready;
    assign ifu_rvalid = ifu_rsp.rvalid;
    assign ifu_rdata = ifu_rsp.rdata;
    assign ifu_rresp = ifu_rsp.rresp;
    assign lsu_arready = lsu_read_rsp.arready;
    assign lsu_rvalid = lsu_read_rsp.rvalid;
    assign lsu_rdata = lsu_read_rsp.rdata;
    assign lsu_rresp = lsu_read_rsp.rresp;
    assign lsu_awready = lsu_write_rsp.awready;
    assign lsu_wready = lsu_write_rsp.wready;
    assign lsu_bvalid = lsu_write_rsp.bvalid;
    assign lsu_bresp = lsu_write_rsp.bresp;

    assign s_arvalid = s_read_req.arvalid;
    assign s_araddr = s_read_req.araddr;
    assign s_rready = s_read_req.rready;
    assign s_awvalid = s_write_req.awvalid;
    assign s_awaddr = s_write_req.awaddr;
    assign s_wvalid = s_write_req.wvalid;
    assign s_wdata = s_write_req.wdata;
    assign s_wstrb = s_write_req.wstrb;
    assign s_bready = s_write_req.bready;

    // Fixed priority: LSU write, LSU read, then IFU read.
    // Forward immediately in IDLE, then lock the route at the clock edge.
    always_comb begin
        route = state;
        if (reset) begin
            route = IDLE;
        end else if (state == IDLE) begin
            if (lsu_write_req.awvalid || lsu_write_req.wvalid)
                route = LSU_WRITE;
            else if (lsu_read_req.arvalid)
                route = LSU_READ;
            else if (ifu_req.arvalid)
                route = IFU_READ;
        end
    end

    always_comb begin
        ifu_rsp = '0;
        lsu_read_rsp = '0;
        lsu_write_rsp = '0;
        s_read_req = '0;
        s_write_req = '0;

        case (route)
            IFU_READ: begin
                s_read_req = ifu_req;
                ifu_rsp = s_read_rsp;
            end
            LSU_READ: begin
                s_read_req = lsu_read_req;
                lsu_read_rsp = s_read_rsp;
            end
            LSU_WRITE: begin
                s_write_req = lsu_write_req;
                lsu_write_rsp = s_write_rsp;
            end
            default: begin
            end
        endcase
    end
endmodule
