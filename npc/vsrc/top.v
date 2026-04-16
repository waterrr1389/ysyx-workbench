module top(
    input clk,
    input reset,
    output [31:0] pc
);
    import "DPI-C" function int pmem_read(input int raddr);
    import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

    wire [31:0] pc_val, pc_next, pc_plus_4;
    wire pc_wen;
    wire pc_sel; // 从 IDU 引出的 PC 选择信号
    wire [31:0] inst;

    assign pc_wen = !reset;
    assign pc_plus_4 = pc_val + 32'd4;
    assign inst = reset ? 32'h00000013 : pmem_read(pc_val);
    
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
    wire [6:0] opcode = inst[6:0];
    wire [2:0] funct3 = inst[14:12];
    wire is_load = opcode == 7'b0000011;
    wire is_store = opcode == 7'b0100011;
    wire is_branch = opcode == 7'b1100011;

    wire [31:0] aligned_addr = {execution_result[31:2], 2'b00};
    wire [1:0] byte_off = execution_result[1:0];
    wire [31:0] mem_word = is_load ? pmem_read(aligned_addr) : 32'b0;
    reg [31:0] load_data;

    reg [31:0] store_wdata;
    reg [7:0] store_wmask;

    // load 指令写回内存读出的数据，其余情况沿用现有 ALU/PC+4 写回路径
    assign wb_data = is_load ? load_data : (wb_sel ? pc_plus_4 : execution_result);

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

    reg branch_taken;
    wire [31:0] branch_target = pc_val + imm;

    // B-type 在 top 中直接决定下一条 PC，避免改动现有 ALU/控制整体结构
    always @(*) begin
        case (funct3)
            3'b000: branch_taken = (rs1_data == rs2_data); // beq
            3'b001: branch_taken = (rs1_data != rs2_data); // bne
            3'b100: branch_taken = ($signed(rs1_data) < $signed(rs2_data)); // blt
            3'b101: branch_taken = ($signed(rs1_data) >= $signed(rs2_data)); // bge
            3'b110: branch_taken = (rs1_data < rs2_data); // bltu
            3'b111: branch_taken = (rs1_data >= rs2_data); // bgeu
            default: branch_taken = 1'b0;
        endcase
    end

    assign pc_next = is_branch
        ? (branch_taken ? branch_target : pc_plus_4)
        : (pc_sel ? {execution_result[31:1], 1'b0} : pc_plus_4);

    
    // alu
    EXU #(32) alu (
        .a(op1),
        .b(op2),
        .sel(sel),
        .out(execution_result)
    );

    always @(*) begin
        load_data = mem_word;
        case (funct3)
            3'b000: begin
                case (byte_off)
                    2'b00: load_data = {{24{mem_word[7]}}, mem_word[7:0]};
                    2'b01: load_data = {{24{mem_word[15]}}, mem_word[15:8]};
                    2'b10: load_data = {{24{mem_word[23]}}, mem_word[23:16]};
                    2'b11: load_data = {{24{mem_word[31]}}, mem_word[31:24]};
                endcase
            end
            3'b001: begin
                load_data = byte_off[1]
                    ? {{16{mem_word[31]}}, mem_word[31:16]}
                    : {{16{mem_word[15]}}, mem_word[15:0]};
            end
            3'b010: begin
                load_data = mem_word;
            end
            3'b100: begin
                case (byte_off)
                    2'b00: load_data = {24'b0, mem_word[7:0]};
                    2'b01: load_data = {24'b0, mem_word[15:8]};
                    2'b10: load_data = {24'b0, mem_word[23:16]};
                    2'b11: load_data = {24'b0, mem_word[31:24]};
                endcase
            end
            3'b101: begin
                load_data = byte_off[1]
                    ? {16'b0, mem_word[31:16]}
                    : {16'b0, mem_word[15:0]};
            end
            default: begin
                load_data = 32'b0;
            end
        endcase
    end

    always @(*) begin
        store_wdata = rs2_data;
        store_wmask = 8'b0;
        case (funct3)
            3'b000: begin
                store_wmask = 8'b0000_0001 << byte_off;
                store_wdata = {24'b0, rs2_data[7:0]} << (byte_off * 8);
            end
            3'b001: begin
                store_wmask = byte_off[1] ? 8'b0000_1100 : 8'b0000_0011;
                store_wdata = {16'b0, rs2_data[15:0]} << (byte_off[1] * 16);
            end
            3'b010: begin
                store_wmask = 8'b0000_1111;
                store_wdata = rs2_data;
            end
            default: begin
                store_wmask = 8'b0;
                store_wdata = rs2_data;
            end
        endcase
    end

    always @(posedge clk) begin
        if (!reset && is_store) begin
            pmem_write(aligned_addr, store_wdata, store_wmask[7:0]);
        end
    end

endmodule
