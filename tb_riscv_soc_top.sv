`timescale 1ns/1ps
//=============================================================
// tb_riscv_soc_top.sv   (renamed from tb_riscv_spi_soc_top.sv)
// Directed, self-checking testbench: boots the RV32I core out
// of reset, lets it run the preloaded program (sw/spi_test.hex)
// which configures + drives the SPI engine over the memory-
// mapped APB peripheral (now reached through apb_interconnect),
// and checks the result the core wrote back into local data
// memory against the expected SPI loopback byte.
//
// *** IMPORTANT: the address map changed in riscv_soc_top.sv
// *** (SPI moved to 0x1000_0000, local dmem moved to
// *** 0x2000_0000 -- see that file's header comment). The
// *** existing sw/spi_test.hex was assembled against the OLD
// *** map and will very likely FAIL the two checks below until
// *** it is re-assembled with the new addresses. This is
// *** expected and is not a bug in this testbench or the RTL --
// *** whoever owns the assembly source needs to update it and
// *** regenerate the .hex file.
//=============================================================
module tb_riscv_soc_top;

    logic PCLK = 0;
    logic PRESETn = 0;
    always #5 PCLK = ~PCLK;

    logic SCLK, MOSI, MISO, SS_N;
    assign MISO = MOSI;   // SPI loopback slave model

    logic pwm_out;
    logic tach_pulse = 1'b0;  // not exercised by this test; tie low

    int errors = 0, pass_count = 0;

    riscv_soc_top #(
        .IMEM_INIT_FILE ("sw/spi_test.hex"),
        .IMEM_DEPTH_WORDS (256),
        .DMEM_DEPTH_WORDS (256)
    ) dut (
        .PCLK       (PCLK),
        .PRESETn    (PRESETn),
        .SCLK       (SCLK),
        .MOSI       (MOSI),
        .MISO       (MISO),
        .SS_N       (SS_N),
        .pwm_out    (pwm_out),
        .tach_pulse (tach_pulse)
    );

    task check(input string name, input logic cond);
        begin
            if (cond) begin pass_count++; $display("[PASS] %s", name); end
            else begin errors++; $display("[FAIL] %s", name); end
        end
    endtask

    // Peek directly into local data memory word 0 (where the program
    // stores the byte it read back from the SPI RX_DATA register).
    logic [31:0] result_word;
    always_comb result_word = {dut.u_dmem.mem3[0], dut.u_dmem.mem2[0],
                                dut.u_dmem.mem1[0], dut.u_dmem.mem0[0]};

    initial begin
        PRESETn = 0;
        repeat (5) @(posedge PCLK);

        // Reset behaviour: core PC is held at the reset vector (0x0)
        // for as long as PRESETn is asserted.
        check("reset: PC held at 0x0 during reset",
              dut.u_rv32i_core.pc_q == 32'h0);

        PRESETn = 1;
        @(posedge PCLK);

        // Let the preloaded program run: LUI/ADDI/SB configure CLKDIV
        // and CTRL, SB writes 0xA5 to TX_DATA, the core polls STATUS
        // until RX is non-empty, then LB+SW stashes the received byte
        // into local data memory word 0.
        repeat (4000) @(posedge PCLK);

        check("core wrote back loopback byte 0xA5",
              result_word[7:0] == 8'hA5);

        check("core parked in the terminal self-loop (no illegal instr)",
              dut.u_rv32i_core.pc_q == 32'h34);

        $display("--------------------------------------------------");
        $display("TOTAL: %0d checks, %0d passed, %0d failed",
                  pass_count + errors, pass_count, errors);
        if (errors == 0) $display("RESULT: ALL TESTS PASSED");
        else              $display("RESULT: %0d TEST(S) FAILED", errors);
        $display("--------------------------------------------------");
        $finish;
    end

    initial begin
        #2_000_000;
        $display("[FAIL] TIMEOUT");
        $finish;
    end

endmodule
