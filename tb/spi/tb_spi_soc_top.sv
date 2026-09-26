`timescale 1ns/1ps

module tb_spi_soc_top;

    logic PCLK = 0;
    logic PRESETn = 0;
    always #5 PCLK = ~PCLK;

    logic       PSEL, PENABLE, PWRITE, PREADY, PSLVERR;
    logic [31:0] PADDR, PWDATA, PRDATA;
    logic SCLK, MOSI, MISO, SS_N;
    assign MISO = MOSI;   // loopback

    int errors = 0, pass_count = 0;

    spi_soc_top dut (
        .PCLK(PCLK), .PRESETn(PRESETn),
        .PSEL(PSEL), .PENABLE(PENABLE), .PWRITE(PWRITE),
        .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA),
        .PREADY(PREADY), .PSLVERR(PSLVERR),
        .SCLK(SCLK), .MOSI(MOSI), .MISO(MISO), .SS_N(SS_N)
    );

    localparam [7:0] CTRL_REG   = 8'h00;
    localparam [7:0] STATUS_REG = 8'h04;
    localparam [7:0] TX_DATA    = 8'h08;
    localparam [7:0] RX_DATA    = 8'h0C;
    localparam [7:0] CLKDIV     = 8'h10;

    // APB write/read with real wait-state handling (PREADY may be 0)
    task apb_write(input [7:0] addr, input [7:0] data);
        begin
            @(negedge PCLK);
            PSEL = 1; PENABLE = 0; PWRITE = 1;
            PADDR = addr; PWDATA = data;
            @(posedge PCLK);
            @(negedge PCLK);
            PENABLE = 1;
            @(posedge PCLK);
            while (PREADY !== 1'b1) begin
                @(posedge PCLK);
            end
            @(negedge PCLK);
            PSEL = 0; PENABLE = 0;
        end
    endtask

    task apb_read(input [7:0] addr, output [7:0] data);
        begin
            @(negedge PCLK);
            PSEL = 1; PENABLE = 0; PWRITE = 0;
            PADDR = addr;
            @(posedge PCLK);
            @(negedge PCLK);
            PENABLE = 1;
            @(posedge PCLK);
            while (PREADY !== 1'b1) begin
                @(posedge PCLK);
            end
            data = PRDATA;
            @(negedge PCLK);
            PSEL = 0; PENABLE = 0;
        end
    endtask

    task check(input string name, input logic cond);
        begin
            if (cond) begin pass_count++; $display("[PASS] %s", name); end
            else begin errors++; $display("[FAIL] %s", name); end
        end
    endtask

    logic [7:0] rd, rxb;

    task send_byte(input [7:0] tx_byte, output [7:0] rx_byte);
        begin
            apb_write(TX_DATA, tx_byte);
            do begin
                apb_read(STATUS_REG, rd);
            end while (rd[3] == 1'b1);   // bit3 = rx_fifo_empty, wait until not empty
            apb_read(RX_DATA, rx_byte);
        end
    endtask

    initial begin
        PSEL = 0; PENABLE = 0; PWRITE = 0; PADDR = 0; PWDATA = 0;

        PRESETn = 0;
        repeat (5) @(posedge PCLK);
        PRESETn = 1;
        @(posedge PCLK);

        apb_read(STATUS_REG, rd);
        check("reset: tx_full=0 tx_empty=1 rx_full=0 rx_empty=1", rd[3:0] == 4'b1010);

        apb_write(CLKDIV, 8'd2);
        apb_write(CTRL_REG, 8'd1);   // enable

        send_byte(8'hA5, rxb);
        check("loopback 0xA5", rxb == 8'hA5);

        send_byte(8'h01, rxb);
        check("loopback 0x01 (LSB pattern, old bug check)", rxb == 8'h01);

        send_byte(8'h80, rxb);
        check("loopback 0x80 (MSB pattern)", rxb == 8'h80);

        send_byte(8'hFF, rxb);
        check("loopback 0xFF", rxb == 8'hFF);

        send_byte(8'h00, rxb);
        check("loopback 0x00", rxb == 8'h00);

        $display("--------------------------------------------------");
        $display("TOTAL: %0d checks, %0d passed, %0d failed", pass_count+errors, pass_count, errors);
        if (errors == 0) $display("RESULT: ALL TESTS PASSED");
        else              $display("RESULT: %0d TEST(S) FAILED", errors);
        $display("--------------------------------------------------");
        $finish;
    end

    initial begin
        #500000;
        $display("[FAIL] TIMEOUT");
        $finish;
    end

endmodule
