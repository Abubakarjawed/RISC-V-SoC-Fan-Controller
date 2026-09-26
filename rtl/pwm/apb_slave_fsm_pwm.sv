`timescale 1ns/1ps

module apb_slave_fsm_pwm (
    input  logic       PCLK,
    input  logic       PRESETn,
    input  logic       PSEL,
    input  logic       PENABLE,
    input  logic       PWRITE,
    input  logic [31:0] PADDR,
    input  logic [31:0] PWDATA,

    output logic [31:0] PRDATA,
    output logic       PREADY,
    output logic       PSLVERR,

    // ---- PWM-engine side ----
    output logic        engine_enable,
    output logic        clear_fail_safe,   // single-cycle pulse
    output logic [7:0]  duty_reg,
    output logic [7:0]  period_reg,
    output logic [7:0]  window_reg,

    input  logic        pwm_stall_detected,
    input  logic        pwm_fail_safe_active,
    input  logic [7:0]  pwm_rpm_count
);
    localparam logic [7:0] CTRL_REG   = 8'h00;
    localparam logic [7:0] STATUS_REG = 8'h04;
    localparam logic [7:0] DUTY_REG   = 8'h08;
    localparam logic [7:0] PERIOD_REG = 8'h0C;
    localparam logic [7:0] RPM_REG    = 8'h10;
    localparam logic [7:0] WINDOW_REG = 8'h14;

    typedef enum logic [1:0] {
        IDLE   = 2'b00,
        SETUP  = 2'b01,
        ACCESS = 2'b10
    } apb_state_t;

    apb_state_t current_state, next_state;

    logic apb_write;
    logic apb_read;
    logic apb_done;

    assign apb_done  = (current_state == ACCESS) && PSEL && PENABLE && PREADY;
    assign apb_write = apb_done && PWRITE;
    assign apb_read  = apb_done && !PWRITE;

    assign PSLVERR = 1'b0;

    // ---------------------------------------------------------------
    // APB FSM - no wait states needed (plain register file, no FIFO)
    // ---------------------------------------------------------------
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) current_state <= IDLE;
        else          current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;
        PREADY = 1'b0;

        case (current_state)
            IDLE: begin
                if (PSEL) next_state = SETUP;
            end

            SETUP: begin
                next_state = ACCESS;
            end

            ACCESS: begin
                if (!PSEL) begin
                    next_state = IDLE;
                end else if (!PENABLE) begin
                    PREADY = 1'b0;
                    next_state = ACCESS;
                end else begin
                    PREADY = 1'b1;
                    next_state = IDLE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

    // ---------------------------------------------------------------
    // register file
    // ---------------------------------------------------------------
    logic [7:0] ctrl_reg_value;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            ctrl_reg_value <= 8'd0;
            duty_reg       <= 8'd0;
            period_reg     <= 8'd0;
            window_reg     <= 8'd0;
        end else if (apb_write) begin
            case (PADDR[7:0])
                CTRL_REG:   ctrl_reg_value <= PWDATA[7:0];
                DUTY_REG:   duty_reg       <= PWDATA[7:0];
                PERIOD_REG: period_reg     <= PWDATA[7:0];
                WINDOW_REG: window_reg     <= PWDATA[7:0];
                default: ;
            endcase
        end
    end

    assign engine_enable   = ctrl_reg_value[0];
    // clear_fail_safe is a single-cycle pulse exactly on the write access, not stored
    assign clear_fail_safe = apb_write && (PADDR[7:0] == CTRL_REG) && PWDATA[1];

    // ---------------------------------------------------------------
    // read mux
    // ---------------------------------------------------------------
    always_comb begin
        PRDATA = 32'h0;
        if (current_state == ACCESS && !PWRITE) begin
            case (PADDR[7:0])
                CTRL_REG:   PRDATA = {24'h0, 6'b0, 1'b0, ctrl_reg_value[0]};
                STATUS_REG: PRDATA = {24'h0, 6'b0, pwm_fail_safe_active, pwm_stall_detected};
                DUTY_REG:   PRDATA = {24'h0, duty_reg};
                PERIOD_REG: PRDATA = {24'h0, period_reg};
                RPM_REG:    PRDATA = {24'h0, pwm_rpm_count};
                WINDOW_REG: PRDATA = {24'h0, window_reg};
                default:    PRDATA = 32'h0;
            endcase
        end
    end

endmodule
