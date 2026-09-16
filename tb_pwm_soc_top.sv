`timescale 1ns/1ps

module tb_pwm_soc_top;

    logic PCLK = 0;
    logic PRESETn = 0;
    always #5 PCLK = ~PCLK;

    logic       PSEL, PENABLE, PWRITE, PREADY, PSLVERR;
    logic [7:0] PADDR, PWDATA, PRDATA;
    logic       pwm_out;
    logic       tach_pulse;

    int errors = 0, pass_count = 0;

    pwm_soc_top dut (
        .PCLK(PCLK), .PRESETn(PRESETn),
        .PSEL(PSEL), .PENABLE(PENABLE), .PWRITE(PWRITE),
        .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA),
        .PREADY(PREADY), .PSLVERR(PSLVERR),
        .pwm_out(pwm_out), .tach_pulse(tach_pulse)
    );

    localparam [7:0] CTRL_REG   = 8'h00;
    localparam [7:0] STATUS_REG = 8'h04;
    localparam [7:0] DUTY_REG   = 8'h08;
    localparam [7:0] PERIOD_REG = 8'h0C;
    localparam [7:0] RPM_REG    = 8'h10;
    localparam [7:0] WINDOW_REG = 8'h14;

    task apb_write(input [7:0] addr, input [7:0] data);
        begin
            @(negedge PCLK);
            PSEL = 1; PENABLE = 0; PWRITE = 1;
            PADDR = addr; PWDATA = data;
            @(posedge PCLK);
            @(negedge PCLK);
            PENABLE = 1;
            @(posedge PCLK);
            while (PREADY !== 1'b1) @(posedge PCLK);
            @(negedge PCLK);
            PSEL = 0; PENABLE = 0;
        end
    endtask

    task apb_read(input [7:0] addr, output [7:0] data);
        begin
            @(negedge PCLK);
            PSEL = 1; PENABLE = 0; PWRITE = 0;
            PADDR = addr;
            @(posedge PCLK);
            @(negedge PCLK);
            PENABLE = 1;
            @(posedge PCLK);
            while (PREADY !== 1'b1) @(posedge PCLK);
            data = PRDATA;
            @(negedge PCLK);
            PSEL = 0; PENABLE = 0;
        end
    endtask

    task check(input string name, input logic cond);
        begin
            if (cond) begin pass_count++; $display("[PASS] %s", name); end
            else begin errors++; $display("[FAIL] %s", name); end
        end
    endtask

    logic [7:0] rd;

    // ---------------------------------------------------------------
    // simulated fan model: emits a 1-PCLK-wide tach pulse every N cycles
    // while fan_spinning=1. Synchronous to PCLK to avoid sampling aliasing.
    // ---------------------------------------------------------------
    logic fan_spinning = 0;
    logic [7:0] fan_div_counter;
    localparam FAN_DIV = 8'd17;   // pulses every 17 PCLK cycles while spinning

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            fan_div_counter <= 8'd0;
            tach_pulse      <= 1'b0;
        end else if (!fan_spinning) begin
            fan_div_counter <= 8'd0;
            tach_pulse      <= 1'b0;
        end else if (fan_div_counter >= FAN_DIV - 1) begin
            fan_div_counter <= 8'd0;
            tach_pulse      <= 1'b1;
        end else begin
            fan_div_counter <= fan_div_counter + 8'd1;
            tach_pulse      <= 1'b0;
        end
    end

    initial begin
        PSEL = 0; PENABLE = 0; PWRITE = 0; PADDR = 0; PWDATA = 0;

        PRESETn = 0;
        repeat (5) @(posedge PCLK);
        PRESETn = 1;
        @(posedge PCLK);

        apb_read(STATUS_REG, rd);
        check("reset: stall=0, fail_safe=0", rd[1:0] == 2'b00);

        apb_read(RPM_REG, rd);
        check("reset: rpm_count=0", rd == 8'h00);

        // ---------------- configure PWM ----------------
        apb_write(PERIOD_REG, 8'd50);
        apb_write(DUTY_REG,   8'd25);   // 50% duty
        apb_write(WINDOW_REG, 8'd200);  // measurement window
        apb_write(CTRL_REG,   8'd1);    // enable

        // ---------------- normal case: fan spinning, tach feeding pulses ----------------
        fan_spinning = 1;
        repeat (2500) @(posedge PCLK);  // let >=1 full measurement window pass

        apb_read(RPM_REG, rd);
        check("normal spin: rpm_count > 0 (tach pulses measured)", rd > 8'd0);

        apb_read(STATUS_REG, rd);
        check("normal spin: no stall, no fail-safe", rd[1:0] == 2'b00);

        // ---------------- stall case: fan physically stops, engine still enabled ----------------
        fan_spinning = 0;
        repeat (2500) @(posedge PCLK);  // let a full window pass with zero pulses

        apb_read(STATUS_REG, rd);
        check("stall: stall_detected=1 and fail_safe_active=1", rd[1:0] == 2'b11);

        check("fail-safe: pwm_out forced low despite duty>0", pwm_out == 1'b0);

        // ---------------- recovery: clear fail-safe ----------------
        apb_write(CTRL_REG, 8'b0000_0011);  // enable=1, clear_fail_safe=1 pulse
        @(posedge PCLK);
        apb_read(STATUS_REG, rd);
        check("after clear: stall/fail-safe cleared", rd[1:0] == 2'b00);

        // ---------------- disable case ----------------
        apb_write(CTRL_REG, 8'd0);
        @(posedge PCLK);
        check("disabled: pwm_out low", pwm_out == 1'b0);

        $display("--------------------------------------------------");
        $display("TOTAL: %0d checks, %0d passed, %0d failed", pass_count+errors, pass_count, errors);
        if (errors == 0) $display("RESULT: ALL TESTS PASSED");
        else              $display("RESULT: %0d TEST(S) FAILED", errors);
        $display("--------------------------------------------------");
        $finish;
    end

    initial begin
        #1000000;
        $display("[FAIL] TIMEOUT");
        $finish;
    end

endmodule
