`ifndef VERILATOR
module testbench;
  reg [4095:0] vcdfile;
  reg clock;
`else
module testbench(input clock, output reg genclock);
  initial genclock = 1;
`endif
  reg genclock = 1;
  reg [31:0] cycle = 0;
  reg [3:0] PI_wmask;
  reg [31:0] PI_wdata;
  reg [0:0] PI_wen;
  reg [0:0] PI_reset;
  reg [0:0] PI_rrespReady;
  reg [31:0] PI_addr;
  wire [0:0] PI_clk = clock;
  reg [0:0] PI_reqValid;
  reg [0:0] PI_wrespReady;
  sram_formal UUT (
    .wmask(PI_wmask),
    .wdata(PI_wdata),
    .wen(PI_wen),
    .reset(PI_reset),
    .rrespReady(PI_rrespReady),
    .addr(PI_addr),
    .clk(PI_clk),
    .reqValid(PI_reqValid),
    .wrespReady(PI_wrespReady)
  );
`ifndef VERILATOR
  initial begin
    if ($value$plusargs("vcd=%s", vcdfile)) begin
      $dumpfile(vcdfile);
      $dumpvars(0, testbench);
    end
    #5 clock = 0;
    while (genclock) begin
      #5 clock = 0;
      #5 clock = 1;
    end
  end
`endif
  initial begin
`ifndef VERILATOR
    #1;
`endif
    // UUT.$auto$async2sync.\cc:107:execute$204  = 1'b0;
    // UUT.$auto$async2sync.\cc:107:execute$210  = 1'b0;
    // UUT.$auto$async2sync.\cc:107:execute$216  = 1'b0;
    // UUT.$auto$async2sync.\cc:116:execute$202  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$208  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$214  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$220  = 1'b1;
    UUT._witness_.anyinit_procdff_188 = 1'b0;
    UUT._witness_.anyinit_procdff_189 = 1'b0;
    UUT._witness_.anyinit_procdff_190 = 32'b00000000000000000000000000000000;
    UUT._witness_.anyinit_procdff_191 = 1'b0;
    UUT._witness_.anyinit_procdff_192 = 1'b0;
    UUT.dut.delay_cnt = 3'b000;
    UUT.dut.lfsr.out = 8'b00000000;
    UUT.dut.rdata = 32'b00000000000000000000000000000000;
    UUT.dut.resp_is_write = 1'b0;
    UUT.dut.state = 2'b00;
    UUT.f_outstanding = 2'b10;
    UUT.f_past_valid = 1'b0;
    UUT.f_wait = 4'b0000;
    UUT.f_wen = 1'b0;

    // state 0
    PI_wmask = 4'b0000;
    PI_wdata = 32'b00000000000000000000000000000000;
    PI_wen = 1'b0;
    PI_reset = 1'b1;
    PI_rrespReady = 1'b0;
    PI_addr = 32'b00000000000000000000000000000000;
    PI_reqValid = 1'b0;
    PI_wrespReady = 1'b0;
    UUT.dut.f_mem_rdata = 32'b00000000000000000000000000000000;
  end
  always @(posedge clock) begin
    // state 1
    if (cycle == 0) begin
      PI_wmask <= 4'b0000;
      PI_wdata <= 32'b00000000000000000000000000000000;
      PI_wen <= 1'b0;
      PI_reset <= 1'b0;
      PI_rrespReady <= 1'b0;
      PI_addr <= 32'b00000000000000000000000000000000;
      PI_reqValid <= 1'b1;
      PI_wrespReady <= 1'b0;
      UUT.dut.f_mem_rdata <= 32'b00000000000000000000000000000000;
    end

    // state 2
    if (cycle == 1) begin
      PI_wmask <= 4'b0000;
      PI_wdata <= 32'b00000000000000000000000000000000;
      PI_wen <= 1'b0;
      PI_reset <= 1'b0;
      PI_rrespReady <= 1'b0;
      PI_addr <= 32'b00000000000000000000000000000000;
      PI_reqValid <= 1'b0;
      PI_wrespReady <= 1'b0;
      UUT.dut.f_mem_rdata <= 32'b00000000000000000000000000000000;
    end

    genclock <= cycle < 2;
    cycle <= cycle + 1;
  end
endmodule
