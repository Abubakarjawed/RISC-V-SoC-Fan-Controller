`timescale 1ns/1ps

module tb_apb_interconnect;
    logic clk;
    logic rst_n;

    // Master Signals
    logic [31:0] m_paddr;
    logic        m_psel;
    logic        m_penable;
    logic        m_pwrite;
    logic [31:0] m_pwdata;
    logic [31:0] m_prdata;
    logic        m_pready;
    logic        m_pslverr;

    // Slave 0 (SPI)
    logic        s0_psel, s0_penable, s0_pwrite, s0_pready, s0_pslverr;
    logic [31:0] s0_paddr, s0_pwdata, s0_prdata;

    // Slave 1 (PWM)
    logic        s1_psel, s1_penable, s1_pwrite, s1_pready, s1_pslverr;
    logic [31:0] s1_paddr, s1_pwdata, s1_prdata;

    // Slave 2 (Config SRAM)
    logic        s2_psel, s2_penable, s2_pwrite, s2_pready, s2_pslverr;
    logic [31:0] s2_paddr, s2_pwdata, s2_prdata;

    // Slave 3 (UART)
    logic        s3_psel, s3_penable, s3_pwrite, s3_pready, s3_pslverr;
    logic [31:0] s3_paddr, s3_pwdata, s3_prdata;

    int pass_count = 0;
    int fail_count = 0;

    // Clock Generation (100 MHz)
    initial clk = 0;
    always #5ns clk = ~clk;

    // Instantiate DUT
    apb_interconnect #(
        .SPI_BASE_ADDR  (32'h1000_0000),
        .PWM_BASE_ADDR  (32'h1001_0000),
        .SRAM_BASE_ADDR (32'h1002_0000),
        .UART_BASE_ADDR (32'h1003_0000),
        .ADDR_MASK      (32'hFFFF_0000)
    ) dut (.*);

    // Dummy Slave Defaults
    assign s0_pslverr = 1'b0;
    assign s1_pslverr = 1'b0;
    assign s2_pslverr = 1'b0;
    assign s3_pslverr = 1'b0;

    assign s0_prdata = 32'hA000_0000; 
    assign s1_prdata = 32'hB000_0000; 
    assign s2_prdata = 32'hC000_0000; 
    assign s3_prdata = 32'hD000_0000;

    // Master Driver Task
    task apb_transaction (
        input  logic [31:0] addr,
        input  logic        write,
        input  logic [31:0] wdata,
        output logic [31:0] rdata,
        output logic        slverr
    );
        begin
            // Setup Phase
            @(posedge clk);
            m_paddr   <= addr;
            m_pwrite  <= write;
            m_pwdata  <= wdata;
            m_psel    <= 1'b1;
            m_penable <= 1'b0;

            // Access Phase
            @(posedge clk);
            m_penable <= 1'b1;

            // Wait state polling
            while (!m_pready) begin
                @(posedge clk);
            end

            rdata  = m_prdata;
            slverr = m_pslverr;

            // Complete Transfer
            @(posedge clk);
            m_psel    <= 1'b0;
            m_penable <= 1'b0;
        end
    endtask

    initial begin
        m_psel    = 1'b0;
        m_penable = 1'b0;
        m_paddr   = '0;
        m_pwdata  = '0;
        m_pwrite  = 1'b0;

        // Set default slave readies
        s0_pready = 1'b1;
        s1_pready = 1'b1;
        s2_pready = 1'b1;
        s3_pready = 1'b1;

        #20ns;

        $display("   STARTING APB INTERCONNECT VERIFICATION SUITE   ");

        // Test 1: SPI Select Routing
        @(posedge clk);
        m_paddr <= 32'h1000_0004;
        m_psel  <= 1'b1;
        #1ns;

        if (s0_psel && !s1_psel && !s2_psel && !s3_psel) begin
            $display("[PASS] SPI Base Address decoded to s0_psel exclusively.");
            pass_count++;
        end else begin
            $error("[FAIL] Incorrect PSEL routing for SPI address!");
            fail_count++;
        end
        m_psel <= 1'b0;

        // Test 2: PWM Select Routing
        @(posedge clk);
        m_paddr <= 32'h1001_0008;
        m_psel  <= 1'b1;
        #1ns;

        if (!s0_psel && s1_psel && !s2_psel && !s3_psel) begin
            $display("[PASS] PWM Base Address decoded to s1_psel exclusively.");
            pass_count++;
        end else begin
            $error("[FAIL] Incorrect PSEL routing for PWM address!");
            fail_count++;
        end
        m_psel <= 1'b0;

        // Test 3: SRAM Select Routing
        @(posedge clk);
        m_paddr <= 32'h1002_0020;
        m_psel  <= 1'b1;
        #1ns;

        if (!s0_psel && !s1_psel && s2_psel && !s3_psel) begin
            $display("[PASS] SRAM Base Address decoded to s2_psel exclusively.");
            pass_count++;
        end else begin
            $error("[FAIL] Incorrect PSEL routing for SRAM address!");
            fail_count++;
        end
        m_psel <= 1'b0;

        // Test 4: UART Select Routing
        @(posedge clk);
        m_paddr <= 32'h1003_0000;
        m_psel  <= 1'b1;
        #1ns;

        if (!s0_psel && !s1_psel && !s2_psel && s3_psel) begin
            $display("[PASS] UART Base Address decoded to s3_psel exclusively.");
            pass_count++;
        end else begin
            $error("[FAIL] Incorrect PSEL routing for UART address!");
            fail_count++;
        end
        m_psel <= 1'b0;

        // Test 5: SPI Dynamic Backpressure (PREADY Propagation)
        s0_pready <= 1'b0; // Force SPI stall
        @(posedge clk);
        m_paddr <= 32'h1000_0000;
        m_psel  <= 1'b1;
        #1ns;

        if (m_pready == 1'b0) begin
            $display("[PASS] Dynamic backpressure (s0_pready=0) successfully passed to m_pready.");
            pass_count++;
        end else begin
            $error("[FAIL] Interconnect failed to propagate s0_pready = 0 to Master!");
            fail_count++;
        end
        s0_pready <= 1'b1; // Release stall
        m_psel    <= 1'b0;

        // Test 6: Unmapped Address (Decode Error Check)
        @(posedge clk);
        m_paddr   <= 32'h1004_0000; // Out of bounds
        m_psel    <= 1'b1;
        m_penable <= 1'b1;
        #1ns;

        if (!s0_psel && !s1_psel && !s2_psel && !s3_psel && m_pslverr && m_pready) begin
            $display("[PASS] Unmapped address returned m_pslverr=1 and m_pready=1 without selecting any slave.");
            pass_count++;
        end else begin
            $error("[FAIL] Unmapped address decode error handling failed!");
            fail_count++;
        end
        m_psel    <= 1'b0;
        m_penable <= 1'b0;

        // Final Summary
        $display("   RESULTS: %0d PASSED, %0d FAILED   ", pass_count, fail_count);

        if (fail_count > 0)
            $error("SIMULATION FAILED!");
        else
            $display("SIMULATION SUCCESSFUL!");

        $finish;
    end

endmodule
