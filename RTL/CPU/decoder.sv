`timescale 1ns/1ps
//=============================================================
// decoder.sv
// Combinationally decodes a 32-bit RV32I instruction word into
// the control signals used by the datapath. Purely combinational
// (no state) - the FSM/enable timing lives in cpu_control.sv.
//=============================================================
module decoder (
    input  logic [31:0] instr,

    output logic [4:0]  rs1_addr,
    output logic [4:0]  rs2_addr,
    output logic [4:0]  rd_addr,
    output logic [2:0]  funct3,
    output logic [6:0]  funct7,
    output logic [6:0]  opcode,

    output logic [2:0]  imm_sel,     // imm_gen format select
    output logic [3:0]  alu_op,
    output logic         alu_src_imm, // 1: ALU operand B = immediate, 0 = rs2
    output logic         alu_pc_a,    // 1: ALU operand A = PC (AUIPC), 0 = rs1

    output logic         reg_write,
    output logic         mem_read,
    output logic         mem_write,
    output logic [1:0]   wb_sel,      // 00=alu, 01=mem, 10=pc+4(link), 11=imm(lui)

    output logic         is_branch,
    output logic         is_jal,
    output logic         is_jalr,

    output logic         illegal_instr
);

    // ---- RV32I base opcodes ----
    localparam logic [6:0] OP_LUI    = 7'b0110111;
    localparam logic [6:0] OP_AUIPC  = 7'b0010111;
    localparam logic [6:0] OP_JAL    = 7'b1101111;
    localparam logic [6:0] OP_JALR   = 7'b1100111;
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_LOAD   = 7'b0000011;
    localparam logic [6:0] OP_STORE  = 7'b0100011;
    localparam logic [6:0] OP_IMM    = 7'b0010011;
    localparam logic [6:0] OP_REG    = 7'b0110011;
    localparam logic [6:0] OP_SYSTEM = 7'b1110011; // ECALL/EBREAK - decoded but treated as NOP

    // ---- ALU op encodings (must match alu.sv) ----
    localparam logic [3:0] ALU_ADD  = 4'b0000;
    localparam logic [3:0] ALU_SUB  = 4'b0001;
    localparam logic [3:0] ALU_SLL  = 4'b0010;
    localparam logic [3:0] ALU_SLT  = 4'b0011;
    localparam logic [3:0] ALU_SLTU = 4'b0100;
    localparam logic [3:0] ALU_XOR  = 4'b0101;
    localparam logic [3:0] ALU_SRL  = 4'b0110;
    localparam logic [3:0] ALU_SRA  = 4'b0111;
    localparam logic [3:0] ALU_OR   = 4'b1000;
    localparam logic [3:0] ALU_AND  = 4'b1001;
    localparam logic [3:0] ALU_PASS_B = 4'b1010;

    localparam logic [2:0] IMM_I = 3'b000;
    localparam logic [2:0] IMM_S = 3'b001;
    localparam logic [2:0] IMM_B = 3'b010;
    localparam logic [2:0] IMM_U = 3'b011;
    localparam logic [2:0] IMM_J = 3'b100;

    assign opcode   = instr[6:0];
    assign rd_addr  = instr[11:7];
    assign funct3   = instr[14:12];
    assign rs1_addr = instr[19:15];
    assign rs2_addr = instr[24:20];
    assign funct7   = instr[31:25];

    // R-type / I-type ALU op decode (shared by OP_REG and OP_IMM)
    logic [3:0] alu_op_calc;
    always_comb begin
        case (funct3)
            3'b000: alu_op_calc = (opcode == OP_REG && funct7[5]) ? ALU_SUB : ALU_ADD; // SUB only valid for R-type
            3'b001: alu_op_calc = ALU_SLL;
            3'b010: alu_op_calc = ALU_SLT;
            3'b011: alu_op_calc = ALU_SLTU;
            3'b100: alu_op_calc = ALU_XOR;
            3'b101: alu_op_calc = funct7[5] ? ALU_SRA : ALU_SRL;
            3'b110: alu_op_calc = ALU_OR;
            3'b111: alu_op_calc = ALU_AND;
            default: alu_op_calc = ALU_ADD;
        endcase
    end

    always_comb begin
        // defaults (safe / NOP-like)
        imm_sel       = IMM_I;
        alu_op        = ALU_ADD;
        alu_src_imm   = 1'b0;
        alu_pc_a      = 1'b0;
        reg_write     = 1'b0;
        mem_read      = 1'b0;
        mem_write     = 1'b0;
        wb_sel        = 2'b00;
        is_branch     = 1'b0;
        is_jal        = 1'b0;
        is_jalr       = 1'b0;
        illegal_instr = 1'b0;

        case (opcode)
            OP_LUI: begin
                imm_sel     = IMM_U;
                alu_src_imm = 1'b1;
                reg_write   = 1'b1;
                wb_sel      = 2'b11;      // write immediate directly
            end

            OP_AUIPC: begin
                imm_sel     = IMM_U;
                alu_src_imm = 1'b1;
                alu_pc_a    = 1'b1;       // ALU: PC + imm
                alu_op      = ALU_ADD;
                reg_write   = 1'b1;
                wb_sel      = 2'b00;
            end

            OP_JAL: begin
                imm_sel     = IMM_J;
                is_jal      = 1'b1;
                reg_write   = 1'b1;
                wb_sel      = 2'b10;      // rd = pc + 4
            end

            OP_JALR: begin
                imm_sel     = IMM_I;
                is_jalr     = 1'b1;
                reg_write   = 1'b1;
                wb_sel      = 2'b10;      // rd = pc + 4
            end

            OP_BRANCH: begin
                imm_sel     = IMM_B;
                is_branch   = 1'b1;
                alu_op      = ALU_SUB;    // unused by branch_unit but harmless
            end

            OP_LOAD: begin
                imm_sel     = IMM_I;
                alu_src_imm = 1'b1;
                alu_op      = ALU_ADD;    // effective address = rs1 + imm
                mem_read    = 1'b1;
                reg_write   = 1'b1;
                wb_sel      = 2'b01;      // write memory data
            end

            OP_STORE: begin
                imm_sel     = IMM_S;
                alu_src_imm = 1'b1;
                alu_op      = ALU_ADD;    // effective address = rs1 + imm
                mem_write   = 1'b1;
            end

            OP_IMM: begin
                imm_sel     = IMM_I;
                alu_src_imm = 1'b1;
                alu_op      = alu_op_calc;
                reg_write   = 1'b1;
                wb_sel      = 2'b00;
            end

            OP_REG: begin
                alu_src_imm = 1'b0;
                alu_op      = alu_op_calc;
                reg_write   = 1'b1;
                wb_sel      = 2'b00;
            end

            OP_SYSTEM: begin
                // ECALL / EBREAK / CSR - treated as architectural NOP
                reg_write   = 1'b0;
            end

            default: begin
                illegal_instr = 1'b1;
            end
        endcase
    end

endmodule
