`timescale 1ns/1ps
//=============================================================
// imm_gen.sv
// Sign-extends / builds the immediate for every RV32I
// instruction format from the raw 32-bit instruction.
//=============================================================
module imm_gen (
    input  logic [31:0] instr,
    input  logic [2:0]  imm_sel,   // format select, from decoder
    output logic [31:0] imm_out
);

    localparam logic [2:0] IMM_I = 3'b000;
    localparam logic [2:0] IMM_S = 3'b001;
    localparam logic [2:0] IMM_B = 3'b010;
    localparam logic [2:0] IMM_U = 3'b011;
    localparam logic [2:0] IMM_J = 3'b100;

    always_comb begin
        case (imm_sel)
            IMM_I: imm_out = {{20{instr[31]}}, instr[31:20]};

            IMM_S: imm_out = {{20{instr[31]}}, instr[31:25], instr[11:7]};

            IMM_B: imm_out = {{19{instr[31]}}, instr[31], instr[7],
                               instr[30:25], instr[11:8], 1'b0};

            IMM_U: imm_out = {instr[31:12], 12'b0};

            IMM_J: imm_out = {{11{instr[31]}}, instr[31], instr[19:12],
                               instr[20], instr[30:21], 1'b0};

            default: imm_out = 32'h0;
        endcase
    end

endmodule
