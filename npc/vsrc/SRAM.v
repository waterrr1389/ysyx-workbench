// SimpleBus slave backed by pmem, answering every request after one cycle.
module SRAM #(DATA_LEN = 32) (
    input clk,
    input reset,

    input req_valid,
    input [DATA_LEN-1:0] req_addr,
    input req_wen,
    input [DATA_LEN-1:0] req_wdata,
    input [3:0] req_wmask,
    output reg rvalid,
    output reg [DATA_LEN-1:0] rdata,
    output reg bvalid
);

    import "DPI-C" function int pmem_read(input int raddr);
    import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

    always @(posedge clk) begin
        rdata <= (req_valid && !req_wen) ? pmem_read(req_addr) : 0;
        if (req_valid && req_wen) pmem_write(req_addr, req_wdata, {4'b0, req_wmask});
    end

    always @(posedge clk) begin
        if (reset) begin
            rvalid <= 0;
            bvalid <= 0;
        end else begin
            rvalid <= req_valid && !req_wen;
            bvalid <= req_valid && req_wen;
        end
    end
endmodule
