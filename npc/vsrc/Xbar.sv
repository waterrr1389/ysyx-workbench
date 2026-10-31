// Routes one AXI master to the slaves by address, one transaction at a time.
// Addresses that map to no slave are answered here with DECERR.
module Xbar
  import npc_pkg::*;
(
  input  logic     clk,
  input  logic     reset,

  input  axi_req_t in_req,
  output axi_rsp_t in_rsp,

  output axi_req_t sram_req,
  input  axi_rsp_t sram_rsp,
  output axi_req_t uart_req,
  input  axi_rsp_t uart_rsp
);

  localparam word_t SRAM_BASE = 32'h8000_0000, SRAM_SIZE = 32'h0200_0000;
  localparam word_t UART_BASE = 32'h1000_0000, UART_SIZE = 32'h0000_0008;
  // The RTC is served by the SRAM model, whose pmem_read returns host time there.
  localparam word_t RTC_BASE  = 32'ha000_0048, RTC_SIZE  = 32'h0000_0008;

  typedef enum logic [1:0] { TO_NONE, TO_SRAM, TO_UART, TO_ERR } route_e;

  function automatic route_e decode(word_t a, logic is_write);
    if (a - SRAM_BASE < SRAM_SIZE)                return TO_SRAM;
    if (!is_write && a - RTC_BASE < RTC_SIZE)     return TO_SRAM;
    if (is_write && a - UART_BASE < UART_SIZE)    return TO_UART;  // the UART cannot be read
    return TO_ERR;
  endfunction

  // Locked from the cycle an address is presented, for the same reason as in Arbiter.
  route_e route, sel;
  always_comb begin
    if (route != TO_NONE)    sel = route;
    else if (in_req.ar_valid) sel = decode(in_req.ar.addr, 1'b0);
    else if (in_req.aw_valid) sel = decode(in_req.aw.addr, 1'b1);
    else                      sel = TO_NONE;
  end

  // Error responder: accept the request, then answer DECERR.
  logic err_aw, err_w, err_ar;   // request parts already taken
  logic [3:0] err_id;

  always_comb begin
    sram_req = '0;
    uart_req = '0;
    in_rsp   = '0;
    unique case (sel)
      TO_SRAM: begin sram_req = in_req; in_rsp = sram_rsp; end
      TO_UART: begin uart_req = in_req; in_rsp = uart_rsp; end
      TO_ERR: begin
        in_rsp.aw_ready = !err_aw;
        in_rsp.w_ready  = !err_w;
        in_rsp.ar_ready = !err_ar;
        in_rsp.b_valid  = err_aw && err_w;
        in_rsp.b        = '{id: err_id, resp: RESP_DECERR};
        in_rsp.r_valid  = err_ar;
        in_rsp.r        = '{id: err_id, data: '0, resp: RESP_DECERR, last: 1'b1};
      end
      default: ;
    endcase
  end

  wire done = (in_rsp.b_valid && in_req.b_ready) ||
              (in_rsp.r_valid && in_req.r_ready && in_rsp.r.last);

  always_ff @(posedge clk) begin
    if (reset || done) begin
      route  <= TO_NONE;
      err_aw <= 1'b0;
      err_w  <= 1'b0;
      err_ar <= 1'b0;
    end else begin
      route <= sel;
      if (sel == TO_ERR) begin
        if (in_req.aw_valid && in_rsp.aw_ready) begin err_aw <= 1'b1; err_id <= in_req.aw.id; end
        if (in_req.w_valid  && in_rsp.w_ready)  err_w  <= 1'b1;
        if (in_req.ar_valid && in_rsp.ar_ready) begin err_ar <= 1'b1; err_id <= in_req.ar.id; end
      end
    end
  end

endmodule
