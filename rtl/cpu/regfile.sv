`timescale 1ns/1ps
//=============================================================
// regfile.sv
// 32 x 32-bit general purpose register file.
// x0 is hardwired to zero. Two asynchronous read ports,
// one synchronous write port (write-through on same-cycle
// read of the write address, standard for single-cycle cores).
//=============================================================
module regfile (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [4:0]  rs1_addr,
    input  logic [4:0]  rs2_addr,
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data,

    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data,
    input  logic        rd_we
);

    logic [31:0] regs [1:31];   // x1..x31 (x0 is not stored)

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 1; i < 32; i = i + 1) begin
                regs[i] <= 32'h0;
            end
        end else if (rd_we && (rd_addr != 5'd0)) begin
            regs[rd_addr] <= rd_data;
        end
    end

    // Read port 1, with write-through bypass
    always_comb begin
        if (rs1_addr == 5'd0)
            rs1_data = 32'h0;
        else if (rd_we && (rd_addr == rs1_addr))
            rs1_data = rd_data;
        else
            rs1_data = regs[rs1_addr];
    end

    // Read port 2, with write-through bypass
    always_comb begin
        if (rs2_addr == 5'd0)
            rs2_data = 32'h0;
        else if (rd_we && (rd_addr == rs2_addr))
            rs2_data = rd_data;
        else
            rs2_data = regs[rs2_addr];
    end

endmodule
