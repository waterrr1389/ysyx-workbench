`include "ctrl_defs.vh"

module top(
    input clk,
    input reset,
    output [31:0] pc
);
    wire [31:0] pc_val, pc_next, pc_plus_4;
    wire pc_wen;
    wire [31:0] inst;
    wire inst_valid;
    wire inst_done;

    wire ifu_reqValid, ifu_reqReady;
    wire [31:0] ifu_addr;
    wire ifu_rrespValid, ifu_rrespReady;
    wire [31:0] ifu_rdata;

    wire lsu_reqValid, lsu_reqReady;
    wire [31:0] lsu_addr;
    wire lsu_wen;
    wire [31:0] lsu_wdata;
    wire [3:0] lsu_wmask;
    wire lsu_rrespValid, lsu_rrespReady;
    wire [31:0] lsu_rdata;
    wire lsu_wrespValid, lsu_wrespReady;

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

    IFU #(32) ifu (
        .clk(clk),
        .reset(reset),
        .pc(pc_val),
        .inst_done(inst_done),
        .inst(inst),
        .inst_valid(inst_valid),
        .reqValid(ifu_reqValid),
        .reqReady(ifu_reqReady),
        .addr(ifu_addr),
        .rrespValid(ifu_rrespValid),
        .rrespReady(ifu_rrespReady),
        .rdata(ifu_rdata)
    );

    SRAM #(32, 1) ifu_sram (
        .clk(clk),
        .reset(reset),
        .reqValid(ifu_reqValid),
        .reqReady(ifu_reqReady),
        .addr(ifu_addr),
        .wen(1'b0),
        .wdata(32'b0),
        .wmask(4'b0),
        .rrespValid(ifu_rrespValid),
        .rrespReady(ifu_rrespReady),
        .rdata(ifu_rdata),
        .wrespValid(),
        .wrespReady(1'b0)
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
        .reqValid(lsu_reqValid),
        .reqReady(lsu_reqReady),
        .addr(lsu_addr),
        .wen(lsu_wen),
        .wdata(lsu_wdata),
        .wmask(lsu_wmask),
        .rrespValid(lsu_rrespValid),
        .rrespReady(lsu_rrespReady),
        .rdata(lsu_rdata),
        .wrespValid(lsu_wrespValid),
        .wrespReady(lsu_wrespReady)
    );

    SRAM #(32, 1) lsu_sram (
        .clk(clk),
        .reset(reset),
        .reqValid(lsu_reqValid),
        .reqReady(lsu_reqReady),
        .addr(lsu_addr),
        .wen(lsu_wen),
        .wdata(lsu_wdata),
        .wmask(lsu_wmask),
        .rrespValid(lsu_rrespValid),
        .rrespReady(lsu_rrespReady),
        .rdata(lsu_rdata),
        .wrespValid(lsu_wrespValid),
        .wrespReady(lsu_wrespReady)
    );

endmodule
