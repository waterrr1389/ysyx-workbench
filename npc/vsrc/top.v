module top(
    input clk,
    input reset,
    input [31:0] inst,
    output [31:0] pc
);

    wire [31:0] pc_val, pc_next, pc_plus_4;
    wire pc_wen;
    wire pc_sel; // 从 IDU 引出的 PC 选择信号

    assign pc_wen = !reset;
    assign pc_plus_4 = pc_val + 32'd4;
    
    // pc_sel 为 1 时，跳到 ALU 算出来的地址
    assign pc_next = pc_sel ? {execution_result[31:1], 1'b0} : pc_plus_4;

    Reg #(32, 32'h80000000) programcouter (
        .clk(clk), 
        .rst(reset), 
        .dout(pc_val), 
        .din(pc_next), 
        .wen(pc_wen)
    );
    assign pc = pc_val;


    wire [31:0] rs1_data, rs2_data;
    wire wb_sel; // 从 IDU 引出的写回选择信号
    wire [31:0] wb_data;

    //  EXU_MUX，wb_sel 为 1 时写回 PC+4 (用于 JAL/JALR)
    assign wb_data = wb_sel ? pc_plus_4 : execution_result;

    RegisterFile #(5, 32) rf0 (
        .wen(reg_wen_wire), 
        .clk(clk),
        .wdata(wb_data), // 【修改】不再硬连到 execution_result，而是连到 MUX 输出
        .waddr(rd_addr),
        .raddr1(rs1_addr),
        .raddr2(rs2_addr),
        .out1(rs1_data),
        .out2(rs2_data)
    );

    wire [4:0] rs1_addr, rs2_addr, rd_addr;
    wire [3:0] sel;
    wire [2:0] inst_type;
    wire reg_wen_wire;
    wire [1:0] op1_sel, op2_sel;

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
        .wb_sel(wb_sel),
        .pc_sel(pc_sel)
    );

    // Immediate Gen
    wire [31:0] imm;
    IMME #(32) imme (
        .inst_type(inst_type),
        .inst(inst),
        .imm(imm)
    );

    wire [31:0] execution_result, op1, op2;
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

    
    // alu
    EXU #(32) alu (
        .a(op1),
        .b(op2),
        .sel(sel),
        .out(execution_result)
    );

    // EXU_MUX #(32) emux (
    //     .inst_type(inst_type),
    //     .

    // );
endmodule
