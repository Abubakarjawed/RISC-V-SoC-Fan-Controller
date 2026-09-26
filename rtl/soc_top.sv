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

    // APB Slave Interconnect Signals
    logic [31:0] s0_paddr, s0_pwdata, s0_prdata;
    logic        s0_psel, s0_penable, s0_pwrite, s0_pready, s0_pslverr;

    logic [31:0] s1_paddr, s1_pwdata, s1_prdata;
    logic        s1_psel, s1_penable, s1_pwrite, s1_pready, s1_pslverr;

    logic [31:0] s2_paddr, s2_pwdata, s2_prdata;
    logic        s2_psel, s2_penable, s2_pwrite, s2_pready, s2_pslverr;

    logic [31:0] s3_paddr, s3_pwdata, s3_prdata;
    logic        s3_psel, s3_penable, s3_pwrite, s3_pready, s3_pslverr;

    //-----------------------------------------------------------
    // RISC-V SoC Subsystem (Core + Memories + APB Bus)
    //-----------------------------------------------------------
    riscv_soc_top #(
        .IMEM_INIT_FILE   (IMEM_INIT_FILE),
        .IMEM_DEPTH_WORDS (IMEM_DEPTH_WORDS),
        .DMEM_DEPTH_WORDS (DMEM_DEPTH_WORDS)
    ) riscv_soc_top_inst (
        .PCLK       (PCLK),
        .PRESETn    (PRESETn),

        // Slave 0 Routing (SPI)
        .s0_paddr   (s0_paddr),
        .s0_psel    (s0_psel),
        .s0_penable (s0_penable),
        .s0_pwrite  (s0_pwrite),
        .s0_pwdata  (s0_pwdata),
        .s0_prdata  (s0_prdata),
        .s0_pready  (s0_pready),
        .s0_pslverr (s0_pslverr),

        // Slave 1 Routing (PWM)
        .s1_paddr   (s1_paddr),
        .s1_psel    (s1_psel),
        .s1_penable (s1_penable),
        .s1_pwrite  (s1_pwrite),
        .s1_pwdata  (s1_pwdata),
        .s1_prdata  (s1_prdata),
        .s1_pready  (s1_pready),
        .s1_pslverr (s1_pslverr),

        // Slave 2 Routing (SRAM)
        .s2_paddr   (s2_paddr),
        .s2_psel    (s2_psel),
        .s2_penable (s2_penable),
        .s2_pwrite  (s2_pwrite),
        .s2_pwdata  (s2_pwdata),
        .s2_prdata  (s2_prdata),
        .s2_pready  (s2_pready),
        .s2_pslverr (s2_pslverr),

        // Slave 3 Routing (UART)
        .s3_paddr   (s3_paddr),
        .s3_psel    (s3_psel),
        .s3_penable (s3_penable),
        .s3_pwrite  (s3_pwrite),
        .s3_pwdata  (s3_pwdata),
        .s3_prdata  (s3_prdata),
        .s3_pready  (s3_pready),
        .s3_pslverr (s3_pslverr)
    );

    //-----------------------------------------------------------
    // Peripheral Sub-Top Modules Instantiation
    //-----------------------------------------------------------

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
    uart_soc_top uart_soc_top_inst (
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