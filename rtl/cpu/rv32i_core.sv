`timescale 1ns/1ps
//=============================================================
// rv32i_core.sv
// Synthesizable single-cycle RV32I core (with wait-state
// stalling for slow memory-mapped peripherals).
//
// - Instruction memory: combinational read, word addressed.
// - Data memory bus: generic byte-addressed bus with byte
//   write-enables, used for both the on-chip data SRAM and
//   (through a bridge, outside this module) the APB peripheral
//   region. A single "dmem_ready" handshake lets the bus
//   insert wait states for slow peripherals; the SoC top level
//   is responsible for the address decode that produces
//   is_periph_addr / dmem_ready.
//=============================================================
module rv32i_core (
    input  logic         clk,
    input  logic         rst_n,

    // ---- Instruction memory interface (combinational read) ----
    output logic [31:0]  imem_addr,
    input  logic [31:0]  imem_rdata,

    // ---- Data memory / peripheral bus ----
    output logic [31:0]  dmem_addr,
    output logic [31:0]  dmem_wdata,   // write data, pre-aligned to the correct byte lane(s)
    output logic [3:0]   dmem_byte_en, // byte write enables (SB/SH/SW)
    output logic         dmem_read,
    output logic         dmem_write,
    input  logic [31:0]  dmem_rdata,   // read word, byte lane(s) valid per address/funct3

    // ---- Address-decode / handshake supplied by the SoC top ----
    input  logic         is_periph_addr, // current dmem_addr targets the APB peripheral region
    input  logic         periph_done     // pulses for the cycle an APB transaction completes
);

    //-----------------------------------------------------------
    // Fetch
    //-----------------------------------------------------------
    logic [31:0] pc_q, pc_plus4;
    logic [1:0]  pc_sel;
    logic        pc_stall;
    logic [31:0] instr;

    assign imem_addr = pc_q;
    assign instr      = imem_rdata;

    //-----------------------------------------------------------
    // Decode
    //-----------------------------------------------------------
    logic [4:0] rs1_addr, rs2_addr, rd_addr;
    logic [2:0] funct3;
    logic [6:0] funct7, opcode;
    logic [2:0] imm_sel;
    logic [3:0] alu_op;
    logic       alu_src_imm, alu_pc_a;
    logic       reg_write_d, mem_read, mem_write;
    logic [1:0] wb_sel;
    logic       is_branch, is_jal, is_jalr;
    logic       illegal_instr;

    decoder u_decoder (
        .instr          (instr),
        .rs1_addr       (rs1_addr),
        .rs2_addr       (rs2_addr),
        .rd_addr        (rd_addr),
        .funct3         (funct3),
        .funct7         (funct7),
        .opcode         (opcode),
        .imm_sel        (imm_sel),
        .alu_op         (alu_op),
        .alu_src_imm    (alu_src_imm),
        .alu_pc_a       (alu_pc_a),
        .reg_write      (reg_write_d),
        .mem_read       (mem_read),
        .mem_write      (mem_write),
        .wb_sel         (wb_sel),
        .is_branch      (is_branch),
        .is_jal         (is_jal),
        .is_jalr        (is_jalr),
        .illegal_instr  (illegal_instr)
    );

    logic [31:0] imm;
    imm_gen u_imm_gen (
        .instr   (instr),
        .imm_sel (imm_sel),
        .imm_out (imm)
    );

    logic [31:0] rs1_data, rs2_data;
    logic [31:0] rd_wdata;
    logic        reg_write_commit;

    regfile u_regfile (
        .clk       (clk),
        .rst_n     (rst_n),
        .rs1_addr  (rs1_addr),
        .rs2_addr  (rs2_addr),
        .rs1_data  (rs1_data),
        .rs2_data  (rs2_data),
        .rd_addr   (rd_addr),
        .rd_data   (rd_wdata),
        .rd_we     (reg_write_commit)
    );

    //-----------------------------------------------------------
    // Execute
    //-----------------------------------------------------------
    logic [31:0] alu_operand_a, alu_operand_b, alu_result;
    logic        alu_zero;

    assign alu_operand_a = alu_pc_a  ? pc_q     : rs1_data;
    assign alu_operand_b = alu_src_imm ? imm    : rs2_data;

    alu u_alu (
        .operand_a (alu_operand_a),
        .operand_b (alu_operand_b),
        .alu_op    (alu_op),
        .result    (alu_result),
        .zero      (alu_zero)
    );

    logic branch_taken;
    branch_unit u_branch_unit (
        .rs1_data     (rs1_data),
        .rs2_data     (rs2_data),
        .funct3       (funct3),
        .is_branch    (is_branch),
        .branch_taken (branch_taken)
    );

    // Next-PC select: branch/jal -> PC+imm, jalr -> rs1+imm, else PC+4
    always_comb begin
        if (is_jalr)
            pc_sel = 2'b10;
        else if (is_jal || branch_taken)
            pc_sel = 2'b01;
        else
            pc_sel = 2'b00;
    end

    pc_unit u_pc_unit (
        .clk       (clk),
        .rst_n     (rst_n),
        .pc_stall  (pc_stall),
        .pc_sel    (pc_sel),
        .imm       (imm),
        .rs1_data  (rs1_data),
        .pc        (pc_q),
        .pc_plus4  (pc_plus4)
    );

    //-----------------------------------------------------------
    // Memory stage - byte lane handling for LB/LH/LW/LBU/LHU/SB/SH/SW
    //-----------------------------------------------------------
    logic [1:0] addr_lsb;
    assign addr_lsb   = alu_result[1:0];
    assign dmem_addr  = alu_result;
    assign dmem_read  = mem_read;
    assign dmem_write = mem_write;

    // Store data alignment + byte enables
    always_comb begin
        dmem_wdata   = 32'h0;
        dmem_byte_en = 4'b0000;
        if (mem_write) begin
            case (funct3[1:0])
                2'b00: begin // SB
                    dmem_wdata   = {4{rs2_data[7:0]}};
                    dmem_byte_en = 4'b0001 << addr_lsb;
                end
                2'b01: begin // SH
                    dmem_wdata   = {2{rs2_data[15:0]}};
                    dmem_byte_en = addr_lsb[1] ? 4'b1100 : 4'b0011;
                end
                default: begin // SW
                    dmem_wdata   = rs2_data;
                    dmem_byte_en = 4'b1111;
                end
            endcase
        end
    end

    // Load data extraction + sign/zero extension
    logic [7:0]  load_byte;
    logic [15:0] load_half;
    logic [31:0] load_data;

    always_comb begin
        case (addr_lsb)
            2'b00: load_byte = dmem_rdata[7:0];
            2'b01: load_byte = dmem_rdata[15:8];
            2'b10: load_byte = dmem_rdata[23:16];
            2'b11: load_byte = dmem_rdata[31:24];
        endcase
        load_half = addr_lsb[1] ? dmem_rdata[31:16] : dmem_rdata[15:0];

        case (funct3)
            3'b000: load_data = {{24{load_byte[7]}}, load_byte};   // LB
            3'b001: load_data = {{16{load_half[15]}}, load_half};  // LH
            3'b010: load_data = dmem_rdata;                        // LW
            3'b100: load_data = {24'h0, load_byte};                // LBU
            3'b101: load_data = {16'h0, load_half};                // LHU
            default: load_data = dmem_rdata;
        endcase
    end

    //-----------------------------------------------------------
    // Control / wait-state handling for peripheral accesses
    //-----------------------------------------------------------
    logic mem_stage_valid;

    cpu_control u_cpu_control (
        .clk             (clk),
        .rst_n           (rst_n),
        .mem_read        (mem_read),
        .mem_write       (mem_write),
        .is_periph_addr  (is_periph_addr),
        .periph_done     (periph_done),
        .periph_req      (),
        .pc_stall        (pc_stall),
        .mem_stage_valid (mem_stage_valid)
    );

    //-----------------------------------------------------------
    // Write-back mux
    //-----------------------------------------------------------
    always_comb begin
        case (wb_sel)
            2'b00: rd_wdata = alu_result;   // ALU / AUIPC / R-type / I-type
            2'b01: rd_wdata = load_data;    // LOAD
            2'b10: rd_wdata = pc_plus4;     // JAL / JALR link
            2'b11: rd_wdata = imm;          // LUI
            default: rd_wdata = alu_result;
        endcase
    end

    // Only commit the register write once any outstanding peripheral
    // access for this instruction has completed.
    assign reg_write_commit = reg_write_d && mem_stage_valid;

endmodule
