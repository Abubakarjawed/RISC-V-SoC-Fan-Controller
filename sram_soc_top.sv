`timescale 1ns/1ps

module sram_soc_top (
    input  logic       PCLK,
    input  logic       PRESETn,
    input  logic       PSEL,
    input  logic       PENABLE,
    input  logic       PWRITE,
    input  logic [31:0] PADDR,
    input  logic [31:0] PWDATA,
    output logic [31:0] PRDATA,
    output logic       PREADY,
    output logic       PSLVERR
);

    logic       mem_wr_en;
    logic [7:0] mem_addr;
    logic [7:0] mem_wr_data;
    logic [7:0] mem_rd_data;

    apb_slave_fsm_sram u_apb_slave_fsm_sram (
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

        .mem_wr_en   (mem_wr_en),
        .mem_addr    (mem_addr),
        .mem_wr_data (mem_wr_data),
        .mem_rd_data (mem_rd_data)
    );

    sram_engine u_sram_engine (
        .PCLK     (PCLK),
        .PRESETn  (PRESETn),
        .wr_en    (mem_wr_en),
        .addr     (mem_addr),
        .wr_data  (mem_wr_data),
        .rd_data  (mem_rd_data)
    );

endmodule
