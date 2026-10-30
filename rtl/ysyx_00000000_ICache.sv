// Instruction cache between the core's imem port and an AXI4 read master.
// A request accepted in one cycle is looked up in the next; a hit answers in that cycle, so
// back-to-back hits deliver one instruction per cycle. A miss refills the whole block with one
// INCR burst and then looks the request up again. Every fetchable region is cached; fence.i
// invalidates all blocks, including a refill still in flight.
module ysyx_00000000_ICache
  import ysyx_00000000_pkg::*;
#(
  parameter int BLOCK_BYTES = 16,
  parameter int SETS        = 4,
  parameter int WAYS        = 2     // 1 or 2; two ways use one LRU bit per set
) (
  input  logic        clock,
  input  logic        reset,

  input  logic        req_valid,
  output logic        req_ready,
  input  logic [31:0] req_addr,
  output logic        resp_valid,
  input  logic        resp_ready,
  output logic [31:0] resp_inst,
  output logic        resp_err,
  input  logic        fencei,

  output logic        ar_valid,
  input  logic        ar_ready,
  output axi_a_t      ar_bits,
  input  logic        r_valid,
  output logic        r_ready,
  input  axi_r_t      r_bits
);

  localparam int WORDS    = BLOCK_BYTES / 4;
  localparam int OFF_W    = $clog2(BLOCK_BYTES);
  localparam int IDX_W    = SETS > 1 ? $clog2(SETS) : 1;
  localparam int IDX_BITS = $clog2(SETS);
  localparam int TAG_W    = 32 - OFF_W - IDX_BITS;
  localparam int WORD_W   = WORDS > 1 ? $clog2(WORDS) : 1;
  localparam int WAY_W    = WAYS > 1 ? 1 : 1;

  typedef enum logic [1:0] { S_IDLE, S_LOOKUP, S_AR, S_R } state_e;
  state_e state;

  logic [31:0] addr;
  logic        err;         // the refill for `addr` failed; answer it with an error

  wire [TAG_W-1:0]  tag  = addr[31 -: TAG_W];
  wire [IDX_W-1:0]  idx  = SETS > 1 ? IDX_W'(addr[OFF_W +: IDX_BITS]) : '0;
  wire [WORD_W-1:0] word = WORDS > 1 ? WORD_W'(addr[2 +: WORD_W]) : '0;

  logic [TAG_W-1:0] tags  [SETS][WAYS];
  logic             valid [SETS][WAYS];
  logic [31:0]      data  [SETS][WAYS][WORDS];
  logic             lru   [SETS];          // way to replace next (two ways only)

  logic [WAYS-1:0] way_hit;
  always_comb
    for (int w = 0; w < WAYS; w++) way_hit[w] = valid[idx][w] && tags[idx][w] == tag;

  wire       hit     = |way_hit;
  wire       hit_way = WAYS > 1 ? way_hit[WAYS-1] : 1'b0;
  wire       lookup  = state == S_LOOKUP;

  // Refill state.
  logic             victim;
  logic [WORD_W-1:0] beat;
  logic             poisoned;   // fence.i during the refill: do not validate the block

  assign resp_valid = lookup && (hit || err);
  assign resp_inst  = data[idx][hit_way][word];
  assign resp_err   = err;
  assign req_ready  = state == S_IDLE || (resp_valid && resp_ready);

  assign ar_valid      = state == S_AR;
  assign ar_bits.id    = 4'd0;
  assign ar_bits.addr  = {addr[31:OFF_W], {OFF_W{1'b0}}};
  assign ar_bits.len   = 8'(WORDS - 1);
  assign ar_bits.size  = 3'd2;
  assign ar_bits.burst = AXI_BURST_INCR;
  assign r_ready       = state == S_R;

  wire r_fire = r_valid && r_ready;

  always_ff @(posedge clock) begin
    if (reset) begin
      state <= S_IDLE;
      err   <= 1'b0;
      for (int s = 0; s < SETS; s++) begin
        lru[s] <= 1'b0;
        for (int w = 0; w < WAYS; w++) valid[s][w] <= 1'b0;
      end
    end else begin
      unique case (state)
        S_IDLE: if (req_valid) state <= S_LOOKUP;
        S_LOOKUP: begin
          if (resp_valid) begin
            if (resp_ready) begin
              state <= req_valid ? S_LOOKUP : S_IDLE;
              err   <= 1'b0;
            end
          end else begin
            state    <= S_AR;
            victim   <= WAYS > 1 ? lru[idx] : 1'b0;
            beat     <= '0;
            poisoned <= 1'b0;
          end
        end
        S_AR: if (ar_ready) state <= S_R;
        S_R: if (r_fire) begin
          data[idx][victim][beat] <= r_bits.data;
          beat <= beat + 1'b1;
          if (r_bits.resp != 2'b00) poisoned <= 1'b1;
          if (r_bits.resp != 2'b00) err <= 1'b1;
          if (r_bits.last) begin
            state <= S_LOOKUP;
            tags[idx][victim]  <= tag;
            valid[idx][victim] <= !(poisoned || fencei || r_bits.resp != 2'b00);
          end
        end
        default: state <= S_IDLE;
      endcase

      // A fence.i during a refill also leaves the refilled block invalid; the refetch after the
      // redirect then reads memory again.
      if (fencei) begin
        if (state == S_AR || state == S_R) poisoned <= 1'b1;
        for (int s = 0; s < SETS; s++)
          for (int w = 0; w < WAYS; w++) valid[s][w] <= 1'b0;
      end

      // The way not used most recently is replaced next.
      if (WAYS > 1 && lookup && hit) lru[idx] <= !hit_way;
    end
    if (req_valid && req_ready) addr <= req_addr;
  end

  // An errored refill is answered without a valid block: the lookup reports `err` directly.
  // A poisoned refill whose request is still waiting is looked up again and misses, refilling anew.

`ifndef SYNTHESIS
  // Events for the simulator's counters: 0 hit, 1 miss (refill starts), 2 refill done, 3 fence.i.
  import "DPI-C" function void sim_icache_event(input byte ev);
  logic refilled;   // the pending lookup follows a refill and is not a hit of its own
  always_ff @(posedge clock) begin
    if (reset) refilled <= 1'b0;
    else begin
      if (lookup && resp_valid && resp_ready) begin
        if (!refilled) sim_icache_event(8'd0);
        refilled <= 1'b0;
      end
      if (lookup && !resp_valid) sim_icache_event(8'd1);
      if (fencei) sim_icache_event(8'd3);
      if (state == S_R && r_fire && r_bits.last) begin
        sim_icache_event(8'd2);
        refilled <= 1'b1;
      end
    end
  end
`endif

  wire unused = &{1'b0, r_bits.id, WAY_W[0]};

endmodule
