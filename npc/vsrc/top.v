`include "ctrl_defs.vh"

module top(
    input clk,
    input reset,
    output [31:0] pc,
    // High in the cycle whose clock edge commits the instruction at pc.
    // The harness steps DiffTest and the tracers on it, once per instruction.
    output commit
);
    wire [31:0] pc_val, pc_next, pc_plus_4;
    wire pc_wen;
    wire [31:0] inst;
    wire inst_valid;
    wire inst_done;

    wire ifu_arvalid, ifu_arready;
    wire [31:0] ifu_araddr;
    wire ifu_rvalid, ifu_rready;
    wire [31:0] ifu_rdata;
    wire [1:0] ifu_rresp;

    wire lsu_arvalid, lsu_arready;
    wire [31:0] lsu_araddr;
    wire lsu_rvalid, lsu_rready;
    wire [31:0] lsu_rdata;
    wire [1:0] lsu_rresp;
    wire lsu_awvalid, lsu_awready;
    wire [31:0] lsu_awaddr;
    wire lsu_wvalid, lsu_wready;
    wire [31:0] lsu_wdata;
    wire [3:0] lsu_wstrb;
    wire lsu_bvalid, lsu_bready;
    wire [1:0] lsu_bresp;

    wire sram_arvalid, sram_arready;
    wire [31:0] sram_araddr;
    wire sram_rvalid, sram_rready;
    wire [31:0] sram_rdata;
    wire [1:0] sram_rresp;
    wire sram_awvalid, sram_awready;
    wire [31:0] sram_awaddr;
    wire sram_wvalid, sram_wready;
    wire [31:0] sram_wdata;
    wire [3:0] sram_wstrb;
    wire sram_bvalid, sram_bready;
    wire [1:0] sram_bresp;

    wire [31:0] rs1_data, rs2_data;
    wire [31:0] imm;
    wire [31:0] op1, op2;
    wire [31:0] alu_result;
    wire branch_taken;
    wire [31:0] mem_addr;
    wire [31:0] mem_rdata;
    wire [31:0] mem_wdata;
    wire [31:0] load_result;
    wire [31:0] wb_data;
    wire [31:0] branch_next;
    wire [31:0] jump_target;
    wire [3:0] mem_wmask;

    wire [4:0] rs1_addr, rs2_addr, rd_addr;
    wire [3:0] sel;
    wire [2:0] inst_type;
    wire reg_wen_wire;
    wire [1:0] op1_sel, op2_sel;
    wire [1:0] wb_src;
    wire [1:0] pc_src;
    wire [2:0] branch_op;
    wire mem_en, mem_we, mem_unsigned;
    wire [1:0] mem_size;

    // GPR and PC commit only when inst_done is high; Mem is written by the LSU
    // once per instruction. In every other cycle the processor must hold still.
    assign pc_wen = !reset && inst_done;
    assign pc_plus_4 = pc_val + 32'd4;
    assign jump_target = {alu_result[31:1], 1'b0};

    MuxKeyWithDefault #(2, 1, 32) BranchNextMux (
        branch_next,
        branch_taken,
        pc_plus_4,
        {
            1'b0, pc_plus_4,
            1'b1, alu_result
        }
    );

    MuxKeyWithDefault #(3, 2, 32) PcMux (
        pc_next,
        pc_src,
        pc_plus_4,
        {
            `PC_SRC_SEQ, pc_plus_4,
            `PC_SRC_TARGET, jump_target,
            `PC_SRC_BRANCH, branch_next
        }
    );
    
    MuxKeyWithDefault #(3, 2, 32) WbMux (
        wb_data,
        wb_src,
        alu_result,
        {
            `WB_SRC_ALU, alu_result,
            `WB_SRC_PC4, pc_plus_4,
            `WB_SRC_LOAD, load_result
        }
    );


    Reg #(32, 32'h80000000) programcouter (
        .clk(clk),
        .rst(reset),
        .dout(pc_val),
        .din(pc_next),
        .wen(pc_wen)
    );
    assign pc = pc_val;
    assign commit = pc_wen;

    IFU #(32) ifu (
        .clk(clk),
        .reset(reset),
        .pc(pc_val),
        .inst_done(inst_done),
        .inst(inst),
        .inst_valid(inst_valid),
        .arvalid(ifu_arvalid),
        .arready(ifu_arready),
        .araddr(ifu_araddr),
        .rvalid(ifu_rvalid),
        .rready(ifu_rready),
        .rdata(ifu_rdata),
        .rresp(ifu_rresp)
    );

    RegisterFile #(5, 32) rf0 (
        .wen(reg_wen_wire && inst_done),
        .clk(clk),
        .wdata(wb_data),
        .waddr(rd_addr),
        .raddr1(rs1_addr),
        .raddr2(rs2_addr),
        .out1(rs1_data),
        .out2(rs2_data)
    );

    IDU #(32, 5) idu(
        .inst(inst),
        .rs1(rs1_addr),
        .rs2(rs2_addr),
        .rd(rd_addr),
        .sel(sel),
        .inst_type(inst_type),
        .reg_wen(reg_wen_wire),
        .op1_sel(op1_sel),
        .op2_sel(op2_sel),
        .wb_src(wb_src),
        .pc_src(pc_src),
        .branch_op(branch_op),
        .mem_en(mem_en),
        .mem_we(mem_we),
        .mem_size(mem_size),
        .mem_unsigned(mem_unsigned)
    );

    IMME #(32) imme (
        .inst_type(inst_type),
        .inst(inst),
        .imm(imm)
    );

    OP1 #(32) op1_mux (
        .rs1(rs1_data),
        .pc(pc),
        .op1_sel(op1_sel),
        .op1(op1)
    );

    OP2 #(32) op2_mux (
        .rs2(rs2_data),
        .imm(imm),
        .op2_sel(op2_sel),
        .op2(op2)
    );

    EXU #(32) alu (
        .a(op1),
        .b(op2),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .mem_rdata(mem_rdata),
        .sel(sel),
        .branch_op(branch_op),
        .mem_en(mem_en),
        .mem_we(mem_we),
        .mem_size(mem_size),
        .mem_unsigned(mem_unsigned),
        .inst_done(inst_done),
        .alu_result(alu_result),
        .branch_taken(branch_taken),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wmask(mem_wmask),
        .load_result(load_result)
    );

    LSU #(32) lsu (
        .clk(clk),
        .reset(reset),
        .inst_valid(inst_valid),
        .mem_en(mem_en),
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wmask(mem_wmask),
        .mem_rdata(mem_rdata),
        .inst_done(inst_done),
        .arvalid(lsu_arvalid),
        .arready(lsu_arready),
        .araddr(lsu_araddr),
        .rvalid(lsu_rvalid),
        .rready(lsu_rready),
        .rdata(lsu_rdata),
        .rresp(lsu_rresp),
        .awvalid(lsu_awvalid),
        .awready(lsu_awready),
        .awaddr(lsu_awaddr),
        .wvalid(lsu_wvalid),
        .wready(lsu_wready),
        .wdata(lsu_wdata),
        .wstrb(lsu_wstrb),
        .bvalid(lsu_bvalid),
        .bready(lsu_bready),
        .bresp(lsu_bresp)
    );

    Arbiter arbiter (
        .clk(clk),
        .reset(reset),
        .ifu_arvalid(ifu_arvalid),
        .ifu_arready(ifu_arready),
        .ifu_araddr(ifu_araddr),
        .ifu_rvalid(ifu_rvalid),
        .ifu_rready(ifu_rready),
        .ifu_rdata(ifu_rdata),
        .ifu_rresp(ifu_rresp),
        .lsu_arvalid(lsu_arvalid),
        .lsu_arready(lsu_arready),
        .lsu_araddr(lsu_araddr),
        .lsu_rvalid(lsu_rvalid),
        .lsu_rready(lsu_rready),
        .lsu_rdata(lsu_rdata),
        .lsu_rresp(lsu_rresp),
        .lsu_awvalid(lsu_awvalid),
        .lsu_awready(lsu_awready),
        .lsu_awaddr(lsu_awaddr),
        .lsu_wvalid(lsu_wvalid),
        .lsu_wready(lsu_wready),
        .lsu_wdata(lsu_wdata),
        .lsu_wstrb(lsu_wstrb),
        .lsu_bvalid(lsu_bvalid),
        .lsu_bready(lsu_bready),
        .lsu_bresp(lsu_bresp),
        .s_arvalid(sram_arvalid),
        .s_arready(sram_arready),
        .s_araddr(sram_araddr),
        .s_rvalid(sram_rvalid),
        .s_rready(sram_rready),
        .s_rdata(sram_rdata),
        .s_rresp(sram_rresp),
        .s_awvalid(sram_awvalid),
        .s_awready(sram_awready),
        .s_awaddr(sram_awaddr),
        .s_wvalid(sram_wvalid),
        .s_wready(sram_wready),
        .s_wdata(sram_wdata),
        .s_wstrb(sram_wstrb),
        .s_bvalid(sram_bvalid),
        .s_bready(sram_bready),
        .s_bresp(sram_bresp)
    );

    SRAM #(32) sram (
        .clk(clk),
        .reset(reset),
        .arvalid(sram_arvalid),
        .arready(sram_arready),
        .araddr(sram_araddr),
        .rvalid(sram_rvalid),
        .rready(sram_rready),
        .rdata(sram_rdata),
        .rresp(sram_rresp),
        .awvalid(sram_awvalid),
        .awready(sram_awready),
        .awaddr(sram_awaddr),
        .wvalid(sram_wvalid),
        .wready(sram_wready),
        .wdata(sram_wdata),
        .wstrb(sram_wstrb),
        .bvalid(sram_bvalid),
        .bready(sram_bready),
        .bresp(sram_bresp)
    );

endmodule
