`timescale 1ns/1ps

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
