`timescale 1ns/1ps

interface uart_if (input logic PCLK, input logic PRESETn);
    // APB Bus Signals
    logic        PSEL;
    logic        PENABLE;
    logic        PWRITE;
    logic [31:0] PADDR;
    logic [31:0] PWDATA;
    logic [31:0] PRDATA;
    logic        PREADY;
    logic        PSLVERR;

    // External Serial UART Pins
    logic        uart_rx;
    logic        uart_tx;

    // Modports for Driver and Monitor
    modport DRIVER (
        input PCLK, PRESETn, PREADY, PRDATA, 
        output PSEL, PENABLE, PWRITE, PADDR, PWDATA
    );

    modport MONITOR (
        input PCLK, PRESETn, PSEL, PENABLE, PWRITE, PADDR, PWDATA, PRDATA, PREADY, PSLVERR, uart_rx, uart_tx
    );
    
endinterface