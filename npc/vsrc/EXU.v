`include "alu_ops.vh"
`include "ctrl_defs.vh"

module EXU #(DATA_LEN = 1) (
    input [DATA_LEN-1:0] a,
    input [DATA_LEN-1:0] b,
    input [DATA_LEN-1:0] rs1_data,
    input [DATA_LEN-1:0] rs2_data,
    input [DATA_LEN-1:0] mem_rdata,
    input [3:0] sel,
    input [2:0] branch_op,
    input mem_en,
    input mem_we,
    input [1:0] mem_size,
    input mem_unsigned,
    output reg [DATA_LEN-1:0] alu_result,
    output reg branch_taken,
    output [DATA_LEN-1:0] mem_addr,
    output reg [DATA_LEN-1:0] mem_wdata,
    output reg [3:0] mem_wmask,
    output reg [DATA_LEN-1:0] load_result
);
    wire [DATA_LEN:0] sub_tmp;
    wire sub_OF;
    wire [4:0] shamt = b[4:0];
    wire [DATA_LEN-1:0] sub_b = ~b;
    wire signed_lt = sub_tmp[DATA_LEN-1] ^ sub_OF;
    wire unsigned_lt = $unsigned(a) < $unsigned(b);
    wire signed_branch_lt = $signed(rs1_data) < $signed(rs2_data);
    wire unsigned_branch_lt = $unsigned(rs1_data) < $unsigned(rs2_data);
    wire [1:0] byte_off = alu_result[1:0];

    assign sub_tmp = a + sub_b + 1;
    assign sub_OF = (a[DATA_LEN-1] == sub_b[DATA_LEN-1]) &
        (sub_tmp[DATA_LEN-1] != a[DATA_LEN-1]);
    assign mem_addr = {alu_result[DATA_LEN-1:2], 2'b00};

    import "DPI-C" function void npc_trap();

    always @(*) begin
        alu_result = {DATA_LEN{1'b0}};
        case (sel)
            `ALU_ADD: begin
                alu_result = a + b;
            end
            `ALU_SUB: begin
                alu_result = sub_tmp[DATA_LEN-1:0];
            end
            `ALU_NOT: begin
                alu_result = ~a;
            end
            `ALU_AND: begin
                alu_result = a & b;
            end
            `ALU_OR: begin
                alu_result = a | b;
            end
            `ALU_XOR: begin
                alu_result = a ^ b;
            end
            `ALU_SLT: begin
                alu_result = {{(DATA_LEN-1){1'b0}}, signed_lt};
            end
            `ALU_SEQ: begin
                alu_result = {{(DATA_LEN-1){1'b0}}, a == b};
            end
            `ALU_SLL: begin
                alu_result = a << shamt;
            end
            `ALU_SRL: begin
                alu_result = a >> shamt;
            end
            `ALU_SRA: begin
                alu_result = $signed(a) >>> shamt;
            end
            `ALU_SLTU: begin
                alu_result = {{(DATA_LEN-1){1'b0}}, unsigned_lt};
            end
            `ALU_EBREAK: begin
                npc_trap();
            end
            default: begin
                alu_result = {DATA_LEN{1'b0}};
            end
        endcase
    end

    always @(*) begin
        branch_taken = 1'b0;
        case (branch_op)
            `BR_BEQ: begin
                branch_taken = rs1_data == rs2_data;
            end
            `BR_BNE: begin
                branch_taken = rs1_data != rs2_data;
            end
            `BR_BLT: begin
                branch_taken = signed_branch_lt;
            end
            `BR_BGE: begin
                branch_taken = !signed_branch_lt;
            end
            `BR_BLTU: begin
                branch_taken = unsigned_branch_lt;
            end
            `BR_BGEU: begin
                branch_taken = !unsigned_branch_lt;
            end
            default: begin
                branch_taken = 1'b0;
            end
        endcase
    end

    always @(*) begin
        load_result = {DATA_LEN{1'b0}};
        // Load 指令时，内存写使能应该为 0
        if (mem_en && !mem_we) begin
            case (mem_size)
                `MEM_SIZE_B: begin
                    case (byte_off)
                        2'b00: load_result = mem_unsigned
                            ? {24'b0, mem_rdata[7:0]}
                            : {{24{mem_rdata[7]}}, mem_rdata[7:0]};
                        2'b01: load_result = mem_unsigned
                            ? {24'b0, mem_rdata[15:8]}
                            : {{24{mem_rdata[15]}}, mem_rdata[15:8]};
                        2'b10: load_result = mem_unsigned
                            ? {24'b0, mem_rdata[23:16]}
                            : {{24{mem_rdata[23]}}, mem_rdata[23:16]};
                        default: load_result = mem_unsigned
                            ? {24'b0, mem_rdata[31:24]}
                            : {{24{mem_rdata[31]}}, mem_rdata[31:24]};
                    endcase
                end
                `MEM_SIZE_H: begin
                    if (byte_off[1]) begin
                        load_result = mem_unsigned
                            ? {16'b0, mem_rdata[31:16]}
                            : {{16{mem_rdata[31]}}, mem_rdata[31:16]};
                    end else begin
                        load_result = mem_unsigned
                            ? {16'b0, mem_rdata[15:0]}
                            : {{16{mem_rdata[15]}}, mem_rdata[15:0]};
                    end
                end
                // size == word 即 4 字节
                default: begin
                    load_result = mem_rdata;
                end
            endcase
        end
    end

    always @(*) begin
        mem_wdata = rs2_data;
        mem_wmask = 4'b0;

        if (mem_en && mem_we) begin
            case (mem_size)
                `MEM_SIZE_B: begin
                    mem_wmask = 4'b0001 << byte_off;
                    case (byte_off)
                        2'b00: mem_wdata = {24'b0, rs2_data[7:0]};
                        2'b01: mem_wdata = {16'b0, rs2_data[7:0], 8'b0};
                        2'b10: mem_wdata = {8'b0, rs2_data[7:0], 16'b0};
                        default: mem_wdata = {rs2_data[7:0], 24'b0};
                    endcase
                end
                `MEM_SIZE_H: begin
                    mem_wmask = byte_off[1] ? 4'b1100 : 4'b0011;
                    mem_wdata = byte_off[1]
                        ? {rs2_data[15:0], 16'b0}
                        : {16'b0, rs2_data[15:0]};
                end
                default: begin
                    mem_wmask = 4'b1111;
                    mem_wdata = rs2_data;
                end
            endcase
        end
    end

endmodule
