`timescale 1ns/1ps
// ===========================================================================
// tb_sram_uvm_top : SRAM DUT ke sath UVM ko jodne wala top module.
// Reset, clock, DUT instantiation, aur config-SRAM preload (spec: "testbench
// preloads configuration SRAM") yahan hota hai -- bilkul directed
// tb_sram_soc_top.sv jaisa -- phir run_test() UVM ko handover kar deta hai.
// ===========================================================================
import uvm_pkg::*;
`include "uvm_macros.svh"
import apb_pkg::*;
import sram_pkg::*;

module tb_sram_uvm_top;

    logic PCLK = 0;
    logic PRESETn = 0;
    always #5 PCLK = ~PCLK;

    apb_if bus_if (.PCLK(PCLK), .PRESETn(PRESETn));

    sram_soc_top dut (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),
        .PSEL    (bus_if.PSEL),
        .PENABLE (bus_if.PENABLE),
        .PWRITE  (bus_if.PWRITE),
        .PADDR   (bus_if.PADDR),
        .PWDATA  (bus_if.PWDATA),
        .PRDATA  (bus_if.PRDATA),
        .PREADY  (bus_if.PREADY),
        .PSLVERR (bus_if.PSLVERR)
    );

    // ---------------------------------------------------------------
    // Config SRAM preload -- hierarchical poke, jaisa directed TB mein
    // tha. Yahi values sram_base_test apne scoreboard model mein bhi
    // set karta hai (env.sb.preload calls) taake model DUT ke sath sync ho.
    // ---------------------------------------------------------------
    initial begin
        dut.u_sram_engine.mem[8'h00] = 8'h19;  // profile1 duty
        dut.u_sram_engine.mem[8'h01] = 8'h32;  // profile1 period
        dut.u_sram_engine.mem[8'h02] = 8'h40;  // profile2 duty
        dut.u_sram_engine.mem[8'h03] = 8'h64;  // profile2 period
        dut.u_sram_engine.mem[8'hFF] = 8'hAA;  // boundary
        dut.u_sram_engine.mem[8'h0F] = 8'h00;  // isolation check
        dut.u_sram_engine.mem[8'h11] = 8'h00;  // isolation check
    end

    initial begin
        PRESETn = 0;
        repeat (5) @(posedge PCLK);
        PRESETn = 1;
    end

    initial begin
        uvm_config_db#(virtual apb_if)::set(null, "*", "vif", bus_if);
        run_test("sram_base_test");
    end

    // safety timeout
    initial begin
        #1_000_000;
        `uvm_fatal("TB_TOP", "global timeout")
    end

endmodule
