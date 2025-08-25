module axi4_lite_slave #(
    parameter ADDRESS     = 32,
    parameter DATA_WIDTH  = 32,
    parameter REG_COUNT   = 32
) (
    // Global
    input  wire                        ACLK,
    input  wire                        ARESETN,
    // Read Address
    input  wire [ADDRESS-1:0]          S_ARADDR,
    input  wire                        S_ARVALID,
    output wire                        S_ARREADY,
    // Read Data
    output reg  [DATA_WIDTH-1:0]       S_RDATA,
    output reg  [1:0]                  S_RRESP,
    output reg                         S_RVALID,
    input  wire                        S_RREADY,
    // Write Address
    input  wire [ADDRESS-1:0]          S_AWADDR,
    input  wire                        S_AWVALID,
    output wire                        S_AWREADY,
    // Write Data
    input  wire [DATA_WIDTH-1:0]       S_WDATA,
    input  wire [(DATA_WIDTH/8)-1:0]   S_WSTRB,
    input  wire                        S_WVALID,
    output wire                        S_WREADY,
    // Write Response
    output reg  [1:0]                  S_BRESP,
    output reg                         S_BVALID,
    input  wire                        S_BREADY
);

    // Local Parameters
    function integer clog2;
        input integer value;
        integer i;
        begin
            clog2 = 0;
            for (i = value - 1; i > 0; i = i >> 1)
                clog2 = clog2 + 1;
        end
    endfunction

    localparam ADDR_LSB    = (DATA_WIDTH == 64) ? 3 :
                              (DATA_WIDTH == 32) ? 2 :
                              (DATA_WIDTH == 16) ? 1 : 0;
    localparam REG_INDEX_W = (REG_COUNT <= 1) ? 1 : clog2(REG_COUNT);
    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

   //Register file
    reg [DATA_WIDTH-1:0] regs [0:REG_COUNT-1];

    
  //Write Channel 
    parameter W_IDLE = 1'b0, W_RESP = 1'b1;
    reg wstate;

    reg aw_captured, w_captured;
    reg [ADDRESS-1:0]        awaddr_r;
    reg [DATA_WIDTH-1:0]     wdata_r;
    reg [(DATA_WIDTH/8)-1:0] wstrb_r;

    assign S_AWREADY = (wstate == W_IDLE) && !aw_captured;
    assign S_WREADY  = (wstate == W_IDLE) && !w_captured;

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            aw_captured <= 1'b0;
            w_captured  <= 1'b0;
            awaddr_r    <= {ADDRESS{1'b0}};
            wdata_r     <= {DATA_WIDTH{1'b0}};
            wstrb_r     <= {(DATA_WIDTH/8){1'b0}};
        end else begin
            if (S_AWREADY && S_AWVALID) begin
                aw_captured <= 1'b1;
                awaddr_r    <= S_AWADDR;
            end
            if (S_WREADY && S_WVALID) begin
                w_captured <= 1'b1;
                wdata_r    <= S_WDATA;
                wstrb_r    <= S_WSTRB;
            end
            if (wstate == W_RESP && S_BVALID && S_BREADY) begin
                aw_captured <= 1'b0;
                w_captured  <= 1'b0;
            end
        end
    end

    // Decode helpers
    wire [REG_INDEX_W-1:0] w_index;
    wire w_align_ok, w_in_range, w_has_strobes;

    assign w_align_ok    = (awaddr_r[ADDR_LSB-1:0] == {ADDR_LSB{1'b0}});
    assign w_index       = awaddr_r[ADDR_LSB + REG_INDEX_W - 1 -: REG_INDEX_W];
    assign w_in_range    = (w_index < REG_COUNT);
    assign w_has_strobes = |wstrb_r;

    function [DATA_WIDTH-1:0] apply_wstrb;
        input [DATA_WIDTH-1:0] oldv;
        input [DATA_WIDTH-1:0] newv;
        input [(DATA_WIDTH/8)-1:0] strb;
        integer b;
        reg [DATA_WIDTH-1:0] res;
        begin
            res = oldv;
            for (b = 0; b < DATA_WIDTH/8; b = b + 1) begin
                if (strb[b]) res[b*8 +: 8] = newv[b*8 +: 8];
            end
            apply_wstrb = res;
        end
    endfunction

    always @(posedge ACLK or negedge ARESETN) begin
        integer i;
        if (!ARESETN) begin
            wstate   <= W_IDLE;
            S_BVALID <= 1'b0;
            S_BRESP  <= RESP_OKAY;
            for (i = 0; i < REG_COUNT; i = i + 1)
                regs[i] <= {DATA_WIDTH{1'b0}};
        end else begin
            case (wstate)
                W_IDLE: begin
                    S_BVALID <= 1'b0;
                    if (aw_captured && w_captured) begin
                        if (w_align_ok && w_in_range && w_has_strobes) begin
                            S_BRESP <= RESP_OKAY;
                            regs[w_index] <= apply_wstrb(regs[w_index], wdata_r, wstrb_r);
                        end else begin
                            S_BRESP <= RESP_SLVERR;
                        end
                        S_BVALID <= 1'b1;
                        wstate   <= W_RESP;
                    end
                end
                W_RESP: begin
                    if (S_BVALID && S_BREADY) begin
                        S_BVALID <= 1'b0;
                        wstate   <= W_IDLE;
                    end
                end
            endcase
        end
    end

  
    //Read Channel
    parameter R_IDLE = 1'b0, R_DATA = 1'b1;
    reg rstate;

    reg [ADDRESS-1:0]     araddr_r;
    reg [REG_INDEX_W-1:0] r_index;
    reg                   r_align_ok, r_in_range;

    assign S_ARREADY = (rstate == R_IDLE);

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            rstate     <= R_IDLE;
            araddr_r   <= {ADDRESS{1'b0}};
            r_align_ok <= 1'b0;
            r_in_range <= 1'b0;
            r_index    <= {REG_INDEX_W{1'b0}};
            S_RDATA    <= {DATA_WIDTH{1'b0}};
            S_RRESP    <= RESP_OKAY;
            S_RVALID   <= 1'b0;
        end else begin
            case (rstate)
                R_IDLE: begin
                    S_RVALID <= 1'b0;
                    if (S_ARVALID && S_ARREADY) begin
                        araddr_r   <= S_ARADDR;
                        r_align_ok <= (S_ARADDR[ADDR_LSB-1:0] == {ADDR_LSB{1'b0}});
                        r_index    <= S_ARADDR[ADDR_LSB + REG_INDEX_W - 1 -: REG_INDEX_W];
                        r_in_range <= (S_ARADDR[ADDR_LSB + REG_INDEX_W - 1 -: REG_INDEX_W] < REG_COUNT);
                        rstate     <= R_DATA;
                    end
                end
                R_DATA: begin
                    if (r_align_ok && r_in_range) begin
                        S_RRESP <= RESP_OKAY;
                        S_RDATA <= regs[r_index];
                    end else begin
                        S_RRESP <= RESP_SLVERR;
                        S_RDATA <= {DATA_WIDTH{1'b0}};
                    end
                    S_RVALID <= 1'b1;
                    if (S_RVALID && S_RREADY) begin
                        S_RVALID <= 1'b0;
                        rstate   <= R_IDLE;
                    end
                end
            endcase
        end
    end

    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars();
    end

endmodule
