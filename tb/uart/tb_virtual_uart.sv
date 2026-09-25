`timescale 1ns/1ps

import uart_pkg::*;

module tb_virtual_uart;
    logic clk;
    logic rst_n;

    // Serial Lines
    logic v_tx_pin;
    logic v_rx_pin;
    logic hw_tx_pin; // Explicit wire for HW Tx line to prevent vopt optimization errors

    // APB Bus Signals
    logic [ADDR_WIDTH_32-1:0] paddr;
    logic                     psel;
    logic                     penable;
    logic                     pwrite;
    logic [DATA_WIDTH_32-1:0] pwdata;
    logic [DATA_WIDTH_32-1:0] prdata;
    logic                     pready;
    logic                     pslverr;

    int pass_count = 0;
    int fail_count = 0;

    initial clk = 0;
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    virtual_uart virtual_term (
        .rx_pin    (v_rx_pin),
        .tx_pin    (v_tx_pin)
    );

    uart_apb uart_apb_term (
        .PCLK      (clk),
        .PRESETn   (rst_n),
        .PADDR     (paddr),
        .PSEL      (psel),
        .PENABLE   (penable),
        .PWRITE    (pwrite),
        .PWDATA    (pwdata),
        .PRDATA    (prdata),
        .PREADY    (pready),
        .PSLVERR   (pslverr),
        .uart_rx   (v_tx_pin), 
        .uart_tx   (hw_tx_pin)          
    );

    task apb_write(input logic [ADDR_WIDTH_32-1:0] addr, input logic [DATA_WIDTH_32-1:0] data);
        begin
            @(posedge clk);
            paddr   <= addr;
            pwdata  <= data;
            pwrite  <= 1'b1;
            psel    <= 1'b1;
            penable <= 1'b0;
            @(posedge clk);
            penable <= 1'b1;

            while (!pready) begin 
                @(posedge clk);
            end
            
            @(posedge clk);
            psel    <= 1'b0;
            penable <= 1'b0;
        end
    endtask

    task apb_read(input logic [ADDR_WIDTH_32-1:0] addr, output logic [DATA_WIDTH_32-1:0] data);
        begin
            @(posedge clk);
            paddr   <= addr;
            pwrite  <= 1'b0;
            psel    <= 1'b1;
            penable <= 1'b0;
            @(posedge clk);
            penable <= 1'b1;

            while (!pready) begin       
                @(posedge clk);
            end            
            
            data    = prdata;
            @(posedge clk);
            psel    <= 1'b0;
            penable <= 1'b0;
        end
    endtask

    task apb_write_uart_tx(input logic [DATA_WIDTH_8-1:0] char_data);
        logic [DATA_WIDTH_32-1:0] status;
        begin
            do begin
                apb_read(32'h0000_0008, status); 
            end while (status[2] == 1'b1);

            apb_write(32'h0000_0000, {24'h0, char_data});
        end
    endtask

    logic loopback_direct;
    assign v_rx_pin = loopback_direct ? v_tx_pin : hw_tx_pin;

    initial begin
        rst_n           = 1'b0;
        psel            = 1'b0;
        penable         = 1'b0;
        loopback_direct = 1'b1; 

        #100ns;
        rst_n = 1'b1;
        #100ns;

        $display("   STARTING VIRTUAL UART TERMINAL VERIFICATION    ");

        // Test 1: Terminal Direct Internal Loopback
        $display("[TEST 1] Testing Virtual UART Direct Loopback Transmission...");
        fork
            begin
                virtual_term.send_string("Hello\n");
            end
            begin
                @(virtual_term.byte_received);
                if (virtual_term.last_rx_byte == "H") begin
                    $display("[PASS] Received first character 'H' via direct loopback.");
                    pass_count++;
                end else begin
                    $error("[FAIL] Direct Loopback character mismatch!");
                    fail_count++;
                end
            end
        join

        #200us; 

        // Test 2: Hardware APB UART Integration Loopback
        $display("\n[TEST 2] Testing APB UART <-> Virtual UART Communication...");
        loopback_direct = 1'b0; // Connect virtual_uart to uart_apb

        // HW Tx -> Virtual Terminal Rx
        $display("Subtest: HW sending 'O' (0x4F) and 'K' (0x4B) over APB...");
        fork
            begin
                apb_write_uart_tx("O");
                apb_write_uart_tx("K");
                apb_write_uart_tx("\n");
            end
            begin
                @(virtual_term.byte_received);
                if (virtual_term.last_rx_byte == "O") pass_count++; else fail_count++;

                @(virtual_term.byte_received);
                if (virtual_term.last_rx_byte == "K") begin
                    $display("[PASS] Virtual UART successfully received 'OK' from HW APB UART.");
                    pass_count++;
                end else begin
                    $error("[FAIL] HW to Terminal transmission failed!");
                    fail_count++;
                end
            end
        join

        #200us;

        // Virtual Terminal Tx -> HW Rx
        $display("Subtest: Virtual Terminal sending command string 'CMD' to HW...");
        fork
            begin
                virtual_term.send_string("CMD");
            end
            begin
                logic [DATA_WIDTH_32-1:0] rx_data;

                #100us; 
                apb_read(32'h0000_0004, rx_data); // Read RX_DATA
                if (rx_data[DATA_WIDTH_8-1:0] == "C") begin
                    $display("[PASS] APB UART successfully received 'C' from Virtual Terminal!");
                    pass_count++;
                end else begin
                    $error("[FAIL] APB UART read mismatch! Expected 'C', Got 0x%02h", rx_data[7:0]);
                    fail_count++;
                end
            end
        join

        // Final Results Summary
        $display("   RESULTS: %0d PASSED, %0d FAILED   ", pass_count, fail_count);

        if (fail_count > 0)
            $error("SIMULATION FAILED!");
        else
            $display("SIMULATION SUCCESSFUL!");

        $finish;
    end

endmodule
