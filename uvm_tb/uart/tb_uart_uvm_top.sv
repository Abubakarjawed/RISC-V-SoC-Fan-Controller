`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import uart_uvm_pkg::*;

class uart_test extends uvm_test;
    `uvm_component_utils(uart_test)

    uart_environment env;

    function new(string name = "uart_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = uart_environment::type_id::create("env", this);
    endfunction

    // task run_phase(uvm_phase phase);
    //     uart_tx_string_seq seq;

    //     phase.raise_objection(this);

    //     seq = uart_tx_string_seq::type_id::create("seq");
    //     seq.start(env.agent.sequencer);

    //     #100us;
    //     phase.drop_objection(this);
    // endtask

    virtual task run_phase(uvm_phase phase);
        uart_full_coverage_seq cov_seq;
        
        phase.raise_objection(this);
        
        cov_seq = uart_full_coverage_seq::type_id::create("cov_seq");
        cov_seq.start(env.agent.sequencer);
        
        #100us;
        phase.drop_objection(this);
    endtask
endclass // uart_test

module tb_uart_uvm_top;
    logic clk;
    logic rst_n;

    // Clock Generation (50 MHz)
    initial clk = 0;
    always #10ns clk = ~clk;

    // Interface Instance
    uart_if uart_if_inst (
        .PCLK    (clk), 
        .PRESETn (rst_n)
    );

    // Device Under Test (DUT)
    uart_soc_top dut (
        .PCLK    (uart_if_inst.PCLK),
        .PRESETn (uart_if_inst.PRESETn),
        .PADDR   (uart_if_inst.PADDR),
        .PWRITE  (uart_if_inst.PWRITE),
        .PSEL    (uart_if_inst.PSEL),
        .PENABLE (uart_if_inst.PENABLE),
        .PWDATA  (uart_if_inst.PWDATA),
        .PRDATA  (uart_if_inst.PRDATA),
        .PREADY  (uart_if_inst.PREADY),
        .PSLVERR (uart_if_inst.PSLVERR),
        .uart_rx (uart_if_inst.uart_rx),
        .uart_tx (uart_if_inst.uart_tx)
    );

    // Initial Reset Sequence & UVM Configuration DB Registration
    initial begin
        rst_n = 1'b0;
        #100ns;
        rst_n = 1'b1;
    end

    initial begin
        // Pass interface handles into DB
        uvm_config_db#(virtual uart_if.DRIVER)::set(null, "uvm_test_top.env.agent.driver", "vif", uart_if_inst);
        uvm_config_db#(virtual uart_if.MONITOR)::set(null, "uvm_test_top.env.agent.monitor", "vif", uart_if_inst);

        run_test("uart_test");
    end

endmodule // tb_uart_uvm_top