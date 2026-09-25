`timescale 1ns/1ps

module sram_engine (
    input  logic       PCLK,
    input  logic       PRESETn,

    input  logic        wr_en,
    input  logic [7:0]  addr,
    input  logic [7:0]  wr_data,
    output logic [7:0]  rd_data
);

    // Configuration SRAM: 256 bytes, byte-addressable.
    // Holds fan profiles / config values loaded by the CPU (or preloaded by
    // the testbench per the "Expected Operation" requirement in the spec).
    logic [7:0] mem [0:255];

    always_ff @(posedge PCLK) begin
        if (wr_en) begin
            mem[addr] <= wr_data;
        end
    end

    // Combinational read - matches the team's existing fifo module style
    // (apb_fifo.sv: assign rd_data = mem[read_pointer];)
    assign rd_data = mem[addr];

endmodule
