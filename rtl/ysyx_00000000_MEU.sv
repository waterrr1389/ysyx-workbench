// Memory access and commit point. Every irreversible effect happens here: dmem access, CSR write,
// trap entry, mret and fence.i. An instruction in MEU is never speculative.
module ysyx_00000000_MEU
  import ysyx_00000000_pkg::*;
(
  input  logic        clock,
  input  logic        reset,

  input  logic        in_valid,
  output logic        in_ready,
  input  ex2mem_t     in_bits,

  output fwd_t        fwd,

  output logic        redirect_valid,
  output logic [31:0] redirect_pc,
  output logic        fencei,

  output logic        dmem_req_valid,
  input  logic        dmem_req_ready,
  output logic [31:0] dmem_req_addr,
  output logic        dmem_req_wen,
  output logic [1:0]  dmem_req_size,
  output logic [31:0] dmem_req_wdata,
  output logic [3:0]  dmem_req_wstrb,
  input  logic        dmem_resp_valid,
  input  logic [31:0] dmem_resp_rdata,
  input  logic        dmem_resp_err,

  output logic        out_valid,
  output mem2wb_t     out_bits
);

  logic    valid;
  ex2mem_t r;
  logic    req_sent;

  // WBU always accepts, so leaving MEU only waits for the memory response.
  wire fire = out_valid;

  // A redirect here kills the instruction EXU would hand over in the same cycle.
  assign in_ready = (!valid || fire) && !redirect_valid;

  always_ff @(posedge clock) begin
    if (reset)         valid <= 1'b0;
    else if (in_ready) valid <= in_valid;
    else if (fire)     valid <= 1'b0;
    if (in_ready && in_valid) r <= in_bits;
  end

  // ---------------------------------------------------------------- memory access
  wire [1:0] size  = r.funct3[1:0];
  wire [1:0] off   = r.result[1:0];
  wire misalign    = (size == 2'd1 && off[0]) || (size == 2'd2 && off != 2'd0);
  wire mem_op      = (r.mem_ren || r.mem_wen) && !r.exc.valid;
  wire mem_go      = mem_op && !misalign;

  assign dmem_req_valid = valid && mem_go && !req_sent;
  assign dmem_req_addr  = r.result;
  assign dmem_req_wen   = r.mem_wen;
  assign dmem_req_size  = size;
  assign dmem_req_wdata = r.src << {off, 3'b0};
  assign dmem_req_wstrb = (size == 2'd0 ? 4'b0001 : size == 2'd1 ? 4'b0011 : 4'b1111) << off;

  always_ff @(posedge clock) begin
    if (reset || fire)                       req_sent <= 1'b0;
    else if (dmem_req_valid && dmem_req_ready) req_sent <= 1'b1;
  end

  wire mem_done = req_sent && dmem_resp_valid;
  assign out_valid = valid && (!mem_go || mem_done);

  wire [31:0] lane = dmem_resp_rdata >> {off, 3'b0};
  logic [31:0] load_val;
  always_comb begin
    unique case (r.funct3)
      3'b000:  load_val = {{24{lane[7]}}, lane[7:0]};
      3'b001:  load_val = {{16{lane[15]}}, lane[15:0]};
      3'b100:  load_val = {24'd0, lane[7:0]};
      3'b101:  load_val = {16'd0, lane[15:0]};
      default: load_val = lane;
    endcase
  end

  // ---------------------------------------------------------------- exceptions
  exc_t exc;
  always_comb begin
    exc = r.exc;
    if (!r.exc.valid && mem_op && misalign) begin
      exc.valid = 1'b1;
      exc.cause = r.mem_wen ? EXC_STORE_MISALIGN : EXC_LOAD_MISALIGN;
    end else if (mem_go && dmem_resp_err) begin
      exc.valid = 1'b1;
      exc.cause = r.mem_wen ? EXC_STORE_FAULT : EXC_LOAD_FAULT;
    end
  end

  // ---------------------------------------------------------------- CSRs
  logic        mstatus_mie, mstatus_mpie;
  logic [31:2] mtvec;
  logic [31:2] mepc;
  logic        mcause_int;
  logic [3:0]  mcause_code;

  logic [31:0] csr_rdata;
  always_comb begin
    unique case (r.csr_addr)
      CSR_MSTATUS:   csr_rdata = {19'd0, 2'b11, 3'd0, mstatus_mpie, 3'd0, mstatus_mie, 3'd0};
      CSR_MTVEC:     csr_rdata = {mtvec, 2'b00};
      CSR_MEPC:      csr_rdata = {mepc, 2'b00};
      CSR_MCAUSE:    csr_rdata = {mcause_int, 27'd0, mcause_code};
      CSR_MVENDORID: csr_rdata = 32'h7973_7978;
      default:       csr_rdata = 32'd0;          // marchid
    endcase
  end

  logic [31:0] csr_wdata;
  always_comb begin
    unique case (r.csr_op)
      CSR_RS:  csr_wdata = csr_rdata | r.src;
      CSR_RC:  csr_wdata = csr_rdata & ~r.src;
      default: csr_wdata = r.src;
    endcase
  end

  wire trap   = fire && exc.valid;
  wire csr_we = fire && !exc.valid && r.csr_op != CSR_NONE;
  wire mret   = fire && !exc.valid && r.mret;

  always_ff @(posedge clock) begin
    if (reset) begin
      mstatus_mie  <= 1'b0;
      mstatus_mpie <= 1'b0;
      mcause_int   <= 1'b0;
      mcause_code  <= 4'd0;
    end else if (trap) begin
      mepc         <= r.pc[31:2];
      mcause_int   <= 1'b0;
      mcause_code  <= exc.cause;
      mstatus_mpie <= mstatus_mie;
      mstatus_mie  <= 1'b0;
    end else if (mret) begin
      mstatus_mie  <= mstatus_mpie;
      mstatus_mpie <= 1'b1;
    end else if (csr_we) begin
      unique case (r.csr_addr)
        CSR_MSTATUS: begin mstatus_mie <= csr_wdata[3]; mstatus_mpie <= csr_wdata[7]; end
        CSR_MTVEC:   mtvec <= csr_wdata[31:2];
        CSR_MEPC:    mepc  <= csr_wdata[31:2];
        CSR_MCAUSE:  begin mcause_int <= csr_wdata[31]; mcause_code <= csr_wdata[3:0]; end
        default: ;
      endcase
    end
  end

  // ---------------------------------------------------------------- redirect and writeback
  assign fencei         = fire && !exc.valid && r.fencei;
  assign redirect_valid = trap || mret || fencei;
  assign redirect_pc    = trap ? {mtvec, 2'b00} : mret ? {mepc, 2'b00} : r.pc + 32'd4;

  assign fwd.valid = valid && r.rd_wen;
  assign fwd.rd    = r.rd;
  assign fwd.ready = r.wbsel == WB_ALU;
  assign fwd.data  = r.result;

  always_comb begin
    out_bits.pc         = r.pc;
    out_bits.rd         = r.rd;
    out_bits.rd_wen     = r.rd_wen && !exc.valid;
    out_bits.wdata      = r.wbsel == WB_MEM ? load_val : r.wbsel == WB_CSR ? csr_rdata : r.result;
    out_bits.trap       = exc.valid;
    out_bits.ebreak     = r.ebreak;
    out_bits.skip       = r.csr_op != CSR_NONE &&
                          (r.csr_addr == CSR_MVENDORID || r.csr_addr == CSR_MARCHID);
    out_bits.mem_access = mem_go;
    out_bits.mem_addr   = r.result;
  end

endmodule
