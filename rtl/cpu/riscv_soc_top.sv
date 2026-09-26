`timescale 1ns/1ps
//=============================================================
// riscv_soc_top.sv
// Sub-system: Core + IMEM + DMEM + APB Bridge + Interconnect
//=============================================================
module riscv_soc_top #(
    parameter string IMEM_INIT_FILE   = "",
    parameter int    IMEM_DEPTH_WORDS = 1024,
    parameter int    DMEM_DEPTH_WORDS = 1024
) (
    input  logic        PCLK,
    input  logic        PRESETn,

    // APB Slave 0 Interface (SPI)
    output logic [31:0] s0_paddr,
    output logic        s0_psel,
    output logic        s0_penable,
    output logic        s0_pwrite,
    output logic [31:0] s0_pwdata,
    input  logic [31:0] s0_prdata,
    input  logic        s0_pready,
    input  logic        s0_pslverr,

    // APB Slave 1 Interface (PWM)
    output logic [31:0] s1_paddr,
    output logic        s1_psel,
    output logic        s1_penable,
    output logic        s1_pwrite,
    output logic [31:0] s1_pwdata,
    input  logic [31:0] s1_prdata,
    input  logic        s1_pready,
    input  logic        s1_pslverr,

    // APB Slave 2 Interface (Config SRAM)
    output logic [31:0] s2_paddr,
    output logic        s2_psel,
    output logic        s2_penable,
    output logic        s2_pwrite,
    output logic [31:0] s2_pwdata,
    input  logic [31:0] s2_prdata,
    input  logic        s2_pready,
    input  logic        s2_pslverr,

    // APB Slave 3 Interface (UART)
    output logic [31:0] s3_paddr,
    output logic        s3_psel,
    output logic        s3_penable,
    output logic        s3_pwrite,
    output logic [31:0] s3_pwdata,
    input  logic [31:0] s3_prdata,
    input  logic        s3_pready,
    input  logic        s3_pslverr
);

    localparam logic [3:0] LOCAL_DMEM_SEL = 4'h2;  // 0x2000_0000 region

    //-----------------------------------------------------------
    // Core <-> instruction memory
    //-----------------------------------------------------------
    logic [31:0] imem_addr, imem_rdata;

    imem #(
        .DEPTH_WORDS (IMEM_DEPTH_WORDS),
        .INIT_FILE   (IMEM_INIT_FILE)
    ) u_imem (
        .addr  (imem_addr),
        .rdata (imem_rdata)
    );

    //-----------------------------------------------------------
    // Core <-> data bus (local dmem + APB peripheral region)
    //-----------------------------------------------------------
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [3:0]  dmem_byte_en;
    logic        dmem_read, dmem_write;

    logic        is_dmem_local;
    logic        is_periph_addr;
    assign is_dmem_local  = (dmem_addr[31:28] == LOCAL_DMEM_SEL);
    assign is_periph_addr = !is_dmem_local;

    logic [31:0] dmem_local_rdata;
    logic        dmem_local_write_en;
    assign dmem_local_write_en = dmem_write && is_dmem_local;

    dmem #(
        .DEPTH_WORDS (DMEM_DEPTH_WORDS)
    ) u_dmem (
        .clk      (PCLK),
        .rst_n    (PRESETn),
        .addr     (dmem_addr),
        .wdata    (dmem_wdata),
        .byte_en  (dmem_byte_en),
        .write_en (dmem_local_write_en),
        .rdata    (dmem_local_rdata)
    );

    logic [31:0] periph_rdata;
    logic        periph_done;

    logic        PSEL, PENABLE, PWRITE;
    logic [31:0] PADDR, PWDATA, PRDATA;
    logic        PREADY, PSLVERR;

    cpu_apb_bridge u_cpu_apb_bridge (
        .PCLK           (PCLK),
        .PRESETn        (PRESETn),
        .is_periph_addr (is_periph_addr),
        .dmem_read      (dmem_read),
        .dmem_write     (dmem_write),
        .dmem_addr      (dmem_addr),
        .dmem_wdata     (dmem_wdata),
        .periph_rdata   (periph_rdata),
        .periph_done    (periph_done),
        .PSEL           (PSEL),
        .PENABLE        (PENABLE),
        .PWRITE         (PWRITE),
        .PADDR          (PADDR),
        .PWDATA         (PWDATA),
        .PRDATA         (PRDATA),
        .PREADY         (PREADY),
        .PSLVERR        (PSLVERR)
    );

    assign dmem_rdata = is_dmem_local ? dmem_local_rdata : periph_rdata;

    //-----------------------------------------------------------
    // APB interconnect
    //-----------------------------------------------------------
    apb_interconnect #(
        .SPI_BASE_ADDR  (32'h1000_0000),
        .PWM_BASE_ADDR  (32'h1001_0000),
        .SRAM_BASE_ADDR (32'h1002_0000),
        .UART_BASE_ADDR (32'h1003_0000),
        .ADDR_MASK      (32'hFFFF_0000)
    ) u_apb_interconnect (
        .m_paddr   (PADDR),
        .m_psel    (PSEL),
        .m_penable (PENABLE),
        .m_pwrite  (PWRITE),
        .m_pwdata  (PWDATA),
        .m_prdata  (PRDATA),
        .m_pready  (PREADY),
        .m_pslverr (PSLVERR),

        .s0_paddr (s0_paddr), .s0_psel (s0_psel), .s0_penable (s0_penable),
        .s0_pwrite(s0_pwrite), .s0_pwdata(s0_pwdata), .s0_prdata(s0_prdata),
        .s0_pready(s0_pready), .s0_pslverr(s0_pslverr),

        .s1_paddr (s1_paddr), .s1_psel (s1_psel), .s1_penable (s1_penable),
        .s1_pwrite(s1_pwrite), .s1_pwdata(s1_pwdata), .s1_prdata(s1_prdata),
        .s1_pready(s1_pready), .s1_pslverr(s1_pslverr),

        .s2_paddr (s2_paddr), .s2_psel (s2_psel), .s2_penable (s2_penable),
        .s2_pwrite(s2_pwrite), .s2_pwdata(s2_pwdata), .s2_prdata(s2_prdata),
        .s2_pready(s2_pready), .s2_pslverr(s2_pslverr),

        .s3_paddr (s3_paddr), .s3_psel (s3_psel), .s3_penable (s3_penable),
        .s3_pwrite(s3_pwrite), .s3_pwdata(s3_pwdata), .s3_prdata(s3_prdata),
        .s3_pready(s3_pready), .s3_pslverr(s3_pslverr)
    );

    //-----------------------------------------------------------
    // RV32I core
    //-----------------------------------------------------------
    rv32i_core u_rv32i_core (
        .clk             (PCLK),
        .rst_n           (PRESETn),
        .imem_addr       (imem_addr),
        .imem_rdata      (imem_rdata),
        .dmem_addr       (dmem_addr),
        .dmem_wdata      (dmem_wdata),
        .dmem_byte_en    (dmem_byte_en),
        .dmem_read       (dmem_read),
        .dmem_write      (dmem_write),
        .dmem_rdata      (dmem_rdata),
        .is_periph_addr  (is_periph_addr),
        .periph_done     (periph_done)
    );

endmodule