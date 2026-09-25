`timescale 1ns/1ps
// ===========================================================================
// sram_pkg : Configuration SRAM (sram_soc_top) ka UVM environment.
//
// DUT: 256-byte, byte-addressable APB memory. PADDR[7:0] = address,
// combinational read, ek cycle write. Koi CTRL/STATUS register nahi hai --
// puri APB window hi memory hai. PSLVERR hamesha 0 hai (RTL mein hardwire).
// ===========================================================================
package sram_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import apb_pkg::*;

    // -----------------------------------------------------------------
    // Scoreboard : golden byte-array reference model. Monitor se writes
    // dekh kar model update karta hai, reads par model ke sath compare
    // karta hai. Testbench (top module) jo preload karta hai wahi values
    // config_db ke through yahan set hote hain taake model in-sync rahe.
    // -----------------------------------------------------------------
    class sram_scoreboard extends uvm_subscriber #(apb_txn);
        `uvm_component_utils(sram_scoreboard)

        bit [7:0] golden_mem [256];
        int       match_count   = 0;
        int       mismatch_count = 0;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        // preload ko model mein bhi apply karo (dut.u_sram_engine.mem ko
        // top module preload karta hai, hum sirf model side sync karte hain)
        function void preload(bit [7:0] addr, bit [7:0] data);
            golden_mem[addr] = data;
        endfunction

        function void write(apb_txn t);
            bit [7:0] a = t.addr[7:0];
            if (t.write) begin
                golden_mem[a] = t.wdata[7:0];
                `uvm_info("SRAM_SB", $sformatf("WRITE addr=0x%0h data=0x%0h", a, t.wdata[7:0]), UVM_HIGH)
            end else begin
                if (t.rdata[7:0] === golden_mem[a]) begin
                    match_count++;
                    `uvm_info("SRAM_SB", $sformatf("READ  addr=0x%0h data=0x%0h MATCH", a, t.rdata[7:0]), UVM_HIGH)
                end else begin
                    mismatch_count++;
                    `uvm_error("SRAM_SB", $sformatf(
                        "READ MISMATCH addr=0x%0h expected=0x%0h got=0x%0h",
                        a, golden_mem[a], t.rdata[7:0]))
                end
            end
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("SRAM_SB", $sformatf("reads matched=%0d mismatched=%0d",
                       match_count, mismatch_count), UVM_LOW)
        endfunction
    endclass

    // -----------------------------------------------------------------
    // Sequences
    // -----------------------------------------------------------------

    // Reset ke baad, preload ki gayi values readback honi chahiye (SRAM
    // reset se clear nahi hoti - real memory arrays don't clear).
    class sram_reset_check_seq extends apb_base_sequence;
        `uvm_object_utils(sram_reset_check_seq)
        function new(string name = "sram_reset_check_seq"); super.new(name); endfunction

        task body();
            bit [31:0] rd;
            apb_read(8'h00, rd); // PROFILE1_DUTY_ADDR
            if (rd[7:0] !== 8'h19)
                `uvm_error("SRAM_SEQ", $sformatf("reset: profile1 duty expected 0x19 got 0x%0h", rd[7:0]))
            else
                `uvm_info("SRAM_SEQ", "reset: preload readback ok", UVM_LOW)
        endtask
    endclass

    // Directed: write/readback, neighbor isolation, overwrite, boundary
    class sram_directed_seq extends apb_base_sequence;
        `uvm_object_utils(sram_directed_seq)
        function new(string name = "sram_directed_seq"); super.new(name); endfunction

        task body();
            bit [31:0] rd;

            // normal write + readback
            apb_write(8'h10, 8'h77);
            apb_read(8'h10, rd);
            if (rd[7:0] !== 8'h77) `uvm_error("SRAM_SEQ", "write+readback 0x10 failed")

            // neighbor isolation (0x0F / 0x11 preloaded to 0x00 by top TB)
            apb_read(8'h0F, rd);
            if (rd[7:0] !== 8'h00) `uvm_error("SRAM_SEQ", "neighbor 0x0F corrupted")
            apb_read(8'h11, rd);
            if (rd[7:0] !== 8'h00) `uvm_error("SRAM_SEQ", "neighbor 0x11 corrupted")

            // overwrite an existing config value (profile update)
            apb_write(8'h00, 8'hFF);
            apb_read(8'h00, rd);
            if (rd[7:0] !== 8'hFF) `uvm_error("SRAM_SEQ", "profile1 duty overwrite failed")

            // profile1 period (addr 0x01) untouched by duty overwrite
            apb_read(8'h01, rd);
            if (rd[7:0] !== 8'h32) `uvm_error("SRAM_SEQ", "profile1 period corrupted by unrelated write")

            // boundary addresses: min (0x00) and max (0xFF)
            apb_write(8'h00, 8'h11);
            apb_read(8'h00, rd);
            if (rd[7:0] !== 8'h11) `uvm_error("SRAM_SEQ", "boundary write 0x00 failed")

            apb_write(8'hFF, 8'h22);
            apb_read(8'hFF, rd);
            if (rd[7:0] !== 8'h22) `uvm_error("SRAM_SEQ", "boundary write 0xFF failed")
        endtask
    endclass

    // Random: N iterations of random addr/data write-then-read, functional
    // coverage ke liye address space acche se explore karta hai.
    class sram_random_seq extends apb_base_sequence;
        `uvm_object_utils(sram_random_seq)
        rand int unsigned num_iter;
        constraint c_iter { num_iter inside {[20:40]}; }

        function new(string name = "sram_random_seq"); super.new(name); endfunction

        task body();
            bit [7:0]  addr;
            bit [7:0]  data;
            bit [31:0] rd;
            repeat (num_iter) begin
                addr = $urandom_range(0, 255);
                data = $urandom_range(0, 255);
                apb_write(addr, data);
                apb_read(addr, rd);
                if (rd[7:0] !== data)
                    `uvm_error("SRAM_SEQ", $sformatf("random rw mismatch addr=0x%0h exp=0x%0h got=0x%0h",
                               addr, data, rd[7:0]))
            end
        endtask
    endclass

    // -----------------------------------------------------------------
    // Coverage collector : address bins + access type
    // -----------------------------------------------------------------
    class sram_coverage extends uvm_subscriber #(apb_txn);
        `uvm_component_utils(sram_coverage)

        apb_txn cur_txn;

        covergroup cg_sram;
            option.per_instance = 1;
            cp_addr : coverpoint cur_txn.addr[7:0] {
                bins low        = {8'h00};
                bins high       = {8'hFF};
                bins profile1[] = {[8'h00:8'h03]};
                bins mid        = {[8'h20:8'hDF]};
                bins others     = default;
            }
            cp_write : coverpoint cur_txn.write;
            cx_addr_write : cross cp_addr, cp_write;
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            cg_sram = new();
        endfunction

        function void write(apb_txn t);
            cur_txn = t;
            cg_sram.sample();
        endfunction
    endclass

    // -----------------------------------------------------------------
    // Environment
    // -----------------------------------------------------------------
    class sram_env extends uvm_env;
        `uvm_component_utils(sram_env)

        apb_agent       agent;
        sram_scoreboard sb;
        sram_coverage   cov;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = apb_agent::type_id::create("agent", this);
            agent.is_active = UVM_ACTIVE;
            sb  = sram_scoreboard::type_id::create("sb", this);
            cov = sram_coverage::type_id::create("cov", this);
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
    class sram_base_test extends uvm_test;
        `uvm_component_utils(sram_base_test)

        sram_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = sram_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            sram_reset_check_seq reset_seq;
            sram_directed_seq    dir_seq;
            sram_random_seq      rand_seq;

            phase.raise_objection(this);

            // scoreboard model ko top-level preload ke sath sync karo
            // (top TB dut.u_sram_engine.mem[...] ko directly poke karta hai)
            env.sb.preload(8'h00, 8'h19); // PROFILE1_DUTY
            env.sb.preload(8'h01, 8'h32); // PROFILE1_PERIOD
            env.sb.preload(8'h02, 8'h40); // PROFILE2_DUTY
            env.sb.preload(8'h03, 8'h64); // PROFILE2_PERIOD
            env.sb.preload(8'hFF, 8'hAA);
            env.sb.preload(8'h0F, 8'h00);
            env.sb.preload(8'h11, 8'h00);

            reset_seq = sram_reset_check_seq::type_id::create("reset_seq");
            reset_seq.start(env.agent.sequencer);

            dir_seq = sram_directed_seq::type_id::create("dir_seq");
            dir_seq.start(env.agent.sequencer);

            rand_seq = sram_random_seq::type_id::create("rand_seq");
            if (!rand_seq.randomize())
                `uvm_error("SRAM_TEST", "rand_seq randomize failed")
            rand_seq.start(env.agent.sequencer);

            phase.drop_objection(this);
        endtask
    endclass

endpackage
