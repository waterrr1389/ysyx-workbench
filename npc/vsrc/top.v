module top(
    input clk,
    input reset,
    input [31:0] inst,
    output [31:0] pc
);
    //TODO: PC选择器,区分control transfer指令
    /**
        Program Counter
        Data-32bit
    **/
    wire [31:0] pc_val, pc_next;
    wire pc_wen;
    assign pc_wen = !reset;
    assign pc_next = pc_val + 32'd4;
    Reg #(32, 32'h80000000) programcouter (
        .clk(clk), 
        .rst(reset), 
        .dout(pc_val), 
        .din(pc_next), 
        .wen(pc_wen)
        );

    assign pc = pc_val;

    /** 
        RegisterFIle
        Data-32bit
        Addr-5bit->32GPRS
    **/
    wire [31:0] rs1_data, rs2_data;
    RegisterFile #(5, 32) rf0 (
        .wen(reg_wen_wire), // 根据指令类型判断,写入内存时,en为0
        .clk(clk),
        .wdata(execution_result),
        .waddr(rd_addr),
        .raddr1(rs1_addr),
        .raddr2(rs2_addr),
        .out1(rs1_data),
        .out2(rs2_data)
    );

    /*
        我们暂时使用c++实现取指令
    */

    /*
        IDU
    */
    wire [4:0] rs1_addr, rs2_addr, rd_addr;
    wire [3:0] exu_mode;
    wire [11:0] imm_wire;
    wire reg_wen_wire;
    IDU #(32, 5) idu(
        .inst(inst),
        .rs1(rs1_addr),
        .rs2(rs2_addr),
        .rd(rd_addr),
        .imm(imm_wire),
        .sel(exu_mode),
        .reg_wen(reg_wen_wire),
        .imm_or_reg(sel_imm_or_reg)
    );

    wire sel_imm_or_reg;
    // 根据解码出的信息,决定第二个操作数是寄存器值还是立即数
    MuxKey #(2, 1, 32) mux_imm_or_reg (op2, sel_imm_or_reg, {
        1'b0, rs2_data,
        1'b1, {{20{imm_wire[11]}}, imm_wire}
    });

    wire [31:0] execution_result, op1, op2;
    assign op1 = rs1_data;
    
    // ALU
    EXU #(32) alu (
        .a(op1),
        .b(op2),
        .sel(exu_mode),
        .out(execution_result)
    );

endmodule
