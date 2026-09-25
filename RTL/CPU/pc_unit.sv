`timescale 1ns/1ps
//=============================================================
// pc_unit.sv
// Program Counter register + next-PC mux for the RV32I core.
//
// next PC sources:
//   00 : PC + 4                    (sequential)
//   01 : PC + imm                  (branch taken / JAL)
//   10 : (rs1 + imm) & ~1          (JALR)
//   11 : reserved (defaults to PC+4)
//
// pc_stall holds the PC (used while the bus/APB bridge is busy
// servicing a load/store so the "single-cycle" core can support
// multi-cycle memory-mapped peripherals).
//=============================================================
module pc_unit (
    input  logic        clk,
    input  logic        rst_n,

    input  logic         pc_stall,      // freeze PC (bus wait-state)
    input  logic [1:0]   pc_sel,        // next-PC select
    input  logic [31:0]  imm,           // branch/jal immediate
    input  logic [31:0]  rs1_data,      // for JALR

    output logic [31:0]  pc,            // current PC (fetch address)
    output logic [31:0]  pc_plus4       // PC + 4 (for link register)
);

    localparam logic [1:0] PC_SEL_PLUS4 = 2'b00;
    localparam logic [1:0] PC_SEL_BRJAL = 2'b01;
    localparam logic [1:0] PC_SEL_JALR  = 2'b10;

    logic [31:0] pc_q;
    logic [31:0] pc_next;

    assign pc       = pc_q;
    assign pc_plus4 = pc_q + 32'd4;

    always_comb begin
        case (pc_sel)
            PC_SEL_PLUS4: pc_next = pc_q + 32'd4;
            PC_SEL_BRJAL: pc_next = pc_q + imm;
            PC_SEL_JALR : pc_next = (rs1_data + imm) & ~32'h1;
            default     : pc_next = pc_q + 32'd4;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_q <= 32'h0000_0000;   // reset vector
        end else if (!pc_stall) begin
            pc_q <= pc_next;
        end
    end

endmodule
