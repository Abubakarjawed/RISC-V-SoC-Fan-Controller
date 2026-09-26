`timescale 1ns/1ps
//=============================================================
// imem.sv
// Instruction SRAM. Combinational (single-cycle) read, word
// addressed. Contents are preloaded from INIT_FILE (hex, one
// 32-bit word per line) which the testbench points at the
// compiled program image.
//=============================================================
module imem #(
    parameter int  DEPTH_WORDS = 1024,               // 4 KB default
    parameter      INIT_FILE   = ""
) (
    input  logic [31:0] addr,      // byte address (word-aligned)
    output logic [31:0] rdata
);

    localparam int ADDR_BITS = $clog2(DEPTH_WORDS);

    logic [31:0] mem [0:DEPTH_WORDS-1];

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    assign rdata = mem[addr[ADDR_BITS+1:2]];

endmodule
