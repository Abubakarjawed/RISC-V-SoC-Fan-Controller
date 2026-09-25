`timescale 1ns/1ps
// ---------------------------------------------------------------------
// pwm_assertions : `bind` ke zariye pwm_soc_top ke andar inject hoti hai,
// isliye internal wires (engine_enable, fail_safe_active, stall_detected,
// duty_reg) seedhe naam se milte hain -- hierarchical path likhne ki
// zaroorat nahi. Yeh un boundary/error conditions ko cover karti hai jo
// scoreboard (edge-based measurement) asaani se nahi pakarta, jaise
// duty=0 ya fail-safe ke doran output force-low.
// ---------------------------------------------------------------------
module pwm_assertions (
    input logic       PCLK,
    input logic       PRESETn,
    input logic       pwm_out,
    input logic        engine_enable,
    input logic        fail_safe_active,
    input logic        stall_detected,
    input logic [7:0]  duty_reg
);

    // Fail-safe active hote hi pwm_out zaroor low hona chahiye
    property p_failsafe_forces_low;
        @(posedge PCLK) disable iff (!PRESETn)
        fail_safe_active |-> !pwm_out;
    endproperty
    a_failsafe_forces_low: assert property (p_failsafe_forces_low)
        else $error("[PWM_ASSERT] fail_safe_active=1 lekin pwm_out high hai");

    // stall_detected hamesha fail_safe_active ke sath (ya baad tak) hota hai
    property p_stall_implies_failsafe;
        @(posedge PCLK) disable iff (!PRESETn)
        stall_detected |-> fail_safe_active;
    endproperty
    a_stall_implies_failsafe: assert property (p_stall_implies_failsafe)
        else $error("[PWM_ASSERT] stall_detected=1 lekin fail_safe_active=0");

    // Engine disable hone par output zaroor low
    property p_disabled_output_low;
        @(posedge PCLK) disable iff (!PRESETn)
        !engine_enable |-> !pwm_out;
    endproperty
    a_disabled_output_low: assert property (p_disabled_output_low)
        else $error("[PWM_ASSERT] engine disabled lekin pwm_out high hai");

    // duty=0 par output kabhi high nahi hona chahiye (jab tak enabled hai)
    property p_zero_duty_output_low;
        @(posedge PCLK) disable iff (!PRESETn)
        (engine_enable && duty_reg == 8'd0) |-> !pwm_out;
    endproperty
    a_zero_duty_output_low: assert property (p_zero_duty_output_low)
        else $error("[PWM_ASSERT] duty=0 hone ke bawajood pwm_out high hai");

endmodule

bind pwm_soc_top pwm_assertions u_pwm_assertions (
    .PCLK             (PCLK),
    .PRESETn          (PRESETn),
    .pwm_out          (pwm_out),
    .engine_enable    (engine_enable),
    .fail_safe_active (fail_safe_active),
    .stall_detected   (stall_detected),
    .duty_reg         (duty_reg)
);
