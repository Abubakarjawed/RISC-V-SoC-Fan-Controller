`timescale 1ns/1ps

module tb_sram_soc_top;

    logic PCLK = 0;
    logic PRESETn = 0;
    always #5 PCLK = ~PCLK;

    logic       PSEL, PENABLE, PWRITE, PREADY, PSLVERR;
    logic [31:0] PADDR, PWDATA, PRDATA;

    int errors = 0, pass_count = 0;

    sram_soc_top dut (
        .PCLK(PCLK), .PRESETn(PRESETn),
        .PSEL(PSEL), .PENABLE(PENABLE), .PWRITE(PWRITE),
        .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA),
        .PREADY(PREADY), .PSLVERR(PSLVERR)
    );

    task apb_write(input [7:0] addr, input [7:0] data);
        begin
            @(negedge PCLK);
            PSEL = 1; PENABLE = 0; PWRITE = 1;
            PADDR = addr; PWDATA = data;
            @(posedge PCLK);
            @(negedge PCLK);
            PENABLE = 1;
            @(posedge PCLK);
            while (PREADY !== 1'b1) @(posedge PCLK);
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
            while (PREADY !== 1'b1) @(posedge PCLK);
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

    logic [7:0] rd;

    // ---------------------------------------------------------------
    // Config profile addresses (example: PWM fan profile stored here,
    // matching the DUTY/PERIOD register map already used in pwm_engine)
    // ---------------------------------------------------------------
    localparam [7:0] PROFILE1_DUTY_ADDR   = 8'h00;
    localparam [7:0] PROFILE1_PERIOD_ADDR = 8'h01;
    localparam [7:0] PROFILE2_DUTY_ADDR   = 8'h02;
    localparam [7:0] PROFILE2_PERIOD_ADDR = 8'h03;

    initial begin
        PSEL = 0; PENABLE = 0; PWRITE = 0; PADDR = 0; PWDATA = 0;

        // ------------------------------------------------------------
        // Preload configuration SRAM directly (per spec: "testbench
        // preloads configuration SRAM"). Hierarchical access to the
        // memory array, as is standard for SRAM preload in simulation.
        // ------------------------------------------------------------
        dut.u_sram_engine.mem[PROFILE1_DUTY_ADDR]   = 8'h19;  // profile 1: duty=25
        dut.u_sram_engine.mem[PROFILE1_PERIOD_ADDR] = 8'h32;  // profile 1: period=50
        dut.u_sram_engine.mem[PROFILE2_DUTY_ADDR]   = 8'h40;  // profile 2: duty=64
        dut.u_sram_engine.mem[PROFILE2_PERIOD_ADDR] = 8'h64;  // profile 2: period=100
        dut.u_sram_engine.mem[8'hFF]                = 8'hAA;  // boundary address
        dut.u_sram_engine.mem[8'h0F]                = 8'h00;  // known value for isolation check
        dut.u_sram_engine.mem[8'h11]                = 8'h00;  // known value for isolation check

        PRESETn = 0;
        repeat (5) @(posedge PCLK);
        PRESETn = 1;
        @(posedge PCLK);

        // ------------------------------------------------------------
        // Verify preloaded config values are readable via APB
        // (simulates CPU reading a fan profile out of config SRAM)
        // ------------------------------------------------------------
        apb_read(PROFILE1_DUTY_ADDR, rd);
        check("preload: profile1 duty readback = 0x19", rd == 8'h19);

        apb_read(PROFILE1_PERIOD_ADDR, rd);
        check("preload: profile1 period readback = 0x32", rd == 8'h32);

        apb_read(PROFILE2_DUTY_ADDR, rd);
        check("preload: profile2 duty readback = 0x40", rd == 8'h40);

        apb_read(PROFILE2_PERIOD_ADDR, rd);
        check("preload: profile2 period readback = 0x64", rd == 8'h64);

        apb_read(8'hFF, rd);
        check("preload: boundary address 0xFF readback = 0xAA", rd == 8'hAA);

        // ------------------------------------------------------------
        // Normal case: CPU writes a new config value, reads it back
        // ------------------------------------------------------------
        apb_write(8'h10, 8'h77);
        apb_read(8'h10, rd);
        check("write+readback: 0x10 = 0x77", rd == 8'h77);

        // ------------------------------------------------------------
        // Write should not corrupt neighboring addresses
        // (0x0F, 0x11 explicitly preloaded above since SRAM has no reset -
        //  real memory arrays don't clear to 0 automatically)
        // ------------------------------------------------------------
        apb_read(8'h0F, rd);
        check("write isolation: neighbor 0x0F unaffected", rd == 8'h00);

        apb_read(8'h11, rd);
        check("write isolation: neighbor 0x11 unaffected", rd == 8'h00);

        // ------------------------------------------------------------
        // Overwrite an existing config value (profile update scenario)
        // ------------------------------------------------------------
        apb_write(PROFILE1_DUTY_ADDR, 8'hFF);
        apb_read(PROFILE1_DUTY_ADDR, rd);
        check("profile update: profile1 duty overwritten to 0xFF", rd == 8'hFF);

        // profile1 period should be untouched by the duty overwrite
        apb_read(PROFILE1_PERIOD_ADDR, rd);
        check("profile update: profile1 period still 0x32", rd == 8'h32);

        // ------------------------------------------------------------
        // Boundary address write (0x00 and 0xFF - min/max of 8-bit space)
        // ------------------------------------------------------------
        apb_write(8'h00, 8'h11);
        apb_read(8'h00, rd);
        check("boundary write: address 0x00 = 0x11", rd == 8'h11);

        apb_write(8'hFF, 8'h22);
        apb_read(8'hFF, rd);
        check("boundary write: address 0xFF = 0x22", rd == 8'h22);

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
