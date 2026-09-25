`timescale 1ns/1ps
//=============================================================
// dmem.sv
// On-chip data / configuration SRAM. Combinational read so the
// single-cycle core sees data the same cycle it drives the
// address; byte-lane write enables support SB/SH/SW.
//=============================================================
module dmem #(
    parameter int DEPTH_WORDS = 1024                 // 4 KB default
) (
    input  logic         clk,
    input  logic         rst_n,

    input  logic [31:0]  addr,       // byte address (word-aligned access assumed)
    input  logic [31:0]  wdata,      // pre-aligned write data (see rv32i_core)
    input  logic [3:0]   byte_en,
    input  logic         write_en,   // qualifies byte_en (must also be word-in-range)
    output logic [31:0]  rdata
);

    localparam int ADDR_BITS = $clog2(DEPTH_WORDS);

    logic [7:0] mem0 [0:DEPTH_WORDS-1];
    logic [7:0] mem1 [0:DEPTH_WORDS-1];
    logic [7:0] mem2 [0:DEPTH_WORDS-1];
    logic [7:0] mem3 [0:DEPTH_WORDS-1];

    wire [ADDR_BITS-1:0] windex = addr[ADDR_BITS+1:2];

    always_ff @(posedge clk) begin
        if (write_en) begin
            if (byte_en[0]) mem0[windex] <= wdata[7:0];
            if (byte_en[1]) mem1[windex] <= wdata[15:8];
            if (byte_en[2]) mem2[windex] <= wdata[23:16];
            if (byte_en[3]) mem3[windex] <= wdata[31:24];
        end
    end

    assign rdata = {mem3[windex], mem2[windex], mem1[windex], mem0[windex]};

endmodule
