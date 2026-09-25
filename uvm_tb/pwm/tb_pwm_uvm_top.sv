`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"
import apb_pkg::*;
import pwm_pkg::*;

module tb_pwm_uvm_top;

    logic PCLK = 0;
    logic PRESETn = 0;
    always #5 PCLK = ~PCLK;

    apb_if bus_if (.PCLK(PCLK), .PRESETn(PRESETn));
    pwm_if fan_if (.PCLK(PCLK), .PRESETn(PRESETn));

    pwm_soc_top dut (
        .PCLK       (PCLK),
        .PRESETn    (PRESETn),
        .PSEL       (bus_if.PSEL),
        .PENABLE    (bus_if.PENABLE),
        .PWRITE     (bus_if.PWRITE),
        .PADDR      (bus_if.PADDR),
        .PWDATA     (bus_if.PWDATA),
        .PRDATA     (bus_if.PRDATA),
        .PREADY     (bus_if.PREADY),
        .PSLVERR    (bus_if.PSLVERR),
        .pwm_out    (fan_if.pwm_out),
        .tach_pulse (fan_if.tach_pulse)
    );

    initial begin
        PRESETn = 0;
        repeat (5) @(posedge PCLK);
        PRESETn = 1;
    end

    initial begin
        uvm_config_db#(virtual apb_if)::set(null, "*", "vif", bus_if);
        uvm_config_db#(virtual pwm_if)::set(null, "*", "vif", fan_if);
        run_test("pwm_base_test");
    end

    initial begin
        #1_000_000;
        `uvm_fatal("TB_TOP", "global timeout")
    end

endmodule
