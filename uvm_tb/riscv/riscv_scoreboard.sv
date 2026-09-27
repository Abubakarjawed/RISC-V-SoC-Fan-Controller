//=============================================================
// riscv_scoreboard.sv
// Self-checking scoreboard for the fixed embedded firmware in
// sw/spi_test.hex: the program configures the SPI engine, sends
// TX_DATA=0xA5, polls STATUS until an RX byte is available, then
// stores it into data-SRAM word 0 and parks in a terminal
// self-loop at PC=0x34. This scoreboard has no free-running
// stimulus to generate (the CPU drives everything itself), so its
// job is purely to check what actually happened against that
// known-good program behaviour:
//   1. every completed SPI beat seen on the bus is logged and,
//      once one arrives, checked against the expected byte;
//   2. at end of test, the CPU must have parked at the terminal
//      PC and the byte stashed in SRAM word 0 must match what
//      was loop-backed on MISO.
//=============================================================
`uvm_analysis_imp_decl(_spi)

class riscv_scoreboard extends uvm_component;
    `uvm_component_utils(riscv_scoreboard)

    uvm_analysis_imp_spi #(riscv_spi_seq_item, riscv_scoreboard) spi_imp;
    virtual riscv_probe_if probe;

    // configurable expectations (overridable per test)
    bit [7:0]    expected_byte     = 8'hA5;
    logic [31:0] terminal_pc       = 32'h0000_0034;
    int unsigned run_cycles        = 4000;   // PCLK cycles to let firmware run after reset release
    int unsigned reset_cycles      = 5;

    int pass_count = 0;
    int errors     = 0;
    bit spi_beat_seen = 1'b0;
    riscv_spi_seq_item last_beat;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        spi_imp = new("spi_imp", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual riscv_probe_if)::get(this, "", "probe", probe))
            `uvm_fatal("NOVIF", "riscv_scoreboard: probe virtual interface not set in config_db")
    endfunction

    // called by the spi agent's monitor for every completed 8-bit beat
    function void write_spi(riscv_spi_seq_item item);
        spi_beat_seen = 1'b1;
        last_beat     = item;
        check("SPI beat: TX byte matches expected firmware write",
              item.tx_byte == expected_byte);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this, "running fixed-firmware SPI loopback check");

        // Reset window: PC must sit at the reset vector the whole time.
        repeat (reset_cycles) @(posedge probe.PCLK);
        check("reset: PC held at 0x0 during reset", probe.pc_q == 32'h0);

        // Let the preloaded program run to completion.
        repeat (run_cycles) @(posedge probe.PCLK);

        check("at least one SPI beat observed on the bus", spi_beat_seen);
        check("core wrote back loopback byte into SRAM word 0",
              probe.result_word()[7:0] == expected_byte);
        check("core parked in the terminal self-loop (no illegal instr)",
              probe.pc_q == terminal_pc);

        report();
        phase.drop_objection(this, "fixed-firmware SPI loopback check complete");
    endtask

    protected function void check(string name, bit cond);
        if (cond) begin
            pass_count++;
            `uvm_info("SCOREBOARD", $sformatf("[PASS] %s", name), UVM_LOW)
        end else begin
            errors++;
            `uvm_error("SCOREBOARD", $sformatf("[FAIL] %s", name))
        end
    endfunction

    function void report();
        `uvm_info("SCOREBOARD",
            $sformatf("--------------------------------------------------\nTOTAL: %0d checks, %0d passed, %0d failed\nRESULT: %s\n--------------------------------------------------",
                       pass_count + errors, pass_count, errors,
                       (errors == 0) ? "ALL TESTS PASSED" : $sformatf("%0d TEST(S) FAILED", errors)),
            UVM_NONE)
    endfunction

endclass : riscv_scoreboard
