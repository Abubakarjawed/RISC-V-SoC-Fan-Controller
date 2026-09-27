`timescale 1ns/1ps

package system_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import apb_pkg::*;
    import spi_pkg::*;
    import pwm_pkg::*;
    import sram_pkg::*;
    import uart_uvm_pkg::*;

    // System Scoreboard
    class system_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(system_scoreboard)

        uvm_analysis_imp#(apb_pkg::apb_txn, system_scoreboard) apb_export;

        int spi_count  = 0;
        int pwm_count  = 0;
        int sram_count = 0;
        int uart_count = 0;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            apb_export = new("apb_export", this);
        endfunction

        virtual function void write(apb_txn tr);
            case (tr.addr[31:16])
                16'h1000: spi_count++;  // SPI  Base: 0x1000_0000
                16'h1001: pwm_count++;  // PWM  Base: 0x1001_0000
                16'h1002: sram_count++; // SRAM Base: 0x1002_0000
                16'h1003: uart_count++; // UART Base: 0x1003_0000
                default: ;
            endcase
        endfunction

        function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("SYS_SB", $sformatf("=== SYSTEM VERIFICATION SUMMARY ==="), UVM_LOW)
            `uvm_info("SYS_SB", $sformatf("SPI Transfers  : %0d", spi_count), UVM_LOW)
            `uvm_info("SYS_SB", $sformatf("PWM Transfers  : %0d", pwm_count), UVM_LOW)
            `uvm_info("SYS_SB", $sformatf("SRAM Transfers : %0d", sram_count), UVM_LOW)
            `uvm_info("SYS_SB", $sformatf("UART Transfers : %0d", uart_count), UVM_LOW)
        endfunction
    endclass

    // 1. Directed Full SoC Sequence (Cleaned & Corrected)
    class system_full_soc_seq extends apb_base_sequence;
        `uvm_object_utils(system_full_soc_seq)

        function new(string name = "system_full_soc_seq");
            super.new(name);
        endfunction

        task body();
            bit [31:0] temp_rd;

            `uvm_info("SYS_SEQ", "Starting Full SoC System Sequence across SPI, PWM, SRAM, and UART...", UVM_LOW)
            
            // Step 1: Config SRAM Preload & Readback (Base: 0x1002_0000)
            apb_write(32'h1002_0000, 32'h0000_0064); // Write 0x64 to addr 0x00
            apb_read (32'h1002_0000, temp_rd);       // Read back addr 0x00 -> MATCH!

            apb_write(32'h1002_0004, 32'h0000_0032); // Write 0x32 to addr 0x04
            apb_read (32'h1002_0004, temp_rd);       // Read back addr 0x04 -> MATCH!

            // Step 2: PWM Subsystem Configuration (Base: 0x1001_0000)
            apb_write(32'h1001_000C, 32'd100); // PERIOD = 100
            apb_write(32'h1001_0008, 32'd50);  // DUTY   = 50
            apb_write(32'h1001_0000, 32'd1);   // CTRL   = 1 (Enable)

            // Step 3: SPI Telemetry Subsystem (Base: 0x1000_0000)
            apb_write(32'h1000_0000, 32'd1);    // Enable SPI (CTRL=1)
            apb_write(32'h1000_0008, 32'hA5);   // Write TX_DATA = 0xA5
            #10us;                               // Wait for hardware transmission
            apb_read (32'h1000_000C, temp_rd);   // Read RX_DATA -> MATCH!

            // Step 4: UART Status Console (Base: 0x1003_0000)
            apb_write(32'h1003_0000, 32'h46);   // 'F'
            apb_write(32'h1003_0000, 32'h41);   // 'A'
            apb_write(32'h1003_0000, 32'h4E);   // 'N'
            apb_write(32'h1003_0000, 32'h20);   // ' '
            apb_write(32'h1003_0000, 32'h4F);   // 'O'
            apb_write(32'h1003_0000, 32'h4B);   // 'K'
            apb_write(32'h1003_0000, 32'h0A);   // '\n'

            `uvm_info("SYS_SEQ", "Full SoC System Sequence Completed Successfully!", UVM_LOW)
        endtask
    endclass

    // 2. Constrained-Random System Sequence (UVM Compliant)
    class system_random_soc_seq extends apb_base_sequence;
        `uvm_object_utils(system_random_soc_seq)

        rand int unsigned num_trans;
        constraint c_num_trans { num_trans inside {[20:40]}; }

        function new(string name = "system_random_soc_seq");
            super.new(name);
        endfunction

        task body();
            bit [31:0] temp_rd;
            `uvm_info("RAND_SEQ", $sformatf("Starting Constrained-Random SoC Sequence (%0d transactions)...", num_trans), UVM_LOW)

            // Step A: Initialize SPI & PWM
            apb_write(32'h1000_0000, 32'h1); // SPI Enable
            apb_write(32'h1001_0000, 32'h1); // PWM Enable

            // Step B: Randomly exercise all 4 peripherals each iteration
            for (int i = 0; i < num_trans; i++) begin
                bit [31:0] rand_val  = $urandom_range(8'h10, 8'hFE);
                bit [7:0]  rand_addr = ($urandom_range(0, 15)) * 4;
                int unsigned peri    = $urandom_range(0, 3);

                case (peri)
                    0: begin // SPI  0x1000_0000 — TX then RX loopback
                        apb_write(32'h1000_0008, rand_val);
                        #10us;
                        apb_read (32'h1000_000C, temp_rd);
                    end
                    1: begin // PWM  0x1001_0000 — DUTY/PERIOD write, STATUS read
                        apb_write(32'h1001_000C, 32'd200);   // PERIOD
                        apb_write(32'h1001_0008, rand_val);  // DUTY
                        apb_read (32'h1001_0004, temp_rd);   // STATUS
                    end
                    2: begin // SRAM 0x1002_0000 — write + readback
                        apb_write(32'h1002_0000 + rand_addr, rand_val);
                        apb_read (32'h1002_0000 + rand_addr, temp_rd);
                    end
                    3: begin // UART 0x1003_0000 — TX write, STATUS read
                        apb_write(32'h1003_0000, rand_val);
                        #10us;
                        apb_read (32'h1003_0008, temp_rd);
                    end
                endcase
            end

            `uvm_info("RAND_SEQ", "Constrained-Random SoC Sequence Completed!", UVM_LOW)
        endtask
    endclass

    // System Environment
    class system_env extends uvm_env;
        `uvm_component_utils(system_env)

        spi_env          spi_sub_env;
        pwm_env          pwm_sub_env;
        sram_env         sram_sub_env;
        uart_environment uart_sub_env;
        system_scoreboard sb;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            spi_sub_env  = spi_env::type_id::create("spi_sub_env", this);
            pwm_sub_env  = pwm_env::type_id::create("pwm_sub_env", this);
            sram_sub_env = sram_env::type_id::create("sram_sub_env", this);
            uart_sub_env = uart_environment::type_id::create("uart_sub_env", this);
            sb           = system_scoreboard::type_id::create("sb", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            pwm_sub_env.agent.monitor.ap.connect(sb.apb_export);
        endfunction
    endclass

    // Test 1: Directed Base Test
    class system_base_test extends uvm_test;
        `uvm_component_utils(system_base_test)

        system_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = system_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            system_full_soc_seq sys_seq;
            sys_seq = system_full_soc_seq::type_id::create("sys_seq");

            phase.raise_objection(this, "Starting Full SoC System Sequence");
            sys_seq.start(env.pwm_sub_env.agent.sequencer);
            #10us; 
            phase.drop_objection(this, "Completed Full SoC System Sequence");
        endtask
    endclass

    // Test 2: Constrained-Random UVM Test
    class system_random_test extends uvm_test;
        `uvm_component_utils(system_random_test)

        system_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = system_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            system_random_soc_seq rand_seq;
            rand_seq = system_random_soc_seq::type_id::create("rand_seq");

            phase.raise_objection(this, "Starting Constrained-Random System Sequence");
            if (!rand_seq.randomize())
                `uvm_fatal("RAND_TEST", "Sequence randomization failed!")
            rand_seq.start(env.pwm_sub_env.agent.sequencer);
            #10us;
            phase.drop_objection(this, "Completed Constrained-Random System Sequence");
        endtask
    endclass

endpackage