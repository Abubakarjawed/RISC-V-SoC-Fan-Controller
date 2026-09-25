`timescale 1ns/1ps
//=============================================================
// branch_unit.sv
// Evaluates the branch condition for BEQ/BNE/BLT/BGE/BLTU/BGEU.
//=============================================================
module branch_unit (
    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,
    input  logic [2:0]  funct3,
    input  logic        is_branch,   // 1 = current instr is a BRANCH opcode
    output logic        branch_taken
);

    localparam logic [2:0] F3_BEQ  = 3'b000;
    localparam logic [2:0] F3_BNE  = 3'b001;
    localparam logic [2:0] F3_BLT  = 3'b100;
    localparam logic [2:0] F3_BGE  = 3'b101;
    localparam logic [2:0] F3_BLTU = 3'b110;
    localparam logic [2:0] F3_BGEU = 3'b111;

    logic cond;

    always_comb begin
        case (funct3)
            F3_BEQ : cond = (rs1_data == rs2_data);
            F3_BNE : cond = (rs1_data != rs2_data);
            F3_BLT : cond = ($signed(rs1_data)  <  $signed(rs2_data));
            F3_BGE : cond = ($signed(rs1_data)  >= $signed(rs2_data));
            F3_BLTU: cond = (rs1_data  <  rs2_data);
            F3_BGEU: cond = (rs1_data  >= rs2_data);
            default: cond = 1'b0;
        endcase
    end

    assign branch_taken = is_branch && cond;

endmodule
