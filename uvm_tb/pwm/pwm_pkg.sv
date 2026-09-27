`timescale 1ns/1ps

package pwm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import apb_pkg::*;

    localparam bit [7:0] CTRL_REG   = 8'h00;
    localparam bit [7:0] STATUS_REG = 8'h04;
    localparam bit [7:0] DUTY_REG   = 8'h08;
    localparam bit [7:0] PERIOD_REG = 8'h0C;
    localparam bit [7:0] RPM_REG    = 8'h10;
    localparam bit [7:0] WINDOW_REG = 8'h14;

    `uvm_analysis_imp_decl(_apb)
    `uvm_analysis_imp_decl(_pwm)


    class pwm_meas_txn extends uvm_sequence_item;
        int unsigned period_cycles;
        int unsigned duty_cycles;

        `uvm_object_utils_begin(pwm_meas_txn)
            `uvm_field_int(period_cycles, UVM_ALL_ON)
            `uvm_field_int(duty_cycles,   UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "pwm_meas_txn");
            super.new(name);
        endfunction
    endclass


    class pwm_fan_model extends uvm_component;
        `uvm_component_utils(pwm_fan_model)

        virtual pwm_if vif;
        bit             spinning = 1'b0;   // test isko seedha set karta hai
        int unsigned    pulse_div = 17;
        int unsigned    pulses_since_clear = 0;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual pwm_if)::get(this, "", "vif", vif))
                `uvm_fatal("PWM_FAN", "virtual pwm_if not set in config_db")
        endfunction

        function void clear_pulse_count();
            pulses_since_clear = 0;
        endfunction

        task run_phase(uvm_phase phase);
            int unsigned cnt = 0;
            vif.tach_pulse <= 1'b0;
            forever begin
                @(posedge vif.PCLK or negedge vif.PRESETn);
                if (!vif.PRESETn) begin
                    cnt = 0;
                    vif.tach_pulse = 1'b0;
                end else if (!spinning) begin
                    cnt = 0;
                    vif.tach_pulse = 1'b0;
                end else if (cnt >= pulse_div - 1) begin
                    cnt = 0;
                    vif.tach_pulse = 1'b1;
                    pulses_since_clear++;
                end else begin
                    cnt = cnt + 1;
                    vif.tach_pulse = 1'b0;
                end
            end
        endtask
    endclass


    class pwm_monitor extends uvm_monitor;
        `uvm_component_utils(pwm_monitor)

        virtual pwm_if vif;
        uvm_analysis_port #(pwm_meas_txn) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual pwm_if)::get(this, "", "vif", vif))
                `uvm_fatal("PWM_MON", "virtual pwm_if not set in config_db")
        endfunction

        task run_phase(uvm_phase phase);
            int unsigned cyc_since_edge = 0;
            int unsigned high_cyc       = 0;
            bit          prev           = 1'b0;
            bit          first_edge     = 1'b0;

            forever begin
                bit cur;
                @(posedge vif.PCLK);
                if (!vif.PRESETn) begin
                    cyc_since_edge = 0;
                    high_cyc       = 0;
                    prev           = 1'b0;
                    first_edge     = 1'b0;
                    continue;
                end

                cur = vif.pwm_out;
                if (cur && !prev) begin
                    if (first_edge) begin
                        pwm_meas_txn t = pwm_meas_txn::type_id::create("t");
                        t.period_cycles = cyc_since_edge;
                        t.duty_cycles   = high_cyc;
                        ap.write(t);
                    end
                    first_edge     = 1'b1;
                    cyc_since_edge = 0;
                    high_cyc       = 0;
                end

                cyc_since_edge++;
                if (cur) high_cyc++;
                prev = cur;
            end
        endtask
    endclass

    // -----------------------------------------------------------------
    // Scoreboard
    // -----------------------------------------------------------------
    class pwm_scoreboard extends uvm_component;
        `uvm_component_utils(pwm_scoreboard)

        uvm_analysis_imp_apb #(apb_txn,      pwm_scoreboard) apb_imp;
        uvm_analysis_imp_pwm #(pwm_meas_txn, pwm_scoreboard) pwm_imp;

        bit [7:0] duty_cfg   = 0;
        bit [7:0] period_cfg = 0;
        bit [7:0] window_cfg = 0;
        bit       enable_cfg = 0;

        int unsigned waveform_checks = 0;
        int unsigned waveform_errors = 0;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            apb_imp = new("apb_imp", this);
            pwm_imp = new("pwm_imp", this);
        endfunction

  
        function void write_apb(apb_txn t);
            if (t.addr[31:16] != 16'h1001)
                return;
            if (t.write) begin
                case (t.addr[7:0])
                    CTRL_REG:   enable_cfg = t.wdata[0];
                    DUTY_REG:   duty_cfg   = t.wdata[7:0];
                    PERIOD_REG: period_cfg = t.wdata[7:0];
                    WINDOW_REG: window_cfg = t.wdata[7:0];
                    default: ;
                endcase
            end
        endfunction


        function void write_pwm(pwm_meas_txn t);
            if (enable_cfg && duty_cfg != 0 && duty_cfg < period_cfg) begin
                waveform_checks++;
                if (t.period_cycles != period_cfg) begin
                    waveform_errors++;
                    `uvm_error("PWM_SB", $sformatf(
                        "period mismatch: configured=%0d measured=%0d",
                        period_cfg, t.period_cycles))
                end
                if (t.duty_cycles != duty_cfg) begin
                    waveform_errors++;
                    `uvm_error("PWM_SB", $sformatf(
                        "duty mismatch: configured=%0d measured=%0d",
                        duty_cfg, t.duty_cycles))
                end
            end
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("PWM_SB", $sformatf("waveform checks=%0d errors=%0d",
                       waveform_checks, waveform_errors), UVM_LOW)
        endfunction
    endclass

    // -----------------------------------------------------------------
    // Coverage : duty/period value bins + status bit combos
    // -----------------------------------------------------------------
    class pwm_coverage extends uvm_subscriber #(apb_txn);
        `uvm_component_utils(pwm_coverage)

        apb_txn cur_txn;

        covergroup cg_pwm_cfg;
            option.per_instance = 1;
            cp_addr : coverpoint cur_txn.addr[7:0] {
                bins ctrl   = {CTRL_REG};
                bins status = {STATUS_REG};
                bins duty   = {DUTY_REG};
                bins period = {PERIOD_REG};
                bins rpm    = {RPM_REG};
                bins window = {WINDOW_REG};
            }
            cp_wdata_duty : coverpoint cur_txn.wdata[7:0] iff (cur_txn.write && cur_txn.addr[7:0]==DUTY_REG) {
                bins zero    = {0};
                bins max     = {255};
                bins mid[]   = {[1:254]};
            }
            cp_status_rdata : coverpoint cur_txn.rdata[1:0]
                              iff (!cur_txn.write && cur_txn.addr[7:0]==STATUS_REG) {
                bins normal      = {2'b00};
                bins stall_only  = {2'b01};
                bins failsafe    = {2'b11};
            }
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            cg_pwm_cfg = new();
        endfunction

        function void write(apb_txn t);
            cur_txn = t;
            cg_pwm_cfg.sample();
        endfunction
    endclass

    class pwm_reset_check_seq extends apb_base_sequence;
        `uvm_object_utils(pwm_reset_check_seq)
        function new(string name = "pwm_reset_check_seq"); super.new(name); endfunction

        task body();
            bit [31:0] rd;
            apb_read(STATUS_REG, rd);
            if (rd[1:0] !== 2'b00) `uvm_error("PWM_SEQ", "reset: stall/fail_safe not clear")
            apb_read(RPM_REG, rd);
            if (rd[7:0] !== 8'h00) `uvm_error("PWM_SEQ", "reset: rpm_count not 0")
        endtask
    endclass


    class pwm_reg_read_seq extends apb_base_sequence;
        `uvm_object_utils(pwm_reg_read_seq)
        bit [31:0] addr;
        bit [31:0] data;
        function new(string name = "pwm_reg_read_seq"); super.new(name); endfunction
        task body();
            apb_read(addr, data);
        endtask
    endclass

    class pwm_configure_seq extends apb_base_sequence;
        `uvm_object_utils(pwm_configure_seq)
        rand bit [7:0] duty;
        rand bit [7:0] period;
        rand bit [7:0] window;

        // normal (valid) range: 0 < duty < period, taake pwm_out edges
        // aayein aur scoreboard measurement check kar sake
        constraint c_period_range { period inside {[20:200]}; }
        constraint c_duty_valid   { duty inside {[1:period-1]}; }
        constraint c_window_range { window inside {[100:250]}; }

        function new(string name = "pwm_configure_seq"); super.new(name); endfunction

        task body();
            apb_write(PERIOD_REG, period);
            apb_write(DUTY_REG,   duty);
            apb_write(WINDOW_REG, window);
            apb_write(CTRL_REG,   8'd1);   // enable
        endtask
    endclass


    class pwm_configure_edge_seq extends apb_base_sequence;
        `uvm_object_utils(pwm_configure_edge_seq)
        rand bit [7:0] duty;
        rand bit [7:0] period;
        bit            edge_type; // 0 = duty=0, 1 = duty>=period

        constraint c_period_range { period inside {[20:200]}; }
        constraint c_duty_edge {
            if (edge_type == 0) duty == 0;
            else                duty inside {[period:255]};
        }

        function new(string name = "pwm_configure_edge_seq"); super.new(name); endfunction

        task body();
            apb_write(PERIOD_REG, period);
            apb_write(DUTY_REG,   duty);
            apb_write(WINDOW_REG, 8'd150);
            apb_write(CTRL_REG,   8'd1);
        endtask
    endclass


    class pwm_invalid_addr_seq extends apb_base_sequence;
        `uvm_object_utils(pwm_invalid_addr_seq)
        function new(string name = "pwm_invalid_addr_seq"); super.new(name); endfunction
        task body();
            bit [31:0] rd;
            apb_read(8'hF0, rd);   // register map (0x00-0x14) se bahar
        endtask
    endclass

    class pwm_clear_failsafe_seq extends apb_base_sequence;
        `uvm_object_utils(pwm_clear_failsafe_seq)
        function new(string name = "pwm_clear_failsafe_seq"); super.new(name); endfunction
        task body();
            apb_write(CTRL_REG, 8'b0000_0011); // enable=1, clear_fail_safe pulse
        endtask
    endclass

    class pwm_disable_seq extends apb_base_sequence;
        `uvm_object_utils(pwm_disable_seq)
        function new(string name = "pwm_disable_seq"); super.new(name); endfunction
        task body();
            apb_write(CTRL_REG, 8'd0);
        endtask
    endclass

    // -----------------------------------------------------------------
    // Environment
    // -----------------------------------------------------------------
    class pwm_env extends uvm_env;
        `uvm_component_utils(pwm_env)

        apb_agent       agent;
        pwm_fan_model   fan;
        pwm_monitor     pmon;
        pwm_scoreboard  sb;
        pwm_coverage    cov;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = apb_agent::type_id::create("agent", this);
            agent.is_active = UVM_ACTIVE;
            fan  = pwm_fan_model::type_id::create("fan", this);
            pmon = pwm_monitor::type_id::create("pmon", this);
            sb   = pwm_scoreboard::type_id::create("sb", this);
            cov  = pwm_coverage::type_id::create("cov", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            agent.monitor.ap.connect(sb.apb_imp);
            agent.monitor.ap.connect(cov.analysis_export);
            pmon.ap.connect(sb.pwm_imp);
        endfunction
    endclass


    class pwm_base_test extends uvm_test;
        `uvm_component_utils(pwm_base_test)

        pwm_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = pwm_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            pwm_reset_check_seq     reset_seq;
            pwm_configure_seq       cfg_seq;
            pwm_configure_edge_seq  edge_seq;
            pwm_clear_failsafe_seq  clr_seq;
            pwm_disable_seq         dis_seq;
            pwm_reg_read_seq        rd_seq;
            pwm_invalid_addr_seq    inv_seq;

            phase.raise_objection(this);

            // ---- reset check ----
            reset_seq = pwm_reset_check_seq::type_id::create("reset_seq");
            reset_seq.start(env.agent.sequencer);

            // ---- invalid address read: default/unmapped branch cover karne ke liye ----
            inv_seq = pwm_invalid_addr_seq::type_id::create("inv_seq");
            inv_seq.start(env.agent.sequencer);

            // ---- edge case: duty=0 (fully off) ----
            edge_seq = pwm_configure_edge_seq::type_id::create("edge_seq0");
            edge_seq.edge_type = 0;
            if (!edge_seq.randomize())
                `uvm_error("PWM_TEST", "edge_seq0 randomize failed")
            edge_seq.start(env.agent.sequencer);
            repeat (300) @(posedge env.agent.driver.vif.PCLK);  // is state mein settle hone dein

            // ---- edge case: duty>=period (fully on) ----
            edge_seq = pwm_configure_edge_seq::type_id::create("edge_seq1");
            edge_seq.edge_type = 1;
            if (!edge_seq.randomize())
                `uvm_error("PWM_TEST", "edge_seq1 randomize failed")
            edge_seq.start(env.agent.sequencer);
            repeat (300) @(posedge env.agent.driver.vif.PCLK);  // is state mein settle hone dein

           
            cfg_seq = pwm_configure_seq::type_id::create("cfg_seq");
            if (!cfg_seq.randomize())
                `uvm_error("PWM_TEST", "cfg_seq randomize failed")
            cfg_seq.start(env.agent.sequencer);

            // ---- normal case: fan spinning, tach feeding pulses ----
            env.fan.spinning = 1'b1;
            env.fan.clear_pulse_count();
            repeat (2500) @(posedge env.agent.driver.vif.PCLK);   // let >=1 full window pass

            rd_seq = pwm_reg_read_seq::type_id::create("rd_seq");
            rd_seq.addr = RPM_REG;
            rd_seq.start(env.agent.sequencer);
            if (rd_seq.data[7:0] == 8'd0)
                `uvm_error("PWM_TEST", "normal spin: rpm_count still 0, tach pulses not measured")

            rd_seq = pwm_reg_read_seq::type_id::create("rd_seq2");
            rd_seq.addr = STATUS_REG;
            rd_seq.start(env.agent.sequencer);
            if (rd_seq.data[1:0] !== 2'b00)
                `uvm_error("PWM_TEST", "normal spin: unexpected stall/fail-safe")

            // ---- stall case: fan physically stops, engine still enabled ----
            env.fan.spinning = 1'b0;
            repeat (2500) @(posedge env.agent.driver.vif.PCLK);   // full window with zero pulses

            rd_seq = pwm_reg_read_seq::type_id::create("rd_seq3");
            rd_seq.addr = STATUS_REG;
            rd_seq.start(env.agent.sequencer);
            if (rd_seq.data[1:0] !== 2'b11)
                `uvm_error("PWM_TEST", $sformatf(
                    "stall: expected stall=1,fail_safe=1, got status=0x%0h", rd_seq.data))

            // ---- recovery: clear fail-safe ----
            clr_seq = pwm_clear_failsafe_seq::type_id::create("clr_seq");
            clr_seq.start(env.agent.sequencer);
            @(posedge env.agent.driver.vif.PCLK);

            rd_seq = pwm_reg_read_seq::type_id::create("rd_seq4");
            rd_seq.addr = STATUS_REG;
            rd_seq.start(env.agent.sequencer);
            if (rd_seq.data[1:0] !== 2'b00)
                `uvm_error("PWM_TEST", "after clear: stall/fail-safe not cleared")

            // ---- disable case ----
            dis_seq = pwm_disable_seq::type_id::create("dis_seq");
            dis_seq.start(env.agent.sequencer);
            @(posedge env.agent.driver.vif.PCLK);

            phase.drop_objection(this);
        endtask
    endclass

endpackage
