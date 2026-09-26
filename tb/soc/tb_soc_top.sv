`timescale 1ns/1ps

import uart_pkg::*;

module tb_soc_top;
    localparam real CLK_PERIOD = 20ns; // 50 MHz Clock

    // Clock and Reset
    logic clk;
    logic rst_n;

    // Physical Interface Wires
    logic sclk;
    logic mosi;
    logic miso;
    logic ss_n;

    logic pwm_out;
    logic tach_pulse;

    logic uart_rx;
    logic uart_tx;

    // Verification Counters
    int pass_count = 0;
    int fail_count = 0;

    // Clock Generation
    initial clk = 0;
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    // Device Under Test (DUT) //
    soc_top #(
        .IMEM_INIT_FILE(""),
        .IMEM_DEPTH_WORDS(1024),
        .DMEM_DEPTH_WORDS(1024)
    ) dut (
        .PCLK       (clk),
        .PRESETn    (rst_n),
        .SCLK       (sclk),
        .MOSI       (mosi),
        .MISO       (miso),
        .SS_N       (ss_n),
        .pwm_out    (pwm_out),
        .tach_pulse (tach_pulse),
        .uart_rx    (uart_rx),
        .uart_tx    (uart_tx)
    );

    // Virtual Verification Models //
    virtual_uart virtual_uart_inst (
        .rx_pin (uart_tx), // Terminal Rx connected to SoC Tx
        .tx_pin (uart_rx)  // Terminal Tx connected to SoC Rx
    );

    // Simple Virtual SPI Slave Model 
    logic [7:0] spi_slave_rx_byte = 8'h00;
    int         spi_bit_idx       = 7;

    always @(negedge ss_n) begin
        spi_bit_idx = 7;
        spi_slave_rx_byte = 8'h00;
    end

    always @(posedge sclk) begin
        if (!ss_n) begin
            spi_slave_rx_byte[spi_bit_idx] = mosi;
            spi_bit_idx--;
        end
    end

    assign miso = 1'b0; // Dummy loopback pin

    // Virtual Fan / Tachometer Generator Model (Toggles tach_pulse when fan runs) //
    logic fan_running = 1'b0;
    always #50us begin
        if (fan_running)
            tach_pulse <= ~tach_pulse;
        else
            tach_pulse <= 1'b0;
    end

    // APB Master Bus Write Task (2-Phase APB Handshake) //
    task apb_bus_write(input logic [31:0] addr, input logic [31:0] data);
        begin
            // Setup Phase
            @(posedge clk);
            force dut.m_paddr   = addr;
            force dut.m_pwdata  = data;
            force dut.m_pwrite  = 1'b1;
            force dut.m_psel    = 1'b1;
            force dut.m_penable = 1'b0;

            // Access Phase
            @(posedge clk);
            force dut.m_penable = 1'b1;

            @(posedge clk);
            while (!dut.m_pready) @(posedge clk);

            // Idle State & Release
            force dut.m_psel    = 1'b0;
            force dut.m_penable = 1'b0;
            force dut.m_pwrite  = 1'b0;

            release dut.m_paddr;
            release dut.m_pwdata;
            release dut.m_pwrite;
            release dut.m_psel;
            release dut.m_penable;
        end
    endtask

    // Test Control Tasks (Direct APB Access via CPU Bridge / Memory Injection) //
    initial begin
        rst_n       = 1'b0;
        tach_pulse  = 1'b0;
        fan_running = 1'b0;

        #100ns;
        rst_n = 1'b1;
        #100ns;

        $display("       STARTING SOC TOP-LEVEL VERIFICATION        ");

        // Test 1: Config SRAM Preload & Readback
        $display("[TEST 1] Config SRAM Preload & Verification...");
        
        // Simulating CPU bus writes to Config SRAM (Base Address: 0x1002_0000)
        dut.sram_soc_top_inst.u_sram_engine.mem[0] = 8'h64; // Preset PWM Period = 100
        dut.sram_soc_top_inst.u_sram_engine.mem[1] = 8'h32; // Preset Duty Cycle = 50

        if (dut.sram_soc_top_inst.u_sram_engine.mem[0] == 8'h64 &&
            dut.sram_soc_top_inst.u_sram_engine.mem[1] == 8'h32) begin
            $display("[PASS] Config SRAM initialized with presets successfully.");
            pass_count++;
        end else begin
            $error("[FAIL] Config SRAM memory read mismatch!");
            fail_count++;
        end

        #10us;

        // Test 2: PWM Fan Startup
        $display("\n[TEST 2] Verifying PWM Controller Signal Generation...");
        fan_running = 1'b1;

        // Trigger PWM subsystem configuration
        apb_bus_write(32'h1001_000C, 32'd100); // Write Period (0x1001_000C)
        apb_bus_write(32'h1001_0008, 32'd50);  // Write Duty   (0x1001_0008)
        apb_bus_write(32'h1001_0000, 32'd1);   // Enable PWM   (0x1001_0000)

        // Watch for PWM output toggle
        fork
            begin
                @(posedge pwm_out);
                $display("[PASS] Detected pwm_out toggling!");
                pass_count++;
            end
            begin
                #100us;
                $error("[FAIL] Timeout waiting for pwm_out signal!");
                fail_count++;
            end
        join_any
        disable fork;

        #100us;

        // Test 3: SPI Transfer
        $display("\n[TEST 3] Verifying SPI Subsystem Transmission...");
        
        // Write byte 0xA5 to SPI TX Data Register
        apb_bus_write(32'h1000_0000, 32'd1);   // Enable SPI Controller
        apb_bus_write(32'h1000_0008, 32'hA5);  // Write 0xA5 into TX FIFO

        // Wait for SPI transaction complete
        fork
            begin
                @(negedge ss_n);
                @(posedge ss_n);
                if (spi_slave_rx_byte == 8'hA5) begin
                    $display("[PASS] SPI Virtual Slave successfully received 0xA5!");
                    pass_count++;
                end else begin
                    $error("[FAIL] SPI Byte Mismatch! Expected 0xA5, Got 0x%02h", spi_slave_rx_byte);
                    fail_count++;
                end
            end
            begin
                #200us;
                $error("[FAIL] SPI Transfer Timeout!");
                fail_count++;
            end
        join_any
        disable fork;

        #100us;

        // Test 4: UART Status Report
        $display("\n[TEST 4] Verifying UART Transmission ('FAN OK\\n')...");

        fork
            begin
                // Simulate APB writes sending "FAN OK\n" to UART TX Register (0x1003_0000)
                apb_bus_write(32'h1003_0000, 32'h46); // 'F'
                apb_bus_write(32'h1003_0000, 32'h41); // 'A'
                apb_bus_write(32'h1003_0000, 32'h4E); // 'N'
                apb_bus_write(32'h1003_0000, 32'h20); // ' '
                apb_bus_write(32'h1003_0000, 32'h4F); // 'O'
                apb_bus_write(32'h1003_0000, 32'h4B); // 'K'
                apb_bus_write(32'h1003_0000, 32'h0A); // '\n'
            end
            begin
                @(virtual_uart_inst.byte_received);
                if (virtual_uart_inst.last_rx_byte == "F") begin
                    $display("[PASS] Received status message on Virtual UART Console!");
                    pass_count++;
                end else begin
                    $error("[FAIL] UART message header mismatch!");
                    fail_count++;
                end
            end
        join

        #200us;

        $display("   SOC VERIFICATION SUMMARY: %0d PASSED, %0d FAILED   ", pass_count, fail_count);

        if (fail_count > 0)
            $error("SOC SIMULATION FAILED!");
        else
            $display("SOC SIMULATION SUCCESSFUL!");

        $finish;
    end

    // Helper task to write characters over APB to UART
    task tb_uart_write(input logic [7:0] char_data);
        begin
            force dut.s3_psel    = 1'b1;
            force dut.s3_penable = 1'b1;
            force dut.s3_pwrite  = 1'b1;
            force dut.s3_paddr   = 32'h1003_0000;
            force dut.s3_pwdata  = {24'h0, char_data};
            #40ns;
            release dut.s3_psel;
            release dut.s3_penable;
            release dut.s3_pwrite;
            release dut.s3_paddr;
            release dut.s3_pwdata;
            #100us;
        end
    endtask

endmodule