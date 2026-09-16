`timescale 1ns/1ps

module pwm_soc_top (
    input  logic       PCLK,
    input  logic       PRESETn,
    input  logic       PSEL,
    input  logic       PENABLE,
    input  logic       PWRITE,
    input  logic [7:0] PADDR,
    input  logic [7:0] PWDATA,
    output logic [7:0] PRDATA,
    output logic       PREADY,
    output logic       PSLVERR,

    // physical fan interface
    output logic       pwm_out,
    input  logic       tach_pulse
);

    logic       engine_enable;
    logic       clear_fail_safe;
    logic [7:0] duty_reg;
    logic [7:0] period_reg;
    logic [7:0] window_reg;

    logic       stall_detected;
    logic       fail_safe_active;
    logic [7:0] rpm_count;

    apb_slave_fsm_pwm u_apb_slave_fsm_pwm (
        .PCLK                 (PCLK),
        .PRESETn              (PRESETn),
        .PSEL                 (PSEL),
        .PENABLE              (PENABLE),
        .PWRITE               (PWRITE),
        .PADDR                (PADDR),
        .PWDATA               (PWDATA),
        .PRDATA               (PRDATA),
        .PREADY               (PREADY),
        .PSLVERR              (PSLVERR),

        .engine_enable        (engine_enable),
        .clear_fail_safe      (clear_fail_safe),
        .duty_reg             (duty_reg),
        .period_reg           (period_reg),
        .window_reg           (window_reg),

        .pwm_stall_detected   (stall_detected),
        .pwm_fail_safe_active (fail_safe_active),
        .pwm_rpm_count        (rpm_count)
    );

    pwm_engine u_pwm_engine (
        .PCLK             (PCLK),
        .PRESETn          (PRESETn),
        .enable           (engine_enable),
        .clear_fail_safe  (clear_fail_safe),
        .duty             (duty_reg),
        .period           (period_reg),
        .window           (window_reg),
        .tach_pulse       (tach_pulse),
        .pwm_out          (pwm_out),
        .rpm_count        (rpm_count),
        .stall_detected   (stall_detected),
        .fail_safe_active (fail_safe_active)
    );

endmodule
