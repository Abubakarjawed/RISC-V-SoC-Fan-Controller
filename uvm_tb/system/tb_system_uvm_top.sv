`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import system_pkg::*;

module tb_system_uvm_top;

    logic PCLK = 0;
    logic PRESETn = 0;

    always #10ns PCLK = ~PCLK; // 50 MHz System Clock

    // 1. Instantiate Physical Interfaces
    apb_if  apb_if_inst (PCLK, PRESETn);
    pwm_if  pwm_if_inst (PCLK, PRESETn);
    uart_if uart_if_inst(PCLK, PRESETn);

    // 2. Physical Wires & External Loopbacks
    logic SCLK, MOSI, MISO, SS_N;
    assign MISO = MOSI; // SPI external slave loopback

    logic pwm_out;
    logic tach_pulse = 1'b0;

    logic uart_rx, uart_tx;
    assign uart_rx = uart_tx; // UART serial loopback pin

    // 3. Connect Master APB Interface to Interconnect Master Ports
    always @(*) begin
        if (apb_if_inst.PSEL) begin
            force dut.riscv_soc_top_inst.PADDR   = apb_if_inst.PADDR;
            force dut.riscv_soc_top_inst.PWDATA  = apb_if_inst.PWDATA;
            force dut.riscv_soc_top_inst.PWRITE  = apb_if_inst.PWRITE;
            force dut.riscv_soc_top_inst.PSEL    = apb_if_inst.PSEL;
            force dut.riscv_soc_top_inst.PENABLE = apb_if_inst.PENABLE;
        end else begin
            release dut.riscv_soc_top_inst.PADDR;
            release dut.riscv_soc_top_inst.PWDATA;
            release dut.riscv_soc_top_inst.PWRITE;
            release dut.riscv_soc_top_inst.PSEL;
            release dut.riscv_soc_top_inst.PENABLE;
        end
    end
    
    // Read Data, Ready & Error are sampled directly from the interconnect
    assign apb_if_inst.PRDATA  = dut.riscv_soc_top_inst.PRDATA;
    assign apb_if_inst.PREADY  = dut.riscv_soc_top_inst.PREADY;
    assign apb_if_inst.PSLVERR = dut.riscv_soc_top_inst.PSLVERR;

    // 4. Top-Level DUT Instantiation
    soc_top dut (
        .PCLK       (PCLK),
        .PRESETn    (PRESETn),
        .SCLK       (SCLK),
        .MOSI       (MOSI),
        .MISO       (MISO),
        .SS_N       (SS_N),
        .pwm_out    (pwm_out),
        .tach_pulse (tach_pulse),
        .uart_rx    (uart_rx),
        .uart_tx    (uart_tx)
    );

    // 5. Virtual UART Terminal (Listener only)
    virtual_uart u_virtual_uart (
        .rx_pin (uart_tx),
        .tx_pin ()
    );

    // 6. APB protocol SVA is bound into soc_top (see apb_assertions.sv)

    // 7. Publish Virtual Interfaces to UVM Database & Start Test
    initial begin
        PRESETn = 0;
        #100ns;
        PRESETn = 1;
    end

    initial begin
        uvm_config_db#(virtual apb_if)::set(null, "uvm_test_top.env.spi_sub_env*",  "vif", apb_if_inst);
        uvm_config_db#(virtual apb_if)::set(null, "uvm_test_top.env.pwm_sub_env*",  "vif", apb_if_inst);
        uvm_config_db#(virtual apb_if)::set(null, "uvm_test_top.env.sram_sub_env*", "vif", apb_if_inst);
        uvm_config_db#(virtual apb_if)::set(null, "uvm_test_top.env.uart_sub_env*", "vif", apb_if_inst);

        uvm_config_db#(virtual pwm_if)::set(null, "uvm_test_top.env.pwm_sub_env*",  "vif", pwm_if_inst);

        uvm_config_db#(virtual uart_if.DRIVER)::set(null,  "uvm_test_top.env.uart_sub_env.agent.driver",  "vif", uart_if_inst);
        uvm_config_db#(virtual uart_if.MONITOR)::set(null, "uvm_test_top.env.uart_sub_env.agent.monitor", "vif", uart_if_inst);

        run_test("system_base_test");
    end

endmodule