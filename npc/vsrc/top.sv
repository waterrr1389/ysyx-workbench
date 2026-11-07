// Standalone simulation top: the core and a memory system modelled through DPI-C.
module top
  import npc_pkg::*;
(
  input  logic  clk,
  input  logic  reset
);

  axi_req_t mem_req, sram_req, uart_req;
  axi_rsp_t mem_rsp, sram_rsp, uart_rsp;

  Core u_core (.clk, .reset, .bus_req(mem_req), .bus_rsp(mem_rsp));

  Xbar u_xbar (
    .clk, .reset,
    .in_req(mem_req), .in_rsp(mem_rsp),
    .sram_req, .sram_rsp, .uart_req, .uart_rsp
  );

  SRAM u_sram (.clk, .reset, .req(sram_req), .rsp(sram_rsp));
  UART u_uart (.clk, .reset, .req(uart_req), .rsp(uart_rsp));

endmodule
