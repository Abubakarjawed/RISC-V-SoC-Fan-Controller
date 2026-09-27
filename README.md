# RISC-V SoC Fan Controller & Telemetry System

A 32-bit RISC-V (RV32I) System-on-Chip (SoC) integrated with a 4-way APB interconnect, SPI telemetry interface, PWM fan controller, Configuration SRAM, and UART communication interface. Fully verified using SystemVerilog Assertions (SVA) and a complete UVM system-level verification framework.

---

## 🏗️ System Architecture

```
                       +-------------------------+
                       |      RV32I Core         |
                       +-------------------------+
                                   |
                       +-------------------------+
                       |    CPU-APB Bridge       |
                       +-------------------------+
                                   | (Master APB Bus)
        +--------------------------+--------------------------+
        |                          |                          |
+---------------+          +---------------+          +---------------+          +---------------+
| SPI Telemetry |          | PWM Fan Ctrl  |          | Config SRAM   |          | UART Console  |
|  (0x1000_0000)|          |  (0x1001_0000)|          |  (0x1002_0000)|          |  (0x1003_0000)|
+---------------+          +---------------+          +---------------+          +---------------+
```

---

## 🗺️ SoC Address Map

All peripherals use 32-bit APB memory mapping:

| Peripheral | Base Address | Description |
| :--- | :--- | :--- |
| **SPI Subsystem** | `0x1000_0000` | SPI Telemetry Interface (Control, Status, TX/RX Data) |
| **PWM Subsystem** | `0x1001_0000` | Fan Speed Controller & Tachometer Measurement |
| **Config SRAM** | `0x1002_0000` | On-chip Configuration SRAM |
| **UART Subsystem** | `0x1003_0000` | Serial Console Communication (TX/RX Registers) |
| **Core DMEM** | `0x2000_0000` | Data Memory |

---

## 📂 Repository Structure

```
├── rtl/                        # Synthesizable RTL Source Code
│   ├── cpu/                    # RV32I Core (ALU, Decoder, PC, Regfile, Control)
│   ├── apb/                    # APB Interconnect & CPU-APB Bridge
│   ├── spi/                    # SPI Subsystem Top & Engine
│   ├── pwm/                    # PWM Engine & Tachometer Subsystem
│   ├── sram/                   # Configuration SRAM Subsystem
│   ├── uart/                   # UART Engine, APB Wrapper & Baud Generator
│   ├── memory/                 # Instruction & Data Memories (IMEM/DMEM)
│   └── soc_top.sv              # Top-Level System-on-Chip Integration
│
├── uvm_tb/                     # UVM Verification Testbenches
│   ├── common/                 # APB Interface, APB Transaction Package, SVA Assertions
│   ├── spi/                    # SPI UVM Package & Block Testbench
│   ├── pwm/                    # PWM UVM Package & Block Testbench
│   ├── sram/                   # SRAM UVM Package & Block Testbench
│   ├── uart/                   # UART UVM Package & Block Testbench
│   └── system/                 # System UVM Top Environment (`system_pkg.sv`, `tb_system_uvm_top.sv`)
│
└── tb/                         # Direct SystemVerilog Testbenches & Virtual UART Terminal
```

---

## 🧪 Verification & Test Suite

The system includes multi-layer verification:
1. **SystemVerilog Assertions (SVA)**: Protocol checking for APB transactions (`apb_assertions.sv`) and PWM waveform timing (`pwm_assertions.sv`).
2. **Block-Level UVM Environments**: Dedicated environments for SPI, PWM, Config SRAM, and UART.
3. **System-Level UVM Environment**: Full SoC testbench running directed and constrained-random sequences across all 4 peripherals simultaneously.

### Running Simulations with QuestaSim / ModelSim

* **Run Directed System UVM Test**:
  ```bash
  vsim -c -suppress 7061 tb_system_uvm_top +UVM_TESTNAME=system_base_test -do "run -all; quit"
  ```

* **Run Constrained-Random System UVM Test**:
  ```bash
  vsim -c -suppress 7061 tb_system_uvm_top +UVM_TESTNAME=system_random_test -do "run -all; quit"
  ```

---

## 📄 License
Project created as part of the Capstone SoC Design & Verification Project.
