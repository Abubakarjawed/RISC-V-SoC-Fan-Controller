`timescale 1ns/1ps
//=============================================================
// riscv_soc_top.sv   (renamed from riscv_spi_soc_top.sv)
//
// Top-level SoC: RV32I core + instruction memory + local data
// memory + APB bridge -> apb_interconnect -> SPI / PWM /
// Configuration-SRAM peripherals (UART slot reserved, stubbed
// until Person 3's uart_apb is ready).
//
// ================= INTEGRATION UPDATE =====================
// This file previously drove a single 8-bit APB peripheral
// (apb_slave_fsm + spi_engine) directly, with the core's own
// local data memory ("dmem") at 0x1000_0000. That address
// clashed with the team's shared peripheral map (Person 3's
// apb_interconnect puts SPI/PWM/SRAM/UART starting at exactly
// 0x1000_0000), so two things changed here:
//
//   1) cpu_apb_bridge's PADDR/PWDATA/PRDATA widened 8 -> 32 bit
//      to match apb_interconnect's master port (see
//      cpu_apb_bridge.sv for that change).
//   2) The core's local data memory moved from 0x1000_0000 to
//      0x2000_0000 so it no longer overlaps the peripheral
//      window. dmem.sv itself needed no change -- it only ever
//      looked at low address bits.
//
// *** Any existing assembly/hex program (e.g. sw/spi_test.hex)
// *** that hardcodes 0x1000_0000 for local variables or
// *** 0x2000_0000 for SPI registers was built against the OLD
// *** map and MUST be re-assembled with the addresses below
// *** before its directed test will pass again. This file only
// *** has the RTL side of that program, not its source, so
// *** that update has to happen separately.
//
// New address map (as seen by the core's data bus):
//   0x1000_0000 - 0x1000_FFFF : SPI controller   (APB)
//   0x1001_0000 - 0x1001_FFFF : PWM controller   (APB)
//   0x1002_0000 - 0x1002_FFFF : Configuration SRAM (APB, 256B used)
//   0x1003_0000 - 0x1003_FFFF : UART             (APB, not wired yet)
//   0x2000_0000 - 0x2000_0FFF : core-local data memory (dmem, 4KB)
// Instructions are fetched from a separate instruction memory
// (0x0000_0000 base) on its own combinational read port.
//
// Register maps for SPI/PWM/Config-SRAM (offset within each
// peripheral's 64KB window, i.e. PADDR[7:0]):
//   SPI : CTRL=0x00 STATUS=0x04 TX_DATA=0x08 RX_DATA=0x0C CLKDIV=0x10
//   PWM : CTRL=0x00 STATUS=0x04 DUTY=0x08 PERIOD=0x0C RPM=0x10 WINDOW=0x14
//   SRAM: byte address 0x00-0xFF directly (no control/status regs)
//=============================================================
module riscv_soc_top #(
    parameter IMEM_INIT_FILE = "",
    parameter int IMEM_DEPTH_WORDS = 1024,
    parameter int DMEM_DEPTH_WORDS = 1024
) (
    input  logic PCLK,
    input  logic PRESETn,

    // SPI pins
    output logic SCLK,
    output logic MOSI,
    input  logic MISO,
    output logic SS_N,

    // PWM pins
    output logic pwm_out,
    input  logic tach_pulse

    // UART pins: add here once Person 3's uart_apb is integrated
    // (e.g. output logic uart_tx, input logic uart_rx)
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
    assign is_dmem_local   = (dmem_addr[31:28] == LOCAL_DMEM_SEL);
    assign is_periph_addr  = !is_dmem_local;

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
    // APB interconnect (Person 3) -> SPI / PWM / Config-SRAM
    // (UART slot stubbed until uart_apb is ready)
    //-----------------------------------------------------------
    logic        s0_psel, s0_penable, s0_pwrite, s0_pready, s0_pslverr;
    logic [31:0] s0_paddr, s0_pwdata, s0_prdata;

    logic        s1_psel, s1_penable, s1_pwrite, s1_pready, s1_pslverr;
    logic [31:0] s1_paddr, s1_pwdata, s1_prdata;

    logic        s2_psel, s2_penable, s2_pwrite, s2_pready, s2_pslverr;
    logic [31:0] s2_paddr, s2_pwdata, s2_prdata;

    logic        s3_psel, s3_penable, s3_pwrite, s3_pready, s3_pslverr;
    logic [31:0] s3_paddr, s3_pwdata, s3_prdata;

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

    // Slave 0 : SPI (spi_soc_top already bundles apb_slave_fsm + spi_engine)
    spi_soc_top u_spi_soc_top (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),
        .PSEL    (s0_psel),
        .PENABLE (s0_penable),
        .PWRITE  (s0_pwrite),
        .PADDR   (s0_paddr),
        .PWDATA  (s0_pwdata),
        .PRDATA  (s0_prdata),
        .PREADY  (s0_pready),
        .PSLVERR (s0_pslverr),
        .SCLK    (SCLK),
        .MOSI    (MOSI),
        .MISO    (MISO),
        .SS_N    (SS_N)
    );

    // Slave 1 : PWM (pwm_soc_top bundles apb_slave_fsm_pwm + pwm_engine)
    pwm_soc_top u_pwm_soc_top (
        .PCLK       (PCLK),
        .PRESETn    (PRESETn),
        .PSEL       (s1_psel),
        .PENABLE    (s1_penable),
        .PWRITE     (s1_pwrite),
        .PADDR      (s1_paddr),
        .PWDATA     (s1_pwdata),
        .PRDATA     (s1_prdata),
        .PREADY     (s1_pready),
        .PSLVERR    (s1_pslverr),
        .pwm_out    (pwm_out),
        .tach_pulse (tach_pulse)
    );

    // Slave 2 : Configuration SRAM (sram_soc_top bundles apb_slave_fsm_sram + sram_engine)
    sram_soc_top u_sram_soc_top (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),
        .PSEL    (s2_psel),
        .PENABLE (s2_penable),
        .PWRITE  (s2_pwrite),
        .PADDR   (s2_paddr),
        .PWDATA  (s2_pwdata),
        .PRDATA  (s2_prdata),
        .PREADY  (s2_pready),
        .PSLVERR (s2_pslverr)
    );

    // Slave 3 : UART -- stub until Person 3's uart_apb is ready.
    // Always-ready, always-zero, never-error so the CPU never hangs
    // if a program accidentally touches this window early.
    assign s3_prdata  = 32'h0000_0000;
    assign s3_pready  = 1'b1;
    assign s3_pslverr = 1'b0;
    // TODO(integration): replace the three lines above with
    //   uart_apb u_uart_apb (.PCLK(PCLK), .PRESETn(PRESETn),
    //       .PSEL(s3_psel), .PENABLE(s3_penable), .PWRITE(s3_pwrite),
    //       .PADDR(s3_paddr), .PWDATA(s3_pwdata), .PRDATA(s3_prdata),
    //       .PREADY(s3_pready), .PSLVERR(s3_pslverr), ...uart pins...);
    // and add uart_tx/uart_rx (or equivalent) to this module's port list.

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
