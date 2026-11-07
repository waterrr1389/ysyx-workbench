// Fetch unit. Owns the PC and reads one instruction per AXI read.
//
// The core runs one instruction at a time: after handing an instruction to IDU,
// IFU waits for the commit to redirect it to the next PC. Pipelining later means
// fetching ahead at a predicted PC and treating the redirect as a flush; the
// ports stay the same.
module IFU
  import npc_pkg::*;
#(
  parameter word_t RESET_PC = DEFAULT_RESET_PC
)
(
  input  logic     clk,
  input  logic     reset,

  output logic     out_valid,
  input  logic     out_ready,
  output if2id_t   out,

  // From the commit point: the next architectural PC.
  input  logic     redirect_valid,
  input  word_t    redirect_pc,

  output word_t    pc,

  output axi_req_t bus_req,
  input  axi_rsp_t bus_rsp
);

  // One flag per step of the fetch; at most one of them is set.
  logic inflight;   // an instruction from pc is somewhere between here and commit
  logic ar_pend;    // the address is presented and not yet accepted
  logic r_wait;     // the address was accepted; waiting for the data

  wire ar_fire  = bus_req.ar_valid && bus_rsp.ar_ready;
  wire r_fire   = bus_rsp.r_valid && bus_req.r_ready;
  wire out_fire = out_valid && out_ready;

  always_ff @(posedge clk) begin
    if (reset) begin
      pc        <= RESET_PC;
      inflight  <= 1'b0;
      ar_pend   <= 1'b0;
      r_wait    <= 1'b0;
      out_valid <= 1'b0;
    end else begin
      if (!inflight) begin
        inflight <= 1'b1;
        ar_pend  <= 1'b1;
      end
      if (ar_fire) begin
        ar_pend <= 1'b0;
        r_wait  <= 1'b1;
      end
      if (r_fire) begin
        r_wait    <= 1'b0;
        out_valid <= 1'b1;
        out.pc    <= pc;
        out.inst  <= bus_rsp.r.data;
        out.fault <= bus_rsp.r.resp != RESP_OKAY;
      end
      if (out_fire) out_valid <= 1'b0;
      if (redirect_valid) begin
        pc       <= redirect_pc;
        inflight <= 1'b0;
      end
    end
  end

  always_comb begin
    bus_req          = '0;
    bus_req.ar_valid = ar_pend;
    bus_req.ar.addr  = pc;
    bus_req.ar.size  = 3'd2;
    bus_req.ar.burst = BURST_INCR;
    bus_req.r_ready  = r_wait;
  end

  // A redirect arrives only after the instruction has left for commit.
  always_ff @(posedge clk) begin
    if (!reset && redirect_valid) assert (inflight && !ar_pend && !r_wait && !out_valid);
  end

endmodule
