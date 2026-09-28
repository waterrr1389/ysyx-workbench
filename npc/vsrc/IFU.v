module IFU #(DATA_LEN = 32) (
    input clk,
    input reset,
    input [DATA_LEN-1:0] pc,
    output [DATA_LEN-1:0] inst,
    output inst_valid
);

    import "DPI-C" function int pmem_read(input int raddr);

    localparam [0:0] IFU_IDLE = 1'b0;
    localparam [0:0] IFU_WAIT = 1'b1;

    reg [0:0] state;
    reg [DATA_LEN-1:0] ifu_rdata;

    // TODO: state transition, ifu_rdata read, inst / inst_valid

endmodule
