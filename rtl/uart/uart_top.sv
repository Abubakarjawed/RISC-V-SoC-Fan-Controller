`timescale 1ns/1ps

import uart_pkg::*;

module uart_top #(
    parameter int unsigned CLK_HZ    = 50_000_000,
    parameter int unsigned BAUD_RATE = 115_200
) (
    input  logic       clk,
    input  logic       rst_n,
    input  parity_e    parity_mode,
    input  stop_e      stop_mode,
    input  logic [7:0] tx_data,
    input  logic       tx_start,
    output logic       tx_ready,
    output logic       uart_tx,
    input  logic       uart_rx,
    output logic [7:0] rx_data,
    output logic       rx_done,
    output logic       parity_err
);
    logic baud_tick;

    baud_generator #(
        .CLK_HZ    (CLK_HZ), 
        .BAUD_RATE (BAUD_RATE)
    ) baud_gen_inst (
        .clk       (clk), 
        .rst_n     (rst_n), 
        .baud_tick (baud_tick)
    );

    transmitter trans_inst (
        .clk        (clk), 
        .rst_n      (rst_n), 
        .baud_tick  (baud_tick),
        .tx_data    (tx_data), 
        .tx_start   (tx_start), 
        .parity_mode(parity_mode),
        .stop_mode  (stop_mode), 
        .tx_pin     (uart_tx), 
        .tx_ready   (tx_ready)
    );

    receiver recv_inst (
        .clk        (clk), 
        .rst_n      (rst_n), 
        .baud_tick  (baud_tick), 
        .rx_pin     (uart_rx),
        .parity_mode(parity_mode), 
        .stop_mode  (stop_mode), 
        .rx_done    (rx_done),
        .rx_data    (rx_data), 
        .parity_err (parity_err)
    );
endmodule
