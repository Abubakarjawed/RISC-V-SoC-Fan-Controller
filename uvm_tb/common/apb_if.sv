`timescale 1ns/1ps
// ---------------------------------------------------------------------
// apb_if : sirf signal bundle hai, DUT (sram_soc_top / pwm_soc_top /
// spi_soc_top) ke APB ports se seedha connect hota hai. Driver aur
// monitor isi interface ki virtual handle uvm_config_db se uthate hain.
// ---------------------------------------------------------------------
interface apb_if (input logic PCLK, input logic PRESETn);
    logic        PSEL;
    logic        PENABLE;
    logic        PWRITE;
    logic [31:0] PADDR;
    logic [31:0] PWDATA;
    logic [31:0] PRDATA;
    logic        PREADY;
    logic        PSLVERR;
endinterface
