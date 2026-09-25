`timescale 1ns/1ps
// ===========================================================================
// spi_pkg : spi_soc_top ka UVM environment.
//
// Register map (apb_slave_fsm.sv / spi wrapper se):
//   CTRL_REG   0x00 : bit0 = enable
//   STATUS_REG 0x04 : bit0=tx_full, bit1=tx_empty, bit2=rx_full, bit3=rx_empty (RO)
//   TX_DATA    0x08 : write pushes byte into tx_fifo (write-only)
//   RX_DATA    0x0C : read pops byte from rx_fifo (read-only)
//   CLKDIV     0x10 : SCLK divider
//
// DUT/TB topology: top module MISO ko MOSI se loopback karta hai (bilkul
// directed tb_spi_soc_top.sv jaisa) -- isliye jo byte bheja jaye, wahi
// byte RX FIFO mein wapas aana chahiye, same order mein. Scoreboard isi
// FIFO-order property ko check karta hai.
//
// Zaroori note: RTL mein CPOL/CPHA configurable nahi hai -- ek hi fixed
// SPI mode hai (sclk idle low, MOSI MSB-first shift). Isliye "SPI modes"
// ka test yahan applicable nahi -- iski jagah FIFO full/empty backpressure
// aur back-to-back transfers cover kiye gaye hain.
// ===========================================================================
package spi_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import apb_pkg::*;

    localparam bit [7:0] CTRL_REG   = 8'h00;
    localparam bit [7:0] STATUS_REG = 8'h04;
    localparam bit [7:0] TX_DATA    = 8'h08;
    localparam bit [7:0] RX_DATA    = 8'h0C;
    localparam bit [7:0] CLKDIV     = 8'h10;

    // -----------------------------------------------------------------
    // Scoreboard : TX_DATA writes se ek expected-byte queue banta hai;
    // RX_DATA reads us queue se FIFO-order mein pop kar ke compare karte
    // hain (loopback => same order, same value expected).
    // -----------------------------------------------------------------
    class spi_scoreboard extends uvm_subscriber #(apb_txn);
        `uvm_component_utils(spi_scoreboard)

        bit [7:0] expected_q [$];
        int unsigned match_count    = 0;
        int unsigned mismatch_count = 0;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void write(apb_txn t);
            if (t.write && t.addr[7:0] == TX_DATA) begin
                expected_q.push_back(t.wdata[7:0]);
                `uvm_info("SPI_SB", $sformatf("TX pushed 0x%0h (queue depth=%0d)",
                           t.wdata[7:0], expected_q.size()), UVM_HIGH)
            end
            else if (!t.write && t.addr[7:0] == RX_DATA) begin
                bit [7:0] exp;
                if (expected_q.size() == 0) begin
                    mismatch_count++;
                    `uvm_error("SPI_SB", $sformatf(
                        "RX_DATA read 0x%0h but no byte was expected (empty model queue)",
                        t.rdata[7:0]))
                end else begin
                    exp = expected_q.pop_front();
                    if (t.rdata[7:0] === exp) begin
                        match_count++;
                        `uvm_info("SPI_SB", $sformatf("RX 0x%0h MATCH", t.rdata[7:0]), UVM_HIGH)
                    end else begin
                        mismatch_count++;
                        `uvm_error("SPI_SB", $sformatf(
                            "RX mismatch: expected=0x%0h got=0x%0h", exp, t.rdata[7:0]))
                    end
                end
            end
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("SPI_SB", $sformatf("match=%0d mismatch=%0d outstanding=%0d",
                       match_count, mismatch_count, expected_q.size()), UVM_LOW)
            if (expected_q.size() != 0)
                `uvm_warning("SPI_SB", $sformatf(
                    "%0d TX byte(s) never read back at end of test", expected_q.size()))
        endfunction
    endclass

    // -----------------------------------------------------------------
    // Coverage : status flag combos + tx byte value classes
    // -----------------------------------------------------------------
    class spi_coverage extends uvm_subscriber #(apb_txn);
        `uvm_component_utils(spi_coverage)

        apb_txn cur_txn;

        covergroup cg_spi;
            option.per_instance = 1;
            cp_tx_byte : coverpoint cur_txn.wdata[7:0] iff (cur_txn.write && cur_txn.addr[7:0]==TX_DATA) {
                bins zero    = {8'h00};
                bins max     = {8'hFF};
                bins lsb     = {8'h01};
                bins msb     = {8'h80};
                bins mid[]   = {[8'h02:8'h7F], [8'h81:8'hFE]};
            }
            cp_status : coverpoint cur_txn.rdata[3:0] iff (!cur_txn.write && cur_txn.addr[7:0]==STATUS_REG) {
                bins idle_ready   = {4'b1010}; // tx_empty, rx_empty
                bins tx_full_b    = {4'b1001};
                bins rx_full_b    = {4'b1100};
                bins others       = default;
            }
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            cg_spi = new();
        endfunction

        function void write(apb_txn t);
            cur_txn = t;
            cg_spi.sample();
        endfunction
    endclass

    // -----------------------------------------------------------------
    // Sequences
    // -----------------------------------------------------------------
    class spi_reset_check_seq extends apb_base_sequence;
        `uvm_object_utils(spi_reset_check_seq)
        function new(string name = "spi_reset_check_seq"); super.new(name); endfunction

        task body();
            bit [31:0] rd;
            apb_read(STATUS_REG, rd);
            // bit3=rx_empty bit2=rx_full bit1=tx_empty bit0=tx_full -> 4'b1010
            if (rd[3:0] !== 4'b1010)
                `uvm_error("SPI_SEQ", $sformatf("reset: expected status=4'b1010 got=4'b%0b", rd[3:0]))
        endtask
    endclass

    class spi_init_seq extends apb_base_sequence;
        `uvm_object_utils(spi_init_seq)
        rand bit [7:0] clkdiv;
        constraint c_clkdiv { clkdiv inside {[1:4]}; }
        function new(string name = "spi_init_seq"); super.new(name); endfunction

        task body();
            apb_write(CLKDIV, clkdiv);
            apb_write(CTRL_REG, 8'd1);   // enable
        endtask
    endclass

    // Ek byte bhejo aur seedha RX_DATA se wapas parho -- APB wrapper khud
    // PREADY low rakh kar stall karta hai jab tak FIFO ready na ho, isliye
    // manual status-polling ki zaroorat nahi (directed TB ke poll-loop se
    // simpler, lekin same guarantee).
    class spi_directed_seq extends apb_base_sequence;
        `uvm_object_utils(spi_directed_seq)
        function new(string name = "spi_directed_seq"); super.new(name); endfunction

        task body();
            bit [7:0] patterns [5] = '{8'hA5, 8'h01, 8'h80, 8'hFF, 8'h00};
            bit [31:0] rd;
            foreach (patterns[i]) begin
                apb_write(TX_DATA, patterns[i]);
                apb_read(RX_DATA, rd);
                if (rd[7:0] !== patterns[i])
                    `uvm_error("SPI_SEQ", $sformatf(
                        "directed loopback mismatch: sent=0x%0h got=0x%0h", patterns[i], rd[7:0]))
            end
        endtask
    endclass

    // Back-to-back: TX FIFO (depth 4) ko ek sath 4 bytes se bhar do (koi
    // beech mein RX read nahi), phir sab 4 wapas parho. FIFO-full
    // backpressure (PREADY stall on full) is tarah exercise hoti hai.
    class spi_burst_seq extends apb_base_sequence;
        `uvm_object_utils(spi_burst_seq)
        function new(string name = "spi_burst_seq"); super.new(name); endfunction

        task body();
            bit [7:0]  burst [4] = '{8'h11, 8'h22, 8'h33, 8'h44};
            bit [31:0] rd;
            foreach (burst[i]) apb_write(TX_DATA, burst[i]);
            foreach (burst[i]) begin
                apb_read(RX_DATA, rd);
                if (rd[7:0] !== burst[i])
                    `uvm_error("SPI_SEQ", $sformatf(
                        "burst mismatch at index %0d: sent=0x%0h got=0x%0h", i, burst[i], rd[7:0]))
            end
        endtask
    endclass

    class spi_random_seq extends apb_base_sequence;
        `uvm_object_utils(spi_random_seq)
        rand int unsigned num_iter;
        constraint c_iter { num_iter inside {[10:20]}; }
        function new(string name = "spi_random_seq"); super.new(name); endfunction

        task body();
            bit [7:0]  txb;
            bit [31:0] rd;
            repeat (num_iter) begin
                txb = $urandom_range(0, 255);
                apb_write(TX_DATA, txb);
                apb_read(RX_DATA, rd);
                if (rd[7:0] !== txb)
                    `uvm_error("SPI_SEQ", $sformatf(
                        "random loopback mismatch: sent=0x%0h got=0x%0h", txb, rd[7:0]))
            end
        endtask
    endclass

    // -----------------------------------------------------------------
    // Environment
    // -----------------------------------------------------------------
    class spi_env extends uvm_env;
        `uvm_component_utils(spi_env)

        apb_agent      agent;
        spi_scoreboard sb;
        spi_coverage   cov;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = apb_agent::type_id::create("agent", this);
            agent.is_active = UVM_ACTIVE;
            sb  = spi_scoreboard::type_id::create("sb", this);
            cov = spi_coverage::type_id::create("cov", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            agent.monitor.ap.connect(sb.analysis_export);
            agent.monitor.ap.connect(cov.analysis_export);
        endfunction
    endclass

    // -----------------------------------------------------------------
    // Test
    // -----------------------------------------------------------------
    class spi_base_test extends uvm_test;
        `uvm_component_utils(spi_base_test)

        spi_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = spi_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            spi_reset_check_seq reset_seq;
            spi_init_seq        init_seq;
            spi_directed_seq    dir_seq;
            spi_burst_seq       burst_seq;
            spi_random_seq      rand_seq;

            phase.raise_objection(this);

            reset_seq = spi_reset_check_seq::type_id::create("reset_seq");
            reset_seq.start(env.agent.sequencer);

            init_seq = spi_init_seq::type_id::create("init_seq");
            if (!init_seq.randomize())
                `uvm_error("SPI_TEST", "init_seq randomize failed")
            init_seq.start(env.agent.sequencer);

            dir_seq = spi_directed_seq::type_id::create("dir_seq");
            dir_seq.start(env.agent.sequencer);

            burst_seq = spi_burst_seq::type_id::create("burst_seq");
            burst_seq.start(env.agent.sequencer);

            rand_seq = spi_random_seq::type_id::create("rand_seq");
            if (!rand_seq.randomize())
                `uvm_error("SPI_TEST", "rand_seq randomize failed")
            rand_seq.start(env.agent.sequencer);

            phase.drop_objection(this);
        endtask
    endclass

endpackage
