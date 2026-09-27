//=============================================================
// riscv_tests.sv
//=============================================================
class riscv_base_test extends uvm_test;
    `uvm_component_utils(riscv_base_test)

    riscv_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = riscv_env::type_id::create("env", this);
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

endclass : riscv_base_test


//=============================================================
// riscv_loopback_test.sv
// Reproduces the original directed testbench exactly: SPI slave
// is a pure loopback (MISO <= MOSI), firmware writes 0xA5 to
// TX_DATA and must read the same 0xA5 back.
//=============================================================
class riscv_loopback_test extends riscv_base_test;
    `uvm_component_utils(riscv_loopback_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        riscv_spi_loopback_seq seq = riscv_spi_loopback_seq::type_id::create("seq");
        seq.start(env.spi_agent.sqr);
    endtask

endclass : riscv_loopback_test


//=============================================================
// riscv_fixed_byte_test.sv
// Negative-style variant: SPI slave ignores MOSI and always
// drives a fixed byte back. Since the fixed-firmware TX byte is
// hardcoded to 0xA5 in sw/spi_test.hex, run this with the same
// 0xA5 to confirm the core also works against a "real" (i.e.
// non-loopback) SPI slave, not just the loopback wire the
// original TB relied on.
//=============================================================
class riscv_fixed_byte_test extends riscv_base_test;
    `uvm_component_utils(riscv_fixed_byte_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env.sb.expected_byte = 8'hA5; // must match whatever the fixed sequence below drives
    endfunction

    task run_phase(uvm_phase phase);
        riscv_spi_fixed_byte_seq seq = riscv_spi_fixed_byte_seq::type_id::create("seq");
        seq.byte_to_send = 8'hA5;
        seq.start(env.spi_agent.sqr);
    endtask

endclass : riscv_fixed_byte_test
