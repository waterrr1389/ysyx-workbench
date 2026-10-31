// Formal harness for the icache: every answer must equal what an uncached memory holds.
// Memory word at address a is a ^ key, with key chosen freely; key may change only in a fence.i
// cycle, standing for stores made before it. A request accepted after the last fence.i must see the
// current memory; one accepted before it may be answered with either (the pipeline drops it).
// The bus may stall any handshake for any number of cycles.
module icache_check (
  input        clock,
  input        req_valid,
  input [31:0] req_addr,
  input        resp_ready,
  input        fencei,
  input        ar_ok,
  input        r_go,
  input [31:0] new_key
);

  reg init = 1'b1;
  always @(posedge clock) init <= 1'b0;
  wire reset = init;

  wire        req_ready, resp_valid, resp_err, ar_valid, r_ready;
  wire [31:0] resp_inst;
  wire [48:0] ar_bits;
  wire [38:0] r_bits;
  reg         busy;
  wire        ar_ready = ar_ok && !busy;   // the slave takes one transaction at a time
  wire        r_valid  = busy && r_go;

  ysyx_00000000_ICache dut (
    .clock, .reset,
    .req_valid, .req_ready, .req_addr, .resp_valid, .resp_ready, .resp_inst, .resp_err, .fencei,
    .ar_valid, .ar_ready, .ar_bits, .r_valid, .r_ready, .r_bits
  );

  // The fetch unit asks for word-aligned addresses and requests nothing while fence.i redirects it.
  always @(*) begin
    assume (req_addr[1:0] == 2'b00);
    assume (!(fencei && req_valid));
  end

  // ------------------------------------------------------------- memory
  (* anyconst *) reg [31:0] key0;
  reg [31:0] key;
  always @(posedge clock) begin
    if (init) key <= key0;
    else if (fencei) key <= new_key;
  end

  // ------------------------------------------------------------- AXI read slave
  wire [31:0] ar_addr = ar_bits[44:13];
  wire [7:0]  ar_len  = ar_bits[12:5];
  reg  [31:0] beat_addr;
  reg  [7:0]  beats_left;

  assign r_bits = {4'd0, beat_addr ^ key, 2'b00, beats_left == 8'd0};

  always @(posedge clock) begin
    if (reset) busy <= 1'b0;
    else if (ar_valid && ar_ready) begin
      busy       <= 1'b1;
      beat_addr  <= ar_addr;
      beats_left <= ar_len;
    end else if (r_valid && r_ready) begin
      beat_addr  <= beat_addr + 32'd4;
      beats_left <= beats_left - 8'd1;
      if (beats_left == 8'd0) busy <= 1'b0;
    end
  end

  // ------------------------------------------------------------- reference
  reg        pending, fresh;
  reg [31:0] pend_addr;

  always @(posedge clock) begin
    if (reset) begin
      pending <= 1'b0;
    end else begin
      if (resp_valid && resp_ready) pending <= 1'b0;
      if (req_valid && req_ready) begin
        pending   <= 1'b1;
        pend_addr <= req_addr;
        fresh     <= 1'b1;
      end
      if (fencei) fresh <= 1'b0;
    end
  end

  always @(*) begin
    if (!reset) begin
      // Answers only to requests, and the right word of the current memory.
      if (resp_valid) assert (pending);
      if (resp_valid && fresh) assert (!resp_err && resp_inst == (pend_addr ^ key));
      // Refills are aligned bursts of one whole block (8 B in the checked shape).
      if (ar_valid) assert (ar_addr[2:0] == 3'd0 && ar_len == 8'd1);
    end
  end

  // The checks must not hold vacuously: a fresh answer after a fence.i is reachable.
  reg seen_fencei = 1'b0;
  always @(posedge clock) if (fencei) seen_fencei <= 1'b1;
  always @(*) if (!reset) cover (seen_fencei && resp_valid && resp_ready && fresh);

endmodule
