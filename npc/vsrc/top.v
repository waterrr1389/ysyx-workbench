`include "ctrl_defs.vh"

module top(
    input clk,
    input reset,
    output [31:0] pc
);
    import "DPI-C" function int pmem_read(input int raddr);
    import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

    wire [31:0] pc_val, pc_next, pc_plus_4;
    wire pc_wen;
    wire [31:0] inst;

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

    assign pc_wen = !reset;
    assign pc_plus_4 = pc_val + 32'd4;
    assign inst = reset ? 32'h00000013 : pmem_read(pc_val);
    assign mem_rdata = (mem_en && !mem_we) ? pmem_read(mem_addr) : 32'b0;
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

    RegisterFile #(5, 32) rf0 (
        .wen(reg_wen_wire),
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
        .alu_result(alu_result),
        .branch_taken(branch_taken),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wmask(mem_wmask),
        .load_result(load_result)
    );

    always @(posedge clk) begin
        if (!reset && mem_en && mem_we) begin
            pmem_write(mem_addr, mem_wdata, {4'b0, mem_wmask});
        end
    end

endmodule
