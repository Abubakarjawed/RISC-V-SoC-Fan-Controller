//=============================================================
// riscv_uvm_pkg.sv
//=============================================================
package riscv_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "riscv_spi_seq_item.sv"
    `include "riscv_spi_sequencer.sv"   // sequencer + sequences
    `include "riscv_spi_driver.sv"
    `include "riscv_spi_monitor.sv"
    `include "riscv_spi_agent.sv"
    `include "riscv_scoreboard.sv"
    `include "riscv_env.sv"
    `include "riscv_tests.sv"

endpackage : riscv_uvm_pkg
