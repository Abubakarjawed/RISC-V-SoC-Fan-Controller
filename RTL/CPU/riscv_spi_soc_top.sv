`timescale 1ns/1ps
//=============================================================
// riscv_spi_soc_top.sv
// Top-level SoC: RV32I core + instruction/data SRAM + APB
// bridge, driving the existing apb_slave_fsm/spi_engine SPI
// subsystem as a memory-mapped peripheral.
//
// Address map (as seen by the core's data bus):
//   0x1000_0000 - 0x1000_0FFF : data / configuration SRAM (4KB)
//   0x2000_0000 - 0x2000_00FF : SPI controller registers (APB)
//                               (CTRL=0x00 STATUS=0x04 TX=0x08
//                                RX=0x0C CLKDIV=0x10 - byte regs,
//                                access with LB/SB)
// Instructions are fetched from a separate instruction SRAM
// (0x0000_0000 base) on its own combinational read port.
//=============================================================
module riscv_spi_soc_top #(
    parameter IMEM_INIT_FILE = "",
    parameter int IMEM_DEPTH_WORDS = 1024,
    parameter int DMEM_DEPTH_WORDS = 1024
) (
    input  logic PCLK,
    input  logic PRESETn,

    output logic SCLK,
    output logic MOSI,
    input  logic MISO,
    output logic SS_N
);

    localparam logic [3:0] SRAM_SEL = 4'h1;

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
    // Core <-> data bus (SRAM + peripheral region)
    //-----------------------------------------------------------
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [3:0]  dmem_byte_en;
    logic        dmem_read, dmem_write;

    logic        is_dmem_sram;
    logic        is_periph_addr;
    assign is_dmem_sram    = (dmem_addr[31:28] == SRAM_SEL);
    assign is_periph_addr  = !is_dmem_sram;

    logic [31:0] sram_rdata;
    logic        sram_write_en;
    assign sram_write_en = dmem_write && is_dmem_sram;

    dmem #(
        .DEPTH_WORDS (DMEM_DEPTH_WORDS)
    ) u_dmem (
        .clk      (PCLK),
        .rst_n    (PRESETn),
        .addr     (dmem_addr),
        .wdata    (dmem_wdata),
        .byte_en  (dmem_byte_en),
        .write_en (sram_write_en),
        .rdata    (sram_rdata)
    );

    logic [31:0] periph_rdata;
    logic        periph_done;

    logic       PSEL, PENABLE, PWRITE;
    logic [7:0] PADDR, PWDATA, PRDATA;
    logic       PREADY, PSLVERR;

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

    assign dmem_rdata = is_dmem_sram ? sram_rdata : periph_rdata;

    //-----------------------------------------------------------
    // Existing APB slave + SPI engine subsystem (unmodified)
    //-----------------------------------------------------------
    logic       tx_fifo_rd_en;
    logic [7:0] tx_fifo_rd_data;
    logic       tx_fifo_empty;
    logic       rx_fifo_wr_en;
    logic [7:0] rx_fifo_wr_data;
    logic       rx_fifo_full;
    logic       engine_enable;
    logic       sclk_tick;

    apb_slave_fsm u_apb_slave_fsm (
        .PCLK             (PCLK),
        .PRESETn          (PRESETn),
        .PSEL             (PSEL),
        .PENABLE          (PENABLE),
        .PWRITE           (PWRITE),
        .PADDR            (PADDR),
        .PWDATA           (PWDATA),
        .PRDATA           (PRDATA),
        .PREADY           (PREADY),
        .PSLVERR          (PSLVERR),

        .tx_fifo_rd_en    (tx_fifo_rd_en),
        .tx_fifo_rd_data  (tx_fifo_rd_data),
        .tx_fifo_empty    (tx_fifo_empty),

        .rx_fifo_wr_en    (rx_fifo_wr_en),
        .rx_fifo_wr_data  (rx_fifo_wr_data),
        .rx_fifo_full     (rx_fifo_full),

        .engine_enable    (engine_enable),
        .sclk_tick        (sclk_tick)
    );

    spi_engine u_spi_engine (
        .PCLK             (PCLK),
        .PRESETn          (PRESETn),
        .sclk_tick        (sclk_tick),
        .enable           (engine_enable),

        .tx_fifo_empty    (tx_fifo_empty),
        .tx_fifo_rd_en    (tx_fifo_rd_en),
        .tx_fifo_rd_data  (tx_fifo_rd_data),

        .rx_fifo_full     (rx_fifo_full),
        .rx_fifo_wr_en    (rx_fifo_wr_en),
        .rx_fifo_wr_data  (rx_fifo_wr_data),

        .SCLK             (SCLK),
        .MOSI             (MOSI),
        .MISO             (MISO),
        .SS_N             (SS_N)
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
