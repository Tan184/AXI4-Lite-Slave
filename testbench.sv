`timescale 1ns/1ps

module tb_axi4_lite_slave;

    localparam int ADDR_W     = 32;
    localparam int DATA_W     = 32;
    localparam int REG_COUNT  = 32;
    localparam int CLK_PERIOD = 10;

    // DUT I/O
    logic                         ACLK;
    logic                         ARESETN;

    logic [ADDR_W-1:0]            S_ARADDR;
    logic                         S_ARVALID;
    logic                         S_RREADY;
    logic [DATA_W-1:0]            S_RDATA;
    logic [1:0]                   S_RRESP;
    logic                         S_RVALID;

    logic [ADDR_W-1:0]            S_AWADDR;
    logic                         S_AWVALID;
    logic [DATA_W-1:0]            S_WDATA;
    logic [(DATA_W/8)-1:0]        S_WSTRB;
    logic                         S_WVALID;

    logic [1:0]                   S_BRESP;
    logic                         S_BVALID;

    logic                         S_ARREADY, S_AWREADY, S_WREADY;
    logic                         S_BREADY;

    // Instantiate DUT
    axi4_lite_slave #(
        .ADDRESS(ADDR_W),
        .DATA_WIDTH(DATA_W),
        .REG_COUNT(REG_COUNT)
    ) dut (
        .ACLK(ACLK), .ARESETN(ARESETN),
        .S_ARADDR(S_ARADDR), .S_ARVALID(S_ARVALID), .S_ARREADY(S_ARREADY),
        .S_RDATA(S_RDATA), .S_RRESP(S_RRESP), .S_RVALID(S_RVALID), .S_RREADY(S_RREADY),
        .S_AWADDR(S_AWADDR), .S_AWVALID(S_AWVALID), .S_AWREADY(S_AWREADY),
        .S_WDATA(S_WDATA), .S_WSTRB(S_WSTRB), .S_WVALID(S_WVALID), .S_WREADY(S_WREADY),
        .S_BRESP(S_BRESP), .S_BVALID(S_BVALID), .S_BREADY(S_BREADY)
    );

    // Clock
    always #(CLK_PERIOD/2) ACLK = ~ACLK;

    // Shadow model
    logic [DATA_W-1:0] shadow [REG_COUNT];

    // Helpers
    localparam int ADDR_LSB = (DATA_W==64)?3 : (DATA_W==32)?2 : (DATA_W==16)?1 : 0;

    function automatic bit aligned(input [ADDR_W-1:0] a);
        return (a[ADDR_LSB-1:0] == '0);
    endfunction

    function automatic bit in_range(input [ADDR_W-1:0] a);
        int idx;
        idx = a[ADDR_LSB + $clog2(REG_COUNT) - 1 -: $clog2(REG_COUNT)];
        return (idx < REG_COUNT);
    endfunction

    function automatic int idx_of(input [ADDR_W-1:0] a);
        return a[ADDR_LSB + $clog2(REG_COUNT) - 1 -: $clog2(REG_COUNT)];
    endfunction

    function automatic [DATA_W-1:0] mask_write(input [DATA_W-1:0] oldv,
                                               input [DATA_W-1:0] newv,
                                               input [(DATA_W/8)-1:0] strb);
        logic [DATA_W-1:0] r;
        r = oldv;
        for (int b = 0; b < DATA_W/8; b++) if (strb[b]) r[b*8 +: 8] = newv[b*8 +: 8];
        return r;
    endfunction

    // AXI write task
    task automatic axi_write(input [ADDR_W-1:0] addr,
                             input [DATA_W-1:0] data,
                             input [(DATA_W/8)-1:0] strb,
                             input int aw_gap_cycles = 0,
                             input int w_gap_cycles  = 0);
        begin
            S_AWVALID <= 0; S_WVALID <= 0; S_BREADY <= 0;
            @(posedge ACLK);

            if (aw_gap_cycles > 0 || w_gap_cycles == 0) begin
                S_AWADDR  <= addr; S_AWVALID <= 1;
                wait (S_AWREADY);
                @(posedge ACLK); S_AWVALID <= 0;
                repeat (aw_gap_cycles) @(posedge ACLK);
                S_WDATA   <= data; S_WSTRB <= strb; S_WVALID <= 1;
                wait (S_WREADY);
                @(posedge ACLK); S_WVALID <= 0;
            end else begin
                S_WDATA   <= data; S_WSTRB <= strb; S_WVALID <= 1;
                wait (S_WREADY);
                @(posedge ACLK); S_WVALID <= 0;
                repeat (w_gap_cycles) @(posedge ACLK);
                S_AWADDR  <= addr; S_AWVALID <= 1;
                wait (S_AWREADY);
                @(posedge ACLK); S_AWVALID <= 0;
            end

            S_BREADY <= 1;
            wait (S_BVALID);
            $display("[%0t] WRITE  addr=0x%08h data=0x%08h strb=0x%0h -> BRESP=%0d",
                     $time, addr, data, strb, S_BRESP);
            @(posedge ACLK);
            S_BREADY <= 0;
        end
    endtask

    // AXI read task
    task automatic axi_read(input [ADDR_W-1:0] addr,
                            output [DATA_W-1:0] data_o,
                            output [1:0] rresp_o);
        begin
            S_ARADDR  <= addr; S_ARVALID <= 1; S_RREADY <= 1;
            wait (S_ARREADY);
            @(posedge ACLK); S_ARVALID <= 0;
            wait (S_RVALID);
            data_o  = S_RDATA; rresp_o = S_RRESP;
            $display("[%0t] READ   addr=0x%08h -> RDATA=0x%08h RRESP=%0d",
                     $time, addr, data_o, rresp_o);
            @(posedge ACLK); S_RREADY <= 0;
        end
    endtask

    // Check helpers
    task automatic expect_bresp(input [ADDR_W-1:0] addr,
                                input [(DATA_W/8)-1:0] strb,
                                input [1:0] got);
        bit ok;
        logic [1:0] exp;
        ok  = aligned(addr) && in_range(addr) && (|strb);
        exp = ok ? 2'b00 : 2'b10;
        if (got !== exp) begin
            $error("BRESP mismatch: addr=0x%08h exp=%0d got=%0d", addr, exp, got);
            $fatal;
        end
    endtask

    task automatic expect_rresp(input [ADDR_W-1:0] addr, input [1:0] got);
        bit ok;
        logic [1:0] exp;
        ok  = aligned(addr) && in_range(addr);
        exp = ok ? 2'b00 : 2'b10;
        if (got !== exp) begin
            $error("RRESP mismatch: addr=0x%08h exp=%0d got=%0d", addr, exp, got);
            $fatal;
        end
    endtask

    // Declarations
    logic [1:0]        rresp;
    logic [DATA_W-1:0] rdata;

    logic [ADDR_W-1:0] addr5, addr6, addr7, unaligned, oor, addr8, addr9;

    // Test sequence
    initial begin
        ACLK=0; ARESETN=0;
        S_ARADDR=0; S_ARVALID=0; S_RREADY=0;
        S_AWADDR=0; S_AWVALID=0; S_WDATA=0; S_WSTRB=0; S_WVALID=0; S_BREADY=0;

        for (int i=0;i<REG_COUNT;i++) shadow[i] = '0;

        $display("[%0t] Reset asserted", $time);
        repeat (5) @(posedge ACLK);
        ARESETN = 1;
        $display("[%0t] Reset deasserted", $time);
        @(posedge ACLK);

        addr5     = (5 << ADDR_LSB);
        addr6     = (6 << ADDR_LSB);
        addr7     = (7 << ADDR_LSB);
        unaligned = (3 << ADDR_LSB) + 1;
        oor       = (REG_COUNT << ADDR_LSB);
        addr8     = (8 << ADDR_LSB);
        addr9     = (9 << ADDR_LSB);

        // 1) Aligned in-range FULL write/read
        axi_write(addr5, 32'hDEADBEEF, 4'hF, 0, 0);
        expect_bresp(addr5, 4'hF, S_BRESP);
        shadow[5] = 32'hDEADBEEF;
        axi_read(addr5, rdata, rresp);
        expect_rresp(addr5, rresp);
        if (rdata !== shadow[5]) begin $error("Data mismatch at reg 5"); $fatal; end
        $display("Transaction 1 PASSED: Full write/read OK");

        // 2) Partial write
        axi_write(addr6, 32'hCAFEBABE, 4'b0011, 0, 0);
        expect_bresp(addr6, 4'b0011, S_BRESP);
        shadow[6] = mask_write(shadow[6], 32'hCAFEBABE, 4'b0011);
        axi_read(addr6, rdata, rresp);
        expect_rresp(addr6, rresp);
        if (rdata !== shadow[6]) begin $error("Partial write mismatch at reg 6"); $fatal; end
        $display("Transaction 2 PASSED: Partial write OK");

        // 3) Zero-strobe write
        axi_write(addr7, 32'h11223344, 4'b0000, 0, 0);
        expect_bresp(addr7, 4'b0000, S_BRESP);
        axi_read(addr7, rdata, rresp);
        expect_rresp(addr7, rresp);
        if (rdata !== shadow[7]) begin $error("Zero-strobe should not modify reg 7"); $fatal; end
        $display("Transaction 3 PASSED: Zero-strobe OK");

      // 4) Misaligned address
        axi_write(unaligned, 32'hA5A5A5A5, 4'hF, 0, 0);
        expect_bresp(unaligned, 4'hF, S_BRESP);
        axi_read(unaligned, rdata, rresp);
        expect_rresp(unaligned, rresp);
        $display("Transaction 4 PASSED: Unaligned address SLVERR OK");

        // 5) Out-of-range address
        axi_write(oor, 32'h5555AAAA, 4'hF, 0, 0);
        expect_bresp(oor, 4'hF, S_BRESP);
        axi_read(oor, rdata, rresp);
        expect_rresp(oor, rresp);
        $display("Transaction 5 PASSED: Out-of-range SLVERR OK");

        // 6) AW first, delayed W
        axi_write(addr8, 32'h0BADF00D, 4'hF, 5, 0);
        expect_bresp(addr8, 4'hF, S_BRESP);
        shadow[8] = 32'h0BADF00D;
        $display("Transaction 6 PASSED: AW first, delayed W OK");

        // 7) W first, delayed AW
        axi_write(addr9, 32'hFEEDC0DE, 4'hF, 0, 7);
        expect_bresp(addr9, 4'hF, S_BRESP);
        shadow[9] = 32'hFEEDC0DE;
        $display("Transaction 7 PASSED: W first, delayed AW OK");

        // 8) Read-back 8
        axi_read(addr8, rdata, rresp);
        expect_rresp(addr8, rresp);
        if (rdata !== shadow[8]) begin $error("Mismatch at reg 8"); $fatal; end
        $display("Transaction 8 PASSED: Read-back reg 8 OK");

        // 9) Read-back 9
        axi_read(addr9, rdata, rresp);
        expect_rresp(addr9, rresp);
        if (rdata !== shadow[9]) begin $error("Mismatch at reg 9"); $fatal; end
        $display("Transaction 9 PASSED: Read-back reg 9 OK");

        $display("[%0t] *** ALL TESTS PASSED ***", $time);
        $finish;
    end

endmodule
