`timescale 1ns/1ps

import uart_pkg::*;

module tb_uart_apb;

    logic PCLK;
    logic PRESETn;

    // APB Bus Signals
    logic [ADDR_WIDTH_32-1:0] PADDR;
    logic                     PSEL;
    logic                     PENABLE;
    logic                     PWRITE;
    logic [DATA_WIDTH_32-1:0] PWDATA;
    logic [DATA_WIDTH_32-1:0] PRDATA;
    logic                     PREADY;
    logic                     PSLVERR;

    // External UART Loopback
    wire  uart_loopback;
    int   pass_count = 0;
    int   fail_count = 0;
    logic error_flag;
    logic [DATA_WIDTH_32-1:0] read_data;


    // 100 MHz Clock Generation
    initial PCLK = 0;
    always #5ns PCLK = ~PCLK;

    // Instantiate DUT (APB Slave)
    uart_apb dut (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),
        .PSEL    (PSEL),
        .PENABLE (PENABLE),
        .PWRITE  (PWRITE),
        .PADDR   (PADDR),
        .PWDATA  (PWDATA),
        .PRDATA  (PRDATA),
        .PREADY  (PREADY),
        .PSLVERR (PSLVERR),
        .uart_tx (uart_loopback), 
        .uart_rx (uart_loopback)
    );

    // Self-Checking
    task check_read (
        input logic [ADDR_WIDTH_32-1:0] addr,
        input logic [ADDR_WIDTH_32-1:0] expected_data,
        input string reg_name
    );  begin
            apb_read_task(addr, read_data);
            if ($isunknown(read_data)) begin
                $error("[FAIL] %s at addr 0x%0h returned UNKNOWN logic (0x%0h)", reg_name, addr, read_data);
                fail_count++;
            end else if (read_data !== expected_data) begin
                $error("[FAIL] %s mismatch at addr 0x%0h | Expected: 0x%0h, Got: 0x%0h", 
                        reg_name, addr, expected_data, read_data);
                fail_count++;
            end else begin
                $display("[PASS] %s at addr 0x%0h matched expected 0x%0h", reg_name, addr, read_data);
                pass_count++;
            end
        end
    endtask //check_read

    task apb_write_task;
        input  logic [ADDR_WIDTH_32-1:0] addr;
        input  logic [DATA_WIDTH_32-1:0] data;
        output logic error;

        begin
            // Setup Phase
            @(posedge PCLK);
            PADDR   <= addr;
            PWDATA  <= data;
            PWRITE  <= 1'b1;
            PSEL    <= 1'b1;
            PENABLE <= 1'b0;

            // Access Phase
            @(posedge PCLK);
            PENABLE <= 1'b1;

            // Wait for slave
            while (!PREADY)
                @(posedge PCLK);

            error = PSLVERR;

            // Complete transfer
            @(posedge PCLK);
            PSEL    <= 1'b0;
            PENABLE <= 1'b0;
            PWRITE  <= 1'b0;
        end
    endtask

    //----------------------------------------------------
    // APB READ
    //----------------------------------------------------
    task apb_read_task;
        input  logic [ADDR_WIDTH_32-1:0] addr;
        output logic [DATA_WIDTH_32-1:0] data;

        begin
            // Setup Phase
            @(posedge PCLK);
            PADDR   <= addr;
            PWRITE  <= 1'b0;
            PSEL    <= 1'b1;
            PENABLE <= 1'b0;

            // Access Phase
            @(posedge PCLK);
            PENABLE <= 1'b1;

            // Wait until ready
            while (!PREADY)
                @(posedge PCLK);

            data    = PRDATA;

            // Complete transfer
            @(posedge PCLK);
            PSEL    <= 1'b0;
            PENABLE <= 1'b0;
        end
    endtask

    // Test Sequence
    initial begin
        PRESETn = 1'b0;
        #20ns;
        PRESETn = 1'b1;
        #10ns;
        
        $display("\n==================================================");
        $display("   STARTING AUTOMATED APB-UART TEST SUITE        ");
        $display("==================================================\n");


        // Test 1: Check Reset State of CTRL
        check_read(32'h0C, 32'h00, "CTRL (Reset State)");

        // Test 2: Trigger Transmission: Write 0x5A to TX_DATA (0x00)
        apb_write_task(32'h00, 32'h5A, error_flag);

        // Test 3: Poll STATUS register until rx_valid (bit 1) is set
        begin : poll_loop
            logic [DATA_WIDTH_32-1:0] status;
            static integer timeout = 0;
            status = 0;

            while ((status & 32'h02) == 0) begin
                apb_read_task(32'h08, status);
                #100ns;
                timeout++;
                if (timeout > 10000) begin
                    $error("[FAIL] Timeout waiting for rx_valid in STATUS!");
                    fail_count++;
                    disable poll_loop;
                end
            end
            $display("[PASS] rx_valid asserted in STATUS register!");
            pass_count++;
        end
        
        // Test 4: Read RX_DATA (0x04) and verify payload
        check_read(32'h04, 32'h5A, "RX_DATA Loopback Read");

        // Test 5: Read STATUS (0x08) again to verify rx_valid cleared back to 0
        check_read(32'h08, 32'h00, "STATUS Read-to-Clear Check");

        // Summary Report
        $display("\n==================================================");
        $display("   TEST RESULTS: %0d PASSED, %0d FAILED          ", pass_count, fail_count);
        $display("==================================================\n");

        if (fail_count > 0) begin
            $error("SIMULATION FAILED with %0d errors.", fail_count);
        end else begin
            $display("SIMULATION SUCCESSFUL!");
        end

        $finish;
    end

    // Concurrent Assertions: Ensure APB protocol compliance
    assert property (@(posedge PCLK) PENABLE |-> PSEL) 
        else $error("[PROTOCOL ERROR] PENABLE asserted without PSEL!");
endmodule