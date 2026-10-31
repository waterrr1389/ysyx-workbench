// Memory slave backed by the harness through pmem_read/pmem_write.
// Serves one transaction at a time; the Xbar never presents a read and a write together.
//
// With RANDOM_DELAY set, every request waits a pseudo-random 0..7 cycles before it
// is accepted, so masters are exercised against a slave that is not always ready.
// The delay lives here, in the slave, because how long memory takes is a property
// of the memory, not of the masters.
module SRAM
  import npc_pkg::*;
#(
  parameter bit RANDOM_DELAY = 1'b1
) (
  input  logic     clk,
  input  logic     reset,
  input  axi_req_t req,
  output axi_rsp_t rsp
);

  import "DPI-C" function int pmem_read(input int raddr);
  import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

  logic [7:0] lfsr;
  logic [2:0] wait_cnt;          // cycles left before the next request is accepted
  logic       aw_got, w_got;     // write request parts already taken
  axi_a_t     aw_q;
  axi_w_t     w_q;
  logic       b_valid, r_valid;
  axi_b_t     b_q;
  axi_r_t     r_q;

  wire ready_now = wait_cnt == 3'd0 && !b_valid && !r_valid;

  always_comb begin
    rsp          = '0;
    rsp.aw_ready = ready_now && !aw_got;
    rsp.w_ready  = ready_now && !w_got;
    rsp.ar_ready = ready_now && !aw_got && !w_got;
    rsp.b_valid  = b_valid;
    rsp.b        = b_q;
    rsp.r_valid  = r_valid;
    rsp.r        = r_q;
  end

  wire aw_fire = req.aw_valid && rsp.aw_ready;
  wire w_fire  = req.w_valid  && rsp.w_ready;
  wire ar_fire = req.ar_valid && rsp.ar_ready;
  wire b_fire  = b_valid && req.b_ready;
  wire r_fire  = r_valid && req.r_ready;

  wire axi_a_t aw_cur = aw_fire ? req.aw : aw_q;
  wire axi_w_t w_cur  = w_fire  ? req.w  : w_q;

  always_ff @(posedge clk) begin
    if (reset) begin
      lfsr     <= 8'h5a;
      wait_cnt <= '0;
      aw_got   <= 1'b0;
      w_got    <= 1'b0;
      b_valid  <= 1'b0;
      r_valid  <= 1'b0;
    end else begin
      lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
      if (wait_cnt != 3'd0) wait_cnt <= wait_cnt - 3'd1;

      if (aw_fire) begin aw_got <= 1'b1; aw_q <= req.aw; end
      if (w_fire)  begin w_got  <= 1'b1; w_q  <= req.w;  end
      if ((aw_fire || aw_got) && (w_fire || w_got)) begin
        pmem_write(aw_cur.addr, w_cur.data, {4'b0, w_cur.strb});
        aw_got  <= 1'b0;
        w_got   <= 1'b0;
        b_valid <= 1'b1;
        b_q     <= '{id: aw_cur.id, resp: RESP_OKAY};
      end
      if (ar_fire) begin
        r_valid <= 1'b1;
        r_q     <= '{id: req.ar.id, data: pmem_read(req.ar.addr), resp: RESP_OKAY, last: 1'b1};
      end
      if (b_fire || r_fire) begin
        b_valid <= 1'b0;
        r_valid <= 1'b0;
        if (RANDOM_DELAY) wait_cnt <= lfsr[2:0];
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!reset) begin
      assert (!(req.ar_valid && (req.aw_valid || req.w_valid)));
      if (req.ar_valid) assert (req.ar.len == 8'd0);
      if (req.aw_valid) assert (req.aw.len == 8'd0);
    end
  end

endmodule
