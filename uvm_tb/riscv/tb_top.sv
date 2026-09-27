`timescale 1ns/1ps
//=============================================================
// tb_top.sv
// UVM top: generates PCLK, instantiates the DUT plus the two
// interfaces (pin-level SPI i/f the agent drives/monitors, and
// the whitebox probe i/f the scoreboard reads for end-of-test
// checks), registers both virtual interfaces in the config_db,
// and kicks off UVM.
//=============================================================
import uvm_pkg::*;
`include "uvm_macros.svh"
import riscv_uvm_pkg::*;

module tb_top;

    logic PCLK = 0;
    always #5 PCLK = ~PCLK;

    riscv_spi_if   spi_if   (.PCLK(PCLK));
    riscv_probe_if probe_if (.PCLK(PCLK));

    // ---- DUT ----------------------------------------------------
    riscv_spi_soc_top #(
        .IMEM_INIT_FILE   ("sw/spi_test.hex"),
        .IMEM_DEPTH_WORDS (256),
        .DMEM_DEPTH_WORDS (256)
    ) dut (
        .PCLK    (PCLK),
        .PRESETn (spi_if.PRESETn),
        .SCLK    (spi_if.SCLK),
        .MOSI    (spi_if.MOSI),
        .MISO    (spi_if.MISO),
        .SS_N    (spi_if.SS_N)
    );

    // ---- whitebox probe hookup (hierarchical refs live only here,
    //      out of class code entirely) ----------------------------
    assign probe_if.pc_q    = dut.u_rv32i_core.pc_q;
    assign probe_if.dmem_b0 = dut.u_dmem.mem0[0];
    assign probe_if.dmem_b1 = dut.u_dmem.mem1[0];
    assign probe_if.dmem_b2 = dut.u_dmem.mem2[0];
    assign probe_if.dmem_b3 = dut.u_dmem.mem3[0];

    // ---- global watchdog, same budget as the original directed TB
    initial begin
        #2_000_000;
        `uvm_fatal("TIMEOUT", "global watchdog expired - test did not finish")
    end

    initial begin
        uvm_config_db#(virtual riscv_spi_if)::set(null, "*", "vif", spi_if);
        uvm_config_db#(virtual riscv_probe_if)::set(null, "*", "probe", probe_if);
        run_test();
    end

endmodule : tb_top
