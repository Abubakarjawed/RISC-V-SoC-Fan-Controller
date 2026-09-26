`timescale 1ns/1ps

import uart_pkg::*;

module uart_soc_top #(
    parameter int CLK_HZ    = uart_pkg::CLK_HZ,
    parameter int BAUD_RATE = uart_pkg::BAUD_RATE
) (
    // APB Bus Interface
    input  logic                    PCLK,
    input  logic                    PRESETn,
    input  logic                    PSEL,
    input  logic                    PENABLE,
    input  logic                    PWRITE,
    input  logic [ADDR_WIDTH_32-1:0] PADDR,
    input  logic [DATA_WIDTH_32-1:0] PWDATA,
    output logic [DATA_WIDTH_32-1:0] PRDATA,
    output logic                    PREADY,
    output logic                    PSLVERR,

    // External Physical Pin Interface
    input  logic                    uart_rx,
    output logic                    uart_tx
);

    // Interconnect Wire Signals
    logic                    tx_start;
    logic [DATA_WIDTH_8-1:0] tx_data;
    parity_e                 parity_mode;
    stop_e                   stop_mode;
    logic                    tx_ready;
    logic [DATA_WIDTH_8-1:0] rx_data;
    logic                    rx_done;
    logic                    parity_err;

    // APB Slave Controller
    uart_apb uart_apb_inst (
        .PCLK        (PCLK),
        .PRESETn     (PRESETn),
        .PSEL        (PSEL),
        .PENABLE     (PENABLE),
        .PWRITE      (PWRITE),
        .PADDR       (PADDR),
        .PWDATA      (PWDATA),
        .PRDATA      (PRDATA),
        .PREADY      (PREADY),
        .PSLVERR     (PSLVERR),
        
        // Interconnect outputs/inputs
        .tx_start    (tx_start),
        .tx_data     (tx_data),
        .parity_mode (parity_mode),
        .stop_mode   (stop_mode),
        .tx_ready    (tx_ready),
        .rx_data     (rx_data),
        .rx_done     (rx_done),
        .parity_err  (parity_err)
    );

    // Core Hardware Controller
    uart_engine #(
        .CLK_HZ    (CLK_HZ),
        .BAUD_RATE (BAUD_RATE)
    ) uart_engine_inst (
        .clk         (PCLK),
        .rst_n       (PRESETn),
        .parity_mode (parity_mode),
        .stop_mode   (stop_mode),
        .tx_data     (tx_data),
        .tx_start    (tx_start),
        .tx_ready    (tx_ready),
        .uart_tx     (uart_tx),
        .uart_rx     (uart_rx),
        .rx_data     (rx_data),
        .rx_done     (rx_done),
        .parity_err  (parity_err)
    );

endmodule