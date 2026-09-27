# UVM testbench for `riscv_spi_soc_top`

Replaces the directed `tb_riscv_spi_soc_top.sv` with a proper UVM 1.2
environment, same DUT, same fixed firmware (`sw/spi_test.hex`).

## Files (compile in this order)
```
rtl/cpu/*.sv
rtl/soc/*.sv
tb/uvm/riscv_spi_if.sv
tb/uvm/riscv_probe_if.sv
tb/uvm/riscv_uvm_pkg.sv     <- pulls in seq_item, sequencer, driver,
                                monitor, agent, scoreboard, env, tests
                                via `include, in that order
tb/uvm/tb_top.sv
```

## Architecture
- **`riscv_spi_if`** – pin interface (SCLK/MOSI/MISO/SS_N/PRESETn) the
  agent drives and monitors.
- **`riscv_spi_driver`** – owns the only pin the TB drives, MISO.
  Also generates the reset pulse. Two response modes selected by
  sequence: `MISO_LOOPBACK` (MISO mirrors MOSI — the same slave model
  the old `assign MISO = MOSI;` gave you) and `MISO_FIXED` (drives a
  fixed byte back regardless of MOSI, MSB-first, synced to SCLK).
- **`riscv_spi_monitor`** – passively decodes SCLK/MOSI/MISO/SS_N into
  byte-level `riscv_spi_seq_item`s and publishes them on an analysis
  port.
- **`riscv_scoreboard`** – subscribes to the monitor, checks every SPI
  beat's TX byte against the expected firmware byte, and does the
  same end-of-test whitebox checks the old TB did (PC held in reset,
  final SRAM byte, core parked at the terminal PC) via a small
  **`riscv_probe_if`** that `tb_top` wires to `dut.u_rv32i_core.pc_q`
  and `dut.u_dmem.mem0..3[0]` — so no class code touches `dut.*`
  hierarchical paths directly.
- **Tests**: `riscv_loopback_test` (drop-in equivalent of the old
  directed TB) and `riscv_fixed_byte_test` (same firmware, but proves
  the core also works against a non-loopback SPI slave).

## Honest scope note
The firmware in `sw/spi_test.hex` is fixed and self-driving — the CPU
generates all bus activity itself, there's no instruction stream for
a sequencer to inject. So this environment's "stimulus" is really just
the SPI slave response model (loopback vs. fixed byte) and reset
timing; the real value over the old directed TB is the self-checking
scoreboard/monitor split, reusable agent, and a second test case for
free. If you want genuinely UVM-driven instruction-level verification
(random programs, a reference/ISS scoreboard, etc.), that needs a
mechanism to load different programs into `imem` per test (e.g. a
backdoor `load_program()` task) — happy to add that if useful.

## Running it
This needs a real UVM kernel — Questa, VCS, or Xcelium. Example (VCS):
```
vcs -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps \
    rtl/cpu/*.sv rtl/soc/*.sv \
    tb/uvm/riscv_spi_if.sv tb/uvm/riscv_probe_if.sv \
    tb/uvm/riscv_uvm_pkg.sv tb/uvm/tb_top.sv \
    -o simv
./simv +UVM_TESTNAME=riscv_loopback_test
./simv +UVM_TESTNAME=riscv_fixed_byte_test
```

**Important — what I could and couldn't verify here:** this sandbox
only has Icarus Verilog (`iverilog` 12.0). I used it to (a) confirm
the plain RTL files compile cleanly, and (b) attempt to elaborate the
UVM classes, first against the real Accellera `uvm-core` library and
then against a hand-written stub of the same API. Both failed for a
tooling reason unrelated to this code: Icarus Verilog does not support
**parameterized classes** (`class foo #(type T=...)`) at all yet, and
that construct is the backbone of UVM itself (`uvm_component#(T)`,
`uvm_analysis_port#(T)`, etc.) — so no UVM code, real or stub, real
project or textbook example, can be elaborated in this environment.
I've manually reviewed every file for signature/type consistency
(factory `type_id::create` calls, analysis port/imp connections,
`uvm_config_db` get/set pairs, enum scoping), but a real compile on
Questa/VCS/Xcelium is the only way to be certain it's clean — please
run it there and send me any errors if you hit them.
