// dmem slave to AXI4 master: one single-beat (possibly narrow) transfer at a time.
module ysyx_00000000_LSUAXI
  import ysyx_00000000_pkg::*;
(
  input  logic        clock,
  input  logic        reset,

  input  logic        req_valid,
  output logic        req_ready,
  input  logic [31:0] req_addr,
  input  logic        req_wen,
  input  logic [1:0]  req_size,
  input  logic [31:0] req_wdata,
  input  logic [3:0]  req_wstrb,
  output logic        resp_valid,
  output logic [31:0] resp_rdata,
  output logic        resp_err,

  output logic        ar_valid,
  input  logic        ar_ready,
  output axi_a_t      ar_bits,
  input  logic        r_valid,
  output logic        r_ready,
  input  axi_r_t      r_bits,
  output logic        aw_valid,
  input  logic        aw_ready,
  output axi_a_t      aw_bits,
  output logic        w_valid,
  input  logic        w_ready,
  output axi_w_t      w_bits,
  input  logic        b_valid,
  output logic        b_ready,
  input  axi_b_t      b_bits
);

  typedef enum logic [1:0] { S_IDLE, S_READ, S_WRITE } state_e;
  state_e      state;
  logic        a_pending;   // AR or AW not yet accepted
  logic        w_pending;
  axi_a_t      a;
  axi_w_t      w;

  assign req_ready = state == S_IDLE;

  assign ar_valid = state == S_READ && a_pending;
  assign ar_bits  = a;
  assign r_ready  = state == S_READ && !a_pending;
  assign aw_valid = state == S_WRITE && a_pending;
  assign aw_bits  = a;
  assign w_valid  = state == S_WRITE && w_pending;
  assign w_bits   = w;
  assign b_ready  = state == S_WRITE && !a_pending && !w_pending;

  always_ff @(posedge clock) begin
    resp_valid <= 1'b0;
    if (reset) begin
      state <= S_IDLE;
    end else begin
      unique case (state)
        S_IDLE: if (req_valid) begin
          state     <= req_wen ? S_WRITE : S_READ;
          a_pending <= 1'b1;
          w_pending <= req_wen;
          a.id      <= 4'd1;
          a.addr    <= req_addr;
          a.len     <= 8'd0;
          a.size    <= {1'b0, req_size};
          a.burst   <= AXI_BURST_INCR;
          w.data    <= req_wdata;
          w.strb    <= req_wstrb;
          w.last    <= 1'b1;
        end
        S_READ: begin
          if (ar_valid && ar_ready) a_pending <= 1'b0;
          if (r_valid && r_ready) begin
            state      <= S_IDLE;
            resp_valid <= 1'b1;
            resp_rdata <= r_bits.data;
            resp_err   <= r_bits.resp != 2'b00;
          end
        end
        S_WRITE: begin
          if (aw_valid && aw_ready) a_pending <= 1'b0;
          if (w_valid && w_ready)   w_pending <= 1'b0;
          if (b_valid && b_ready) begin
            state      <= S_IDLE;
            resp_valid <= 1'b1;
            resp_err   <= b_bits.resp != 2'b00;
          end
        end
        default: state <= S_IDLE;
      endcase
    end
  end

  wire unused = &{1'b0, r_bits.id, r_bits.last, b_bits.id};

endmodule
