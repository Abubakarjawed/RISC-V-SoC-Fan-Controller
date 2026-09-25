`timescale 1ns/1ps

module spi_soc_top (
    input  logic       PCLK,
    input  logic       PRESETn,
    input  logic       PSEL,
    input  logic       PENABLE,
    input  logic       PWRITE,
    input  logic [31:0] PADDR,
    input  logic [31:0] PWDATA,
    output logic [31:0] PRDATA,
    output logic       PREADY,
    output logic       PSLVERR,

    // physical SPI pins
    output logic SCLK,
    output logic MOSI,
    input  logic MISO,
    output logic SS_N
);

    logic       tx_fifo_rd_en;
    logic [7:0] tx_fifo_rd_data;
    logic       tx_fifo_empty;
    logic       rx_fifo_wr_en;
    logic [7:0] rx_fifo_wr_data;
    logic       rx_fifo_full;
    logic       engine_enable;
    logic       sclk_tick;

    apb_slave_fsm u_apb_slave_fsm (
        .PCLK             (PCLK),
        .PRESETn          (PRESETn),
        .PSEL             (PSEL),
        .PENABLE          (PENABLE),
        .PWRITE           (PWRITE),
        .PADDR            (PADDR),
        .PWDATA           (PWDATA),
        .PRDATA           (PRDATA),
        .PREADY           (PREADY),
        .PSLVERR          (PSLVERR),

        .tx_fifo_rd_en    (tx_fifo_rd_en),
        .tx_fifo_rd_data  (tx_fifo_rd_data),
        .tx_fifo_empty    (tx_fifo_empty),

        .rx_fifo_wr_en    (rx_fifo_wr_en),
        .rx_fifo_wr_data  (rx_fifo_wr_data),
        .rx_fifo_full     (rx_fifo_full),

        .engine_enable    (engine_enable),
        .sclk_tick        (sclk_tick)
    );

    spi_engine u_spi_engine (
        .PCLK             (PCLK),
        .PRESETn          (PRESETn),
        .sclk_tick        (sclk_tick),
        .enable           (engine_enable),

        .tx_fifo_empty    (tx_fifo_empty),
        .tx_fifo_rd_en    (tx_fifo_rd_en),
        .tx_fifo_rd_data  (tx_fifo_rd_data),

        .rx_fifo_full     (rx_fifo_full),
        .rx_fifo_wr_en    (rx_fifo_wr_en),
        .rx_fifo_wr_data  (rx_fifo_wr_data),

        .SCLK             (SCLK),
        .MOSI             (MOSI),
        .MISO             (MISO),
        .SS_N             (SS_N)
    );

endmodule
