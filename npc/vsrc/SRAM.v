module SRAM #(DATA_LEN = 32) (
    input clk,
    input reset,

    input arvalid,
    output reg arready,
    input [DATA_LEN-1:0] araddr,

    output reg rvalid,
    input rready,
    output reg [DATA_LEN-1:0] rdata,
    output [1:0] rresp,

    input awvalid,
    output reg awready,
    input [DATA_LEN-1:0] awaddr,

    input wvalid,
    output reg wready,
    input [DATA_LEN-1:0] wdata,
    input [3:0] wstrb,

    output reg bvalid,
    input bready,
    output [1:0] bresp
);

    import "DPI-C" function int pmem_read(input int raddr);
    import "DPI-C" function void pmem_write(input int waddr, input int wdata, input byte wmask);

    localparam [2:0] SRAM_IDLE = 3'd0;
    localparam [2:0] SRAM_AW   = 3'd1;  // Address saved; wait for write data.
    localparam [2:0] SRAM_W    = 3'd2;  // Write data saved; wait for the address.
    localparam [2:0] SRAM_R    = 3'd3;
    localparam [2:0] SRAM_B    = 3'd4;

    reg [2:0] state, next_state;

    reg [DATA_LEN-1:0] awaddr_q;
    reg [DATA_LEN-1:0] wdata_q;
    reg [3:0] wstrb_q;

    wire ar_fire = arvalid && arready;
    wire r_fire  = rvalid && rready;
    wire aw_fire = awvalid && awready;
    wire w_fire  = wvalid && wready;
    wire b_fire  = bvalid && bready;

    always @(posedge clk) begin
        if (reset) state <= SRAM_IDLE;
        else       state <= next_state;
    end

    // Choose the next state.
    always @(*) begin
        next_state = state;

        case (state)
            SRAM_IDLE: begin
                if (ar_fire)
                    next_state = SRAM_R;
                else if (aw_fire && w_fire)
                    next_state = SRAM_B;
                else if (aw_fire)
                    next_state = SRAM_AW;
                else if (w_fire)
                    next_state = SRAM_W;
            end

            SRAM_AW: begin
                if (w_fire)
                    next_state = SRAM_B;
            end

            SRAM_W: begin
                if (aw_fire)
                    next_state = SRAM_B;
            end

            SRAM_R: begin
                if (r_fire)
                    next_state = SRAM_IDLE;
            end

            SRAM_B: begin
                if (b_fire)
                    next_state = SRAM_IDLE;
            end

            default: begin
                next_state = SRAM_IDLE;
            end
        endcase
    end

    // Set the outputs for the current state.
    always @(*) begin
        arready = 1'b0;
        awready = 1'b0;
        wready  = 1'b0;
        rvalid  = 1'b0;
        bvalid  = 1'b0;

        case (state)
            SRAM_IDLE: begin
                // The arbiter sends either a read or a write, never both at once.
                arready = 1'b1;
                awready = 1'b1;
                wready  = 1'b1;
            end
            SRAM_AW: begin
                wready = 1'b1;
            end
            SRAM_W: begin
                awready = 1'b1;
            end
            SRAM_R: begin
                rvalid = 1'b1;
            end
            SRAM_B: begin 
                bvalid = 1'b1;
            end
            default: begin
            end
        endcase
    end

    // Read once when the address is accepted. Hold the data until it is taken.
    always @(posedge clk) begin
        if (reset) begin
            rdata <= 0;
        end else if (ar_fire) begin
            rdata <= pmem_read(araddr);
        end else begin
            rdata <= rdata;
        end
    end

    // Save each part when it arrives. Write once both address and data are ready.
    always @(posedge clk) begin
        if (reset) begin
            awaddr_q <= 0;
            wdata_q  <= 0;
            wstrb_q  <= 0;
        end else begin
            if (aw_fire)
                awaddr_q <= awaddr;

            if (w_fire) begin
                wdata_q <= wdata;
                wstrb_q <= wstrb;
            end

            case (state)
                SRAM_IDLE: begin
                    if (aw_fire && w_fire)
                        pmem_write(awaddr, wdata, {4'b0, wstrb});
                end

                SRAM_AW: begin
                    if (w_fire)
                        pmem_write(awaddr_q, wdata, {4'b0, wstrb});
                end

                SRAM_W: begin
                    if (aw_fire)
                        pmem_write(awaddr, wdata_q, {4'b0, wstrb_q});
                end

                default: begin
                end
            endcase
        end
    end

        
    assign rresp = 2'b00;  // OKAY
    assign bresp = 2'b00;  // OKAY
endmodule
