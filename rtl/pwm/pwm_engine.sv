`timescale 1ns/1ps

module pwm_engine (
    input  logic       PCLK,
    input  logic       PRESETn,

    input  logic        enable,
    input  logic        clear_fail_safe,   // single-cycle pulse from APB wrapper
    input  logic [7:0]  duty,              // 0-255
    input  logic [7:0]  period,            // PWM counter wrap value
    input  logic [7:0]  window,            // measurement window length (PCLK cycles)

    input  logic        tach_pulse,        // raw pulse from fan model

    output logic        pwm_out,
    output logic [7:0]  rpm_count,         // latched tach pulses from last completed window
    output logic        stall_detected,
    output logic        fail_safe_active
);

    // ---------------------------------------------------------------
    // PWM waveform generation
    // ---------------------------------------------------------------
    logic [7:0] pwm_counter;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            pwm_counter <= 8'd0;
        end else if (!enable || period == 8'd0) begin
            pwm_counter <= 8'd0;
        end else if (pwm_counter >= period - 8'd1) begin
            pwm_counter <= 8'd0;
        end else begin
            pwm_counter <= pwm_counter + 8'd1;
        end
    end

    assign pwm_out = enable && !fail_safe_active && (pwm_counter < duty);

    // ---------------------------------------------------------------
    // tach pulse edge detection
    // ---------------------------------------------------------------
    logic tach_prev;
    logic tach_rising;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) tach_prev <= 1'b0;
        else          tach_prev <= tach_pulse;
    end

    assign tach_rising = tach_pulse && !tach_prev;

    // ---------------------------------------------------------------
    // measurement window + RPM latch + stall/fail-safe logic
    // ---------------------------------------------------------------
    logic [7:0] tach_count;
    logic [7:0] window_counter;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            tach_count       <= 8'd0;
            window_counter   <= 8'd0;
            rpm_count        <= 8'd0;
            stall_detected   <= 1'b0;
            fail_safe_active <= 1'b0;
        end else begin

            // clear_fail_safe has priority - CPU explicitly acknowledging/reset
            if (clear_fail_safe) begin
                fail_safe_active <= 1'b0;
                stall_detected   <= 1'b0;
            end

            if (!enable) begin
                // reset measurement state while disabled
                tach_count     <= 8'd0;
                window_counter <= 8'd0;
            end else begin
                // accumulate tach pulses
                if (tach_rising) begin
                    tach_count <= tach_count + 8'd1;
                end

                // window timer
                if (window == 8'd0) begin
                    // window disabled -> no RPM measurement
                    window_counter <= 8'd0;
                end else if (window_counter >= window - 8'd1) begin
                    window_counter <= 8'd0;

                    // snapshot this window's pulse count
                    rpm_count <= tach_count + (tach_rising ? 8'd1 : 8'd0);
                    tach_count <= 8'd0;

                    // stall = fan should be spinning (duty>0) but zero pulses seen
                    if (duty != 8'd0 && (tach_count + (tach_rising ? 8'd1 : 8'd0)) == 8'd0) begin
                        stall_detected   <= 1'b1;
                        fail_safe_active <= 1'b1;
                    end else if (!clear_fail_safe) begin
                        stall_detected <= 1'b0;
                    end
                end else begin
                    window_counter <= window_counter + 8'd1;
                end
            end
        end
    end

endmodule
