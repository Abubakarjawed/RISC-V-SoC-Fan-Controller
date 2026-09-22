`timescale 1ns/1ps

module tb_uart_top_direct;
    import uart_pkg::*;

    localparam int CLK_PERIOD_NS = 10;
    localparam int TICK_DIVISOR  = 4;
    localparam int BIT_CLKS      = 16 * TICK_DIVISOR;

    logic    clk = 1'b0;
    logic    rst_n;
    parity_e parity_mode;
    stop_e   stop_mode;
    logic    [7:0] tx_data;
    logic    tx_start;
    logic    tx_ready;
    logic    uart_tx;
    logic    uart_rx;
    logic    [7:0] rx_data;
    logic    rx_done;
    logic    parity_err;

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    uart_top #(
        .CLK_HZ(64), 
        .BAUD_RATE(1)
    ) dut (
        .clk, 
        .rst_n, 
        .parity_mode, 
        .stop_mode, 
        .tx_data, 
        .tx_start,
        .tx_ready, 
        .uart_tx, 
        .uart_rx, 
        .rx_data, 
        .rx_done, 
        .parity_err
    );

    task automatic check(input logic condition, input string fail_msg, input string pass_msg = "");
        if (!condition) begin 
            $fatal(1, "CHECK FAILED: %s", fail_msg);
        end else if (pass_msg != "") begin
            $display("[PASS] %s", pass_msg);
        end
    endtask

    task automatic wait_clks(input int count);
        repeat (count) @(posedge clk);
    endtask

    // clk and reset
    task automatic reset_dut();    
        rst_n       = 1'b0;
        parity_mode = PARITY_NONE;
        stop_mode   = STOP_1;
        tx_data     = '0;
        tx_start    = 1'b0;
        uart_rx     = 1'b1;

        wait_clks(5);
        rst_n       = 1'b1;
    endtask

    task automatic run_tx_test(input logic [7:0] data_to_send);
        $display("[TX TEST] Starting transmission of 8'h%h...", data_to_send);
        // tx verify test
        tx_data = data_to_send;
        tx_start    = 1'b1;
        wait_clks(1);
        tx_start    = 1'b0;
        
        @(negedge uart_tx)
        wait_clks(BIT_CLKS + (BIT_CLKS / 2));
        
        for (int i = 0; i < 8; i++) begin
            check(uart_tx == data_to_send[i], $sformatf("TX Bit %0d mismatch", i), $sformatf("TX Bit %0d match", i));
            wait_clks(BIT_CLKS);
        end
        wait_clks(BIT_CLKS);
        check(tx_ready == 1'b1, "TX ready did not return High", "TX ready return High succesfully");
    endtask

    task automatic run_rx_test(input logic [7:0] expected_data);
        $display("[RX TEST] Starting transmission of 8'h%h...", expected_data);
        // rx verify test
        uart_rx = 1'b0;
        wait_clks(BIT_CLKS);

        for (int i = 0; i < 8; i++) begin
            uart_rx = expected_data[i];
            wait_clks(BIT_CLKS);
        end

        uart_rx = 1'b1;
        wait_clks(BIT_CLKS);

        @(posedge rx_done);
        check(rx_data == expected_data, "RX data does not match", "RX data does get match");
    endtask
    
    task automatic run_parity_error_test (input logic [7:0] test_data);
        logic correct_parity;

        correct_parity = ^test_data;
        parity_mode = PARITY_EVEN;
        stop_mode   = STOP_1;

        uart_rx     = 1'b0;
        wait_clks(BIT_CLKS);

        for (int i = 0; i < 8; i++) begin
            uart_rx = test_data[i];
            wait_clks(BIT_CLKS);
        end

        uart_rx     = ~correct_parity;
        wait_clks(BIT_CLKS);

        uart_rx     = 1'b1;
        wait_clks(BIT_CLKS);

        @(posedge rx_done);
        check(parity_err == 1'b1, "Parity error flag failed to assert", "Parity error flag successfully assert");
        check(rx_data == test_data, "data mismatch on parity error test", "data match on parity error test");
    endtask

    initial begin
        // 1. Reset Phase
        reset_dut();

        // 2. Scenario 1: TX Standalone Test
        run_tx_test(8'hA5);

        // 3. Scenario 2: RX Standalone Test
        run_rx_test(8'h3C);

        // 4. Scenario 3: Parity Error Test
        run_parity_error_test(8'h3C);

        parity_mode = PARITY_NONE;
        stop_mode   = STOP_1;
        wait_clks(10);
        
        // 5. Scenario 4: Concurrent Full-Duplex Test
        fork
            run_tx_test(8'hAA);
            run_rx_test(8'h55);
        join

        $display("ALL TESTS PASSED SUCCESSFULLY!");
        $finish;
    end
endmodule
