`timescale 1ns/1ps

module soc_top #(
    parameter string IMEM_INIT_FILE   = "",
    parameter int    IMEM_DEPTH_WORDS = 1024,
    parameter int    DMEM_DEPTH_WORDS = 1024
) (
    input  logic PCLK,
    input  logic PRESETn,

    // SPI Physical Pins
    output logic SCLK,
    output logic MOSI,
    input  logic MISO,
    output logic SS_N,

    // PWM Fan Physical Pins
    output logic pwm_out,
    input  logic tach_pulse,

    // UART Physical Pins
    input  logic uart_rx,
    output logic uart_tx
);

    // Internal Signals //

    // Instruction Memory Bus
    logic [31:0] imem_addr;
    logic [31:0] imem_rdata;

    // CPU Data Bus
    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic [31:0] dmem_rdata;
    logic        dmem_read;
    logic        dmem_write;
    logic [3:0]  dmem_byte_enable;

    // Address Decoding Signals
    logic is_dmem_sram;
    logic is_periph_addr;

    // Subsystem Read Data
    logic [31:0] sram_rdata;
    logic [31:0] periph_rdata;
    logic        periph_done;

    // APB Master Signals (Bridge <-> Interconnect)
    logic [31:0] m_paddr;
    logic        m_psel;
    logic        m_penable;
    logic        m_pwrite;
    logic [31:0] m_pwdata;
    logic [31:0] m_prdata;
    logic        m_pready;
    logic        m_pslverr;

    // APB Slave 0 Signals (SPI Subsystem)
    logic [31:0] s0_paddr;
    logic        s0_psel;
    logic        s0_penable;
    logic        s0_pwrite;
    logic [31:0] s0_pwdata;
    logic [31:0] s0_prdata;
    logic        s0_pready;
    logic        s0_pslverr;

    // APB Slave 1 Signals (PWM Subsystem)
    logic [31:0] s1_paddr;
    logic        s1_psel;
    logic        s1_penable;
    logic        s1_pwrite;
    logic [31:0] s1_pwdata;
    logic [31:0] s1_prdata;
    logic        s1_pready;
    logic        s1_pslverr;

    // APB Slave 2 Signals (Config SRAM)
    logic [31:0] s2_paddr;
    logic        s2_psel;
    logic        s2_penable;
    logic        s2_pwrite;
    logic [31:0] s2_pwdata;
    logic [31:0] s2_prdata;
    logic        s2_pready;
    logic        s2_pslverr;

    // APB Slave 3 Signals (UART Wrapper)
    logic [31:0] s3_paddr;
    logic        s3_psel;
    logic        s3_penable;
    logic        s3_pwrite;
    logic [31:0] s3_pwdata;
    logic [31:0] s3_prdata;
    logic        s3_pready;
    logic        s3_pslverr;

    // Intermediate 8-bit read buses for SPI & PWM zero-extension
    logic [7:0]  spi_prdata_8bit;
    logic [7:0]  pwm_prdata_8bit;

    // Step A: Address Decoding & Data Muxing // 
    
    // 0x0000_0000 - 0x0FFF_FFFF: Internal Data SRAM
    // 0x1000_0000 - 0x1003_FFFF: APB Peripherals
    assign is_dmem_sram   = (dmem_addr[31:28] == 4'h0);
    assign is_periph_addr = (dmem_addr[31:28] == 4'h1);

    assign dmem_rdata     = is_dmem_sram ? sram_rdata : periph_rdata;
    
    // Submodules Instantiation //

    // Instruction Memory
    imem #(
        .INIT_FILE   (IMEM_INIT_FILE),
        .DEPTH_WORDS (IMEM_DEPTH_WORDS)
    ) imem_inst (
        .addr  (imem_addr),
        .rdata (imem_rdata)
    );

    // RV32I Core
    rv32i_core rv32i_core_inst (
        .clk            (PCLK),
        .rst_n          (PRESETn),
        .imem_addr      (imem_addr),
        .imem_rdata     (imem_rdata),
        .dmem_addr      (dmem_addr),
        .dmem_wdata     (dmem_wdata),
        .dmem_rdata     (dmem_rdata),
        .dmem_read      (dmem_read),
        .dmem_write     (dmem_write),
        .dmem_byte_en   (dmem_byte_enable),
        .is_periph_addr (is_periph_addr),
        .periph_done    (periph_done)
    );

    // Data SRAM
    dmem #(
        .DEPTH_WORDS (DMEM_DEPTH_WORDS)
    ) dmem_inst (
        .clk      (PCLK),
        .rst_n    (PRESETn),
        .addr     (dmem_addr),
        .wdata    (dmem_wdata),
        .byte_en  (dmem_byte_enable),
        .write_en (dmem_write & is_dmem_sram),
        .rdata    (sram_rdata)
    );

    // Step B: CPU to APB Master Bridge
        cpu_apb_bridge cpu_apb_bridge_inst (
        .PCLK           (PCLK),
        .PRESETn        (PRESETn),
        .is_periph_addr (is_periph_addr),
        .dmem_read      (dmem_read),
        .dmem_write     (dmem_write),
        .dmem_addr      (dmem_addr),
        .dmem_wdata     (dmem_wdata),
        .periph_rdata   (periph_rdata),
        .periph_done    (periph_done),
        .PSEL           (m_psel),
        .PENABLE        (m_penable),
        .PWRITE         (m_pwrite),
        .PADDR          (m_paddr[7:0]),
        .PWDATA         (m_pwdata[7:0]),
        .PRDATA         (m_prdata[7:0]),
        .PREADY         (m_pready),
        .PSLVERR        (m_pslverr)
    );

    // Step C: 4-Way APB Interconnect
    apb_interconnect apb_interconnect_inst (
        // Master Interface
        .m_paddr    (m_paddr),
        .m_psel     (m_psel),
        .m_penable  (m_penable),
        .m_pwrite   (m_pwrite),
        .m_pwdata   (m_pwdata),
        .m_prdata   (m_prdata),
        .m_pready   (m_pready),
        .m_pslverr  (m_pslverr),

        // Slave 0: SPI (0x1000_0000)
        .s0_paddr   (s0_paddr),
        .s0_psel    (s0_psel),
        .s0_penable (s0_penable),
        .s0_pwrite  (s0_pwrite),
        .s0_pwdata  (s0_pwdata),
        .s0_prdata  (s0_prdata),
        .s0_pready  (s0_pready),
        .s0_pslverr (s0_pslverr),

        // Slave 1: PWM (0x1001_0000)
        .s1_paddr   (s1_paddr),
        .s1_psel    (s1_psel),
        .s1_penable (s1_penable),
        .s1_pwrite  (s1_pwrite),
        .s1_pwdata  (s1_pwdata),
        .s1_prdata  (s1_prdata),
        .s1_pready  (s1_pready),
        .s1_pslverr (s1_pslverr),

        // Slave 2: Config SRAM (0x1002_0000)
        .s2_paddr   (s2_paddr),
        .s2_psel    (s2_psel),
        .s2_penable (s2_penable),
        .s2_pwrite  (s2_pwrite),
        .s2_pwdata  (s2_pwdata),
        .s2_prdata  (s2_prdata),
        .s2_pready  (s2_pready),
        .s2_pslverr (s2_pslverr),

        // Slave 3: UART (0x1003_0000)
        .s3_paddr   (s3_paddr),
        .s3_psel    (s3_psel),
        .s3_penable (s3_penable),
        .s3_pwrite  (s3_pwrite),
        .s3_pwdata  (s3_pwdata),
        .s3_prdata  (s3_prdata),
        .s3_pready  (s3_pready),
        .s3_pslverr (s3_pslverr)
    );

    // Step D: Instantiate Peripherals & Route Pins //

    // Slave 0: SPI Subsystem
    spi_soc_top spi_soc_top_inst (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),
        .PADDR   (s0_paddr),
        .PSEL    (s0_psel),
        .PENABLE (s0_penable),
        .PWRITE  (s0_pwrite),
        .PWDATA  (s0_pwdata),
        .PRDATA  (s0_prdata),
        .PREADY  (s0_pready),
        .PSLVERR (s0_pslverr),
        .SCLK    (SCLK),
        .MOSI    (MOSI),
        .MISO    (MISO),
        .SS_N    (SS_N)
    );

    // Slave 1: PWM Subsystem
    pwm_soc_top pwm_soc_top_inst (
        .PCLK       (PCLK),
        .PRESETn    (PRESETn),
        .PADDR      (s1_paddr),
        .PSEL       (s1_psel),
        .PENABLE    (s1_penable),
        .PWRITE     (s1_pwrite),
        .PWDATA     (s1_pwdata),
        .PRDATA     (s1_prdata),
        .PREADY     (s1_pready),
        .PSLVERR    (s1_pslverr),
        .pwm_out    (pwm_out),
        .tach_pulse (tach_pulse)
    );

    // Slave 2: Config SRAM Subsystem
    sram_soc_top sram_soc_top_inst (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),
        .PADDR   (s2_paddr),
        .PSEL    (s2_psel),
        .PENABLE (s2_penable),
        .PWRITE  (s2_pwrite),
        .PWDATA  (s2_pwdata),
        .PRDATA  (s2_prdata),
        .PREADY  (s2_pready),
        .PSLVERR (s2_pslverr)
    );

    // Slave 3: UART Subsystem
        uart_apb uart_apb_inst (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),
        .PADDR   (s3_paddr),
        .PSEL    (s3_psel),
        .PENABLE (s3_penable),
        .PWRITE  (s3_pwrite),
        .PWDATA  (s3_pwdata),
        .PRDATA  (s3_prdata),
        .PREADY  (s3_pready),
        .PSLVERR (s3_pslverr),
        .uart_rx (uart_rx),
        .uart_tx (uart_tx)
    );

endmodule
