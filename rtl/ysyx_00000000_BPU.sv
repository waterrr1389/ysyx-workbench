// Branch predictor. Lookup is combinational on the fetch PC; updates come from EXU when a control-flow
// instruction resolves. A direct-mapped BTB holds taken control flow: on a hit, jumps are predicted
// taken and conditional branches follow the entry's 2-bit counter. Only taken outcomes allocate.
// Tags and targets keep only PC bits below SPAN_W: the predicted target takes its upper bits from the
// fetch PC, so control flow across a 2^SPAN_W boundary and aliasing beyond it only cost a misprediction,
// which EXU corrects.
module ysyx_00000000_BPU
  import ysyx_00000000_pkg::*;
#(
  parameter int ENTRIES = 8,
  parameter int SPAN_W  = 16
) (
  input  logic        clock,
  input  logic        reset,

  input  logic [31:0] lookup_pc,
  output logic [31:0] lookup_next,

  input  logic        update_valid,
  input  cf_e         update_cf,
  input  logic [31:0] update_pc,
  input  logic        update_taken,
  input  logic [31:0] update_target
);

  localparam int IDX_W = $clog2(ENTRIES);
  localparam int TAG_W = SPAN_W - 2 - IDX_W;
  localparam int TGT_W = SPAN_W - 2;

  logic             valid  [ENTRIES];
  logic [TAG_W-1:0] tags   [ENTRIES];
  logic [TGT_W-1:0] target [ENTRIES];
  logic             branch [ENTRIES];
  logic [1:0]       ctr    [ENTRIES];

  wire [IDX_W-1:0] l_idx = lookup_pc[2 +: IDX_W];
  wire             l_hit = valid[l_idx] && tags[l_idx] == lookup_pc[SPAN_W-1 -: TAG_W];
  wire             l_tkn = l_hit && (!branch[l_idx] || ctr[l_idx][1]);

  assign lookup_next = l_tkn ? {lookup_pc[31:SPAN_W], target[l_idx], 2'b00} : lookup_pc + 32'd4;

  wire [IDX_W-1:0] u_idx = update_pc[2 +: IDX_W];
  wire             u_hit = valid[u_idx] && tags[u_idx] == update_pc[SPAN_W-1 -: TAG_W];
  wire             u_br  = update_cf == CF_BRANCH;

  always_ff @(posedge clock) begin
    if (reset) begin
      for (int i = 0; i < ENTRIES; i++) valid[i] <= 1'b0;
    end else if (update_valid) begin
      if (u_hit) begin
        if (update_taken) target[u_idx] <= update_target[SPAN_W-1:2];
        branch[u_idx] <= u_br;
        if (update_taken && ctr[u_idx] != 2'd3) ctr[u_idx] <= ctr[u_idx] + 2'd1;
        if (!update_taken && ctr[u_idx] != 2'd0) ctr[u_idx] <= ctr[u_idx] - 2'd1;
      end else if (update_taken) begin
        valid[u_idx]  <= 1'b1;
        tags[u_idx]   <= update_pc[SPAN_W-1 -: TAG_W];
        target[u_idx] <= update_target[SPAN_W-1:2];
        branch[u_idx] <= u_br;
        ctr[u_idx]    <= 2'd2;
      end
    end
  end

  wire unused = &{1'b0, update_pc, update_target};

endmodule
