// Load/store unit: one AXI transaction per memory instruction; others pass through.
module LSU
  import npc_pkg::*;
(
  input  logic     clk,
  input  logic     reset,

  input  logic     in_valid,
  output logic     in_ready,
  input  ex2ls_t   in,

  output logic     out_valid,
  input  logic     out_ready,
  output ls2wb_t   out,

  output axi_req_t bus_req,
  input  axi_rsp_t bus_rsp
);

  // One flag per channel. Each is set when the request is accepted from EXU and
  // cleared by its own handshake, so the AW and W handshakes may happen in either
  // order or together.
  logic aw_pend, w_pend, b_wait, ar_pend, r_wait;
  ex2ls_t q;   // the memory instruction being served

  wire busy     = aw_pend || w_pend || b_wait || ar_pend || r_wait;
  wire in_fire  = in_valid && in_ready;
  wire out_fire = out_valid && out_ready;
  wire aw_fire  = bus_req.aw_valid && bus_rsp.aw_ready;
  wire w_fire   = bus_req.w_valid && bus_rsp.w_ready;
  wire b_fire   = bus_rsp.b_valid && bus_req.b_ready;
  wire ar_fire  = bus_req.ar_valid && bus_rsp.ar_ready;
  wire r_fire   = bus_rsp.r_valid && bus_req.r_ready;

  assign in_ready = !busy && (!out_valid || out_ready);

  wire logic [1:0] off = q.result[1:0];

  function automatic logic [2:0] size_of(mem_op_e op);
    unique case (op)
      MEM_LB, MEM_LBU, MEM_SB: return 3'd0;
      MEM_LH, MEM_LHU, MEM_SH: return 3'd1;
      default:                 return 3'd2;
    endcase
  endfunction

  // The bus carries a 32-bit word with each byte on its own lane, so loaded data
  // is shifted down from the lane of the address and stored data shifted up to it.
  function automatic word_t load_extend(mem_op_e op, word_t lanes, logic [1:0] o);
    word_t v = lanes >> {o, 3'b0};
    unique case (op)
      MEM_LB:  return {{24{v[7]}}, v[7:0]};
      MEM_LBU: return {24'b0, v[7:0]};
      MEM_LH:  return {{16{v[15]}}, v[15:0]};
      MEM_LHU: return {16'b0, v[15:0]};
      default: return v;
    endcase
  endfunction

  function automatic logic [3:0] strb_of(mem_op_e op, logic [1:0] o);
    unique case (op)
      MEM_SB:  return 4'b0001 << o;
      MEM_SH:  return 4'b0011 << o;
      default: return 4'b1111;
    endcase
  endfunction

  function automatic ls2wb_t pass(ex2ls_t e);
    ls2wb_t p;
    p           = '0;
    p.pc        = e.pc;
    p.npc       = e.npc;
    p.result    = e.result;
    p.rd        = e.rd;
    p.rd_wen    = e.rd_wen;
    p.csr_op    = e.csr_op;
    p.csr_addr  = e.csr_addr;
    p.sys       = e.sys;
    return p;
  endfunction

  always_ff @(posedge clk) begin
    if (reset) begin
      {aw_pend, w_pend, b_wait, ar_pend, r_wait} <= '0;
      out_valid <= 1'b0;
    end else begin
      if (out_fire) out_valid <= 1'b0;
      if (in_fire) begin
        q <= in;
        if (in.mem_op == MEM_NONE) begin
          out       <= pass(in);
          out_valid <= 1'b1;
        end else if (is_store(in.mem_op)) begin
          {aw_pend, w_pend, b_wait} <= 3'b111;
        end else begin
          {ar_pend, r_wait} <= 2'b11;
        end
      end
      if (aw_fire) aw_pend <= 1'b0;
      if (w_fire)  w_pend  <= 1'b0;
      if (ar_fire) ar_pend <= 1'b0;
      if (b_fire) begin
        b_wait        <= 1'b0;
        out           <= pass(q);
        out.bus_error <= bus_rsp.b.resp != RESP_OKAY;
        out_valid     <= 1'b1;
      end
      if (r_fire) begin
        r_wait        <= 1'b0;
        out           <= pass(q);
        out.result    <= load_extend(q.mem_op, bus_rsp.r.data, off);
        out.bus_error <= bus_rsp.r.resp != RESP_OKAY;
        out_valid     <= 1'b1;
      end
    end
  end

  always_comb begin
    bus_req          = '0;
    bus_req.aw_valid = aw_pend;
    bus_req.aw.addr  = q.result;
    bus_req.aw.size  = size_of(q.mem_op);
    bus_req.aw.burst = BURST_INCR;
    bus_req.w_valid  = w_pend;
    bus_req.w.data   = q.store_data << {off, 3'b0};
    bus_req.w.strb   = strb_of(q.mem_op, off);
    bus_req.w.last   = 1'b1;
    // B and R are accepted only after their requests are fully sent.
    bus_req.b_ready  = b_wait && !aw_pend && !w_pend;
    bus_req.ar_valid = ar_pend;
    bus_req.ar.addr  = q.result;
    bus_req.ar.size  = size_of(q.mem_op);
    bus_req.ar.burst = BURST_INCR;
    bus_req.r_ready  = r_wait && !ar_pend;
  end

endmodule
