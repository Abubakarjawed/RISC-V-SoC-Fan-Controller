`timescale 1ns/1ps
//=============================================================
// riscv_probe_if.sv
// Whitebox probe: tb_top wires this up to internal DUT signals
// via hierarchical reference (pc_q, and dmem word 0's four byte
// lanes), so the scoreboard can check end-of-test state without
// any class code touching `dut.*` paths directly. Same signals
// the original directed TB peeked at.
//=============================================================
interface riscv_probe_if (input logic PCLK);
    logic [31:0] pc_q;
    logic [7:0]  dmem_b0, dmem_b1, dmem_b2, dmem_b3;

    function automatic logic [31:0] result_word();
        return {dmem_b3, dmem_b2, dmem_b1, dmem_b0};
    endfunction
endinterface : riscv_probe_if
